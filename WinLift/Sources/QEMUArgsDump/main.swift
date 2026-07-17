import Foundation
import WinLiftCore

// 调试/验证工具：按 WinLift 真实的 QEMUCommandBuilder 输出 QEMU argv，
// 每行一个参数，供 script/qemu_smoke_linux.py 和人工排障使用。

func value(for flag: String) -> String? {
    let arguments = CommandLine.arguments
    guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else {
        return nil
    }
    return arguments[index + 1]
}

guard
    let root = value(for: "--root"),
    let qemu = value(for: "--qemu"),
    let firmware = value(for: "--firmware")
else {
    let usage = """
    用法: winlift-qemu-args --root <VM 根目录> --qemu <qemu-system-aarch64 路径> \
    --firmware <edk2 code.fd 路径> [--id <UUID>] [--name <名称>] [--cpu <核数>] \
    [--memory <GiB>] [--disk <GiB>] [--iso <ISO 路径>]

    """
    FileHandle.standardError.write(Data(usage.utf8))
    exit(2)
}

let machineID = value(for: "--id").flatMap(UUID.init(uuidString:)) ?? UUID()
let isoPath = value(for: "--iso")

let machine = VirtualMachine(
    id: machineID,
    name: value(for: "--name") ?? "WinLift Smoke",
    cpuCount: value(for: "--cpu").flatMap(Int.init) ?? 2,
    memorySizeGiB: value(for: "--memory").flatMap(Int.init) ?? 4,
    diskSizeGiB: value(for: "--disk").flatMap(Int.init) ?? 64,
    installerISOPath: isoPath,
    attachInstaller: isoPath != nil
)

do {
    try VMValidator.validate(machine)
} catch {
    FileHandle.standardError.write(Data("配置无效：\(error.localizedDescription)\n".utf8))
    exit(2)
}

let arguments = QEMUCommandBuilder.arguments(
    machine: machine,
    layout: VMStorageLayout(rootURL: URL(fileURLWithPath: root)),
    installation: QEMUInstallation(
        executableURL: URL(fileURLWithPath: qemu),
        firmwareURL: URL(fileURLWithPath: firmware)
    )
)

print(arguments.joined(separator: "\n"))
