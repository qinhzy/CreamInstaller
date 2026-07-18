# 验证记录

本文件只记录**实际执行过**的验证，以及明确未执行、需要真机完成的步骤。
最近一次更新对应分支 `claude/winlift-completion-testing-tgsokj`。

## 一、GitHub Actions（真实 Swift 工具链）

工作流：仓库根目录 `.github/workflows/winlift.yml`。

### macos-14 runner（Apple Silicon，arm64）

- `swift test`：编译全部 target（WinLiftCore、WinLift App、winlift-qemu-args、测试）并运行完整 XCTest 套件。
- `./script/build_and_run.sh --verify`：SwiftPM 构建、生成 `dist/WinLift.app`、adhoc 签名、`open -n` 启动并确认进程存活。
- App 存活后等待约 4 秒，优先按窗口 ID 截取 WinLift 主窗口，无法取得窗口 ID 时回退为全屏截图；PNG 由 `actions/upload-artifact@v4` 上传。

结果见下方"CI 运行记录"。

### ubuntu-24.04 runner（swift:6.0.3-noble 容器）

- `swift test`：借助 `#if os(macOS)` 守卫在 Linux 上编译核心库与测试并全部运行。
- `python3 script/qemu_smoke_linux.py`：见下节。

## 二、QEMU 参数与生命周期冒烟测试（真实 QEMU）

`script/qemu_smoke_linux.py` 使用 `swift run winlift-qemu-args`（与 App 完全相同的
`QEMUCommandBuilder`）生成 argv，只替换四个 macOS 专属值（`hvf`→`tcg`、
`host`→`cortex-a72`、`cocoa`→`none`、`coreaudio`→`none`），其余参数逐字节一致，
然后对真实的 `qemu-system-aarch64` + EDK2 固件执行：

1. QMP greeting → `qmp_capabilities`；
2. `query-status` 断言 running；
3. pidfile 已创建；
4. `stop` → 断言 paused；`cont` → 断言 running；
5. `screendump` 断言 EDK2 确实通过 ramfb 渲染了画面（非纯色）；
6. `system_powerdown`、`quit`，断言退出码 0 且 pidfile 被清理；
7. 断言 `disk.raw` 保持稀疏（64 GiB 表观，实占接近 0）。

该脚本在交付环境（Ubuntu 24.04，QEMU 8.2.2 + AAVMF/EDK2）中已实际执行通过。
截屏显示 EDK II UEFI Shell 的映射表中同时枚举出 NVMe 系统盘
（`PciRoot/Pci(0x1,0x0)/NVMe`）和 xHCI 上的 USB 安装介质（`Pci(0x2,0x0)/USB`），
证明固件、pflash、NVMe、xHCI/USB 拓扑与引导路径全部按设计工作。
另外单独验证了 QEMU 的双逗号转义：`file=/…/path,,with commas/disk.raw`
成功打开了真实路径 `path,with commas/disk.raw`。

## 三、CI 运行记录

| 提交 | macOS job（macos-14 / arm64 / Swift 5.10） | Linux job（swift 6.0.3 / QEMU 8.2.2） |
| --- | --- | --- |
| `cba5b4a` run #1 | 失败：`swift test` 编译错误（Task 闭包隐式捕获可变 weak self ×3；可选参数误引用） | `swift test` 20/20 通过；冒烟失败于 harness 的 select/缓冲读丢行 |
| `3e2ac0e` run #2 | **通过**：`swift test` 20/20；`--verify` 构建 App、adhoc 签名、启动成功（"WinLift 已成功启动。"） | `swift test` 通过；冒烟仍是旧脚本，同上失败 |
| `d6a6d8e` run #3 | **通过** | **通过**：`swift test` 20/20；冒烟输出"QMP 生命周期、pidfile、稀疏磁盘（表观 64 GiB/实占 0 MiB）、EDK2 渲染全部符合预期" |
| `e184d59`/`8a82e65` run #6/#7（v0.2.0 UI/交互重构：删除/编辑/换 ISO/退出流程/菜单/图标） | **通过**：新增视图与命令全部编译，App 带图标构建并启动成功 | **通过** |
| `0173144` run #9（WinLiftAppCore 拆分 + 交互逻辑测试 + 退出看门狗） | **通过**：36/36 测试，其中 11 个 AppModel 交互测试（创建/删除进废纸篓/游离进程拦截/编辑扩容/换 ISO/ISO 缺失）与 5 个 Provisioner/Store 测试在 Apple Silicon 真机执行 | **通过**：跨平台测试 + QEMU 冒烟 |
| `2878316` run #11（Apple 原生视觉语言重设计：hero 虚拟屏幕 + 分组表单 + 图标芯片） | **通过**：36/36 测试，App 构建并启动 | **通过** |
| `a4b5ba4` [run #14](https://github.com/qinhzy/CreamInstaller/actions/runs/29638722405)（本轮功能实现） | 失败：Swift 5.10 要求 `refreshInstallerMissingCache` 的闭包显式写 `self`；因此 App 构建、启动和截图均未执行 | **通过**：39/39 测试；QEMU/EDK2 冒烟通过 |
| `a51264a` [run #15](https://github.com/qinhzy/CreamInstaller/actions/runs/29639800770)（修复 Swift 5.10 编译） | 失败：交互测试把内存固定改为 8 GiB，超过 runner 的实际主机内存上限；产品代码已编译，截图因测试失败未执行 | **通过**：39/39 测试；QEMU/EDK2 冒烟通过 |
| `3c00a25` [run #16](https://github.com/qinhzy/CreamInstaller/actions/runs/29639851298)（最终验证） | **通过**：Swift 5.10/arm64，51/51 测试；`--verify` 构建、adhoc 签名并启动成功；artifact `winlift-ui-16`（174,605 字节）已下载检查，确为 WinLift 主窗口真实渲染 | **通过**：39/39 测试；真实 QEMU/EDK2 生命周期、ramfb 渲染、pidfile 和 64 GiB 稀疏磁盘全部通过 |

最新状态请以 GitHub Actions 页面为准：
`https://github.com/qinhzy/CreamInstaller/actions/workflows/winlift.yml`

值得注意的是：`cba5b4a` 暴露的三处 Task 捕获错误在最初上传的 v0.1.0 源码中
就已存在——上传版本从未通过 macOS 编译，这正是本轮验证要解决的问题。

## 四、当前环境无法执行、必须真机完成的步骤

交付所在的容器是 Linux x86_64，无 macOS、无 Apple Silicon、无 HVF；
组织出口策略也禁止在容器内下载 Windows ISO。因此以下步骤只能在
真实 Apple Silicon Mac 上人工完成：

1. `brew install qemu` 后启动 WinLift，创建 VM 并挂载 Microsoft 官方
   Windows 11 ARM64 ISO；
2. 点"启动"，确认 QEMU Cocoa 窗口出现并进入 Windows 安装界面
   （必要时按 README 的 LabConfig 步骤绕过 TPM 检查）；
3. 确认键盘/鼠标输入、NVMe 目标磁盘在安装器中可见；
4. 完成一次重启、从 WinLift 请求正常关机，确认 `qemu.pid` 消失；
5. 安装完成后关闭"启动时挂载 Windows ISO"再次启动，确认直接进入系统。

HVF 加速路径（`-accel hvf -cpu host`）无法在任何 CI/虚拟化环境中验证
（GitHub 的 macOS runner 本身是虚拟机，不支持嵌套虚拟化）；
但除这两个值外的全部参数已经由第二节的真实 QEMU 冒烟测试覆盖。

另外说明：交互**逻辑**（异步创建、删除、编辑扩容、换 ISO、缺失缓存、
EFI 重置、pidfile 拦截）由 WinLiftAppTests 在 macOS CI 上自动化覆盖；
SwiftUI **视图层**自动验证到“编译通过 + App 成功启动 + 主窗口真实截图 artifact”。
按钮点击到后续视觉呈现之间的链路（SwiftPM 不支持 XCUITest bundle）仍需在真机上人工过一遍。
