#!/usr/bin/env python3
"""WinLift QEMU 冒烟测试（Linux / CI 专用）。

用 `winlift-qemu-args`（与 App 完全相同的 QEMUCommandBuilder）生成 argv，
只替换四个 macOS 专属值——hvf→tcg、host→cortex-a72、cocoa→none、
coreaudio→none——然后对真实的 qemu-system-aarch64 执行完整生命周期：

  QMP greeting → qmp_capabilities → query-status → stop → cont
  → screendump（校验 EDK2 通过 ramfb 真实渲染）→ system_powerdown → quit

同时校验 pidfile 的创建/清理与稀疏磁盘行为。macOS 侧的 HVF/Cocoa 验证
见 .github/workflows/winlift.yml 的 macos job 与 Documentation/VERIFICATION.md。
"""

import json
import os
import queue
import shutil
import subprocess
import sys
import tempfile
import threading
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MACHINE_ID = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"

FIRMWARE_CANDIDATES = [
    os.environ.get("WINLIFT_QEMU_FIRMWARE"),
    "/usr/share/qemu/edk2-aarch64-code.fd",
    "/usr/share/AAVMF/AAVMF_CODE.no-secboot.fd",
    "/usr/share/AAVMF/AAVMF_CODE.fd",
]


def fail(message):
    print(f"FAIL: {message}", file=sys.stderr)
    sys.exit(1)


def find_firmware():
    for path in FIRMWARE_CANDIDATES:
        if path and os.path.isfile(path):
            return path
    fail("没有找到 aarch64 EDK2 固件；请安装 qemu-efi-aarch64 或设置 WINLIFT_QEMU_FIRMWARE")


def generate_arguments(qemu, firmware, work, iso):
    dump = subprocess.run(
        [
            "swift", "run", "--package-path", ROOT, "winlift-qemu-args",
            "--root", work,
            "--qemu", qemu,
            "--firmware", firmware,
            "--id", MACHINE_ID,
            "--cpu", "2",
            "--memory", "4",
            "--disk", "64",
            "--iso", iso,
        ],
        capture_output=True, text=True, timeout=1800,
    )
    if dump.returncode != 0:
        fail(f"winlift-qemu-args 失败:\n{dump.stderr}")
    return [line for line in dump.stdout.splitlines() if line]


def substitute_for_linux(args):
    """只替换 macOS 专属值，其余参数保持与应用完全一致。"""
    result = list(args)
    substitutions = 0
    for i, arg in enumerate(result[:-1]):
        nxt = result[i + 1]
        if arg == "-accel" and nxt == "hvf":
            result[i + 1] = "tcg"; substitutions += 1
        elif arg == "-cpu" and nxt == "host":
            result[i + 1] = "cortex-a72"; substitutions += 1
        elif arg == "-display" and nxt.startswith("cocoa"):
            result[i + 1] = "none"; substitutions += 1
        elif arg == "-audiodev" and nxt.startswith("coreaudio,"):
            result[i + 1] = "none," + nxt.split(",", 1)[1]; substitutions += 1
    if substitutions != 4:
        fail(f"期望恰好 4 处 macOS 专属替换，实际 {substitutions} 处；参数生成可能已变化")
    return result


class QMP:
    """QMP over stdio。

    用后台线程逐行搬运 stdout：select 与带缓冲的 readline 混用会在
    QEMU 一次写出多行（如 return + 事件）时把后一行卡在用户态缓冲区里。
    """

    def __init__(self, proc):
        self.proc = proc
        self.lines = queue.Queue()
        threading.Thread(target=self._pump, daemon=True).start()

    def _pump(self):
        for line in self.proc.stdout:
            line = line.strip()
            if line:
                self.lines.put(line)

    def read(self, timeout=60):
        try:
            return json.loads(self.lines.get(timeout=timeout))
        except queue.Empty:
            return None

    def command(self, name, timeout=60, **arguments):
        payload = {"execute": name}
        if arguments:
            payload["arguments"] = arguments
        self.proc.stdin.write(json.dumps(payload) + "\n")
        self.proc.stdin.flush()
        while True:
            message = self.read(timeout)
            if message is None:
                fail(f"QMP {name}: 超时无响应")
            if "error" in message:
                fail(f"QMP {name}: {message['error']}")
            if "return" in message:
                return message["return"]
            print(f"  事件: {message.get('event', message)}")


def expect_status(qmp, expected, stage):
    status = qmp.command("query-status").get("status")
    print(f"{stage}: {status}")
    if status != expected:
        fail(f"{stage}: 期望 {expected}，实际 {status}")


def assert_screendump_rendered(path):
    if not os.path.isfile(path):
        fail("screendump 未生成")
    data = open(path, "rb").read()
    body = data.split(b"\n", 3)[-1]
    colors = set()
    for i in range(0, len(body) - 2, 3):
        colors.add(body[i:i + 3])
        if len(colors) > 2:
            print(f"screendump: {len(data)} 字节，>2 种颜色，固件已渲染")
            return
    fail("screendump 是纯色图像，EDK2 可能没有通过 ramfb 输出")


def main():
    qemu = os.environ.get("WINLIFT_QEMU_SYSTEM") or shutil.which("qemu-system-aarch64")
    if not qemu:
        fail("没有找到 qemu-system-aarch64；请先安装 qemu-system-arm")
    firmware = find_firmware()
    print(f"qemu: {qemu}\nfirmware: {firmware}")

    work = tempfile.mkdtemp(prefix="winlift-smoke-")
    bundle = os.path.join(work, f"{MACHINE_ID}.winliftvm")
    os.makedirs(bundle)
    disk = os.path.join(bundle, "disk.raw")
    vars_file = os.path.join(bundle, "efi-vars.fd")
    pidfile = os.path.join(bundle, "qemu.pid")
    iso = os.path.join(work, "fake-installer.iso")
    dump_path = os.path.join(work, "screendump.ppm")

    # 与 VMProvisioner 一致：稀疏磁盘 + 0xFF 擦除态 EFI 变量存储
    with open(disk, "wb") as f:
        f.truncate(64 * 1024 ** 3)
    with open(vars_file, "wb") as f:
        f.write(b"\xff" * (64 * 1024 * 1024))
    with open(iso, "wb") as f:
        f.write(b"\x00" * (8 * 1024 * 1024))

    args = substitute_for_linux(generate_arguments(qemu, firmware, work, iso))
    print("启动:", qemu, " ".join(args[:6]), "...")

    proc = subprocess.Popen(
        [qemu, *args],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, bufsize=1,
    )
    try:
        qmp = QMP(proc)
        greeting = qmp.read(60)
        if not greeting or "QMP" not in greeting:
            proc.kill()
            _, stderr = proc.communicate(timeout=15)
            fail(f"没有收到 QMP greeting。stderr:\n{stderr}")
        print("QMP greeting:", greeting["QMP"]["version"]["qemu"])

        qmp.command("qmp_capabilities")
        expect_status(qmp, "running", "启动后状态")

        if not os.path.isfile(pidfile):
            fail("QEMU 未创建 pidfile")
        print("pidfile:", open(pidfile).read().strip())

        time.sleep(12)  # 给 TCG 下的 EDK2 一点执行时间

        qmp.command("stop")
        expect_status(qmp, "paused", "stop 后状态")
        qmp.command("cont")
        expect_status(qmp, "running", "cont 后状态")

        rendered = False
        for _ in range(6):
            time.sleep(10)
            qmp.command("screendump", filename=dump_path, timeout=120)
            data = open(dump_path, "rb").read() if os.path.isfile(dump_path) else b""
            body = data.split(b"\n", 3)[-1] if data else b""
            if len({body[i:i + 3] for i in range(0, len(body) - 2, 3)}) > 2:
                rendered = True
                break
        if not rendered:
            fail("多次尝试后 screendump 仍为纯色，EDK2 可能没有渲染")
        assert_screendump_rendered(dump_path)

        # 无客体系统时固件通常忽略 ACPI 关机；只验证命令被接受。
        qmp.command("system_powerdown")
        qmp.command("quit")
        proc.wait(timeout=60)
    finally:
        if proc.poll() is None:
            proc.kill()
            proc.wait(timeout=15)

    if proc.returncode != 0:
        fail(f"QEMU 退出码非零：{proc.returncode}")
    if os.path.isfile(pidfile):
        fail("QEMU 退出后 pidfile 未被清理")
    real_blocks = os.stat(disk).st_blocks * 512
    print(f"稀疏磁盘：表观 {os.stat(disk).st_size >> 30} GiB / 实占 {real_blocks >> 20} MiB")
    if real_blocks > 1024 ** 3:
        fail("disk.raw 不是稀疏文件")

    shutil.rmtree(work, ignore_errors=True)
    print("=" * 50)
    print("QEMU 冒烟测试通过：参数集、QMP 生命周期、pidfile、稀疏磁盘、EDK2 渲染全部符合预期")


if __name__ == "__main__":
    main()
