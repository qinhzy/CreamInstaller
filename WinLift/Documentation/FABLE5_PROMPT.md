# 给 Fable 5 的完整工程 Prompt

复制下面整个 Prompt 给 Fable 5。若把本仓库同时交给它，把第一句改成“继续完善当前 WinLift 仓库，不要重新脚手架”。

---

你是一名资深 macOS 虚拟化工程师。请在当前空仓库中从零完成一个名为 **WinLift** 的、可编译运行的 macOS 原生应用。它让 Apple Silicon Mac 用户创建、安装和运行 Windows 11 ARM64 虚拟机。

不要只输出教程、伪代码、界面原型或零散代码片段；直接创建完整工程，完成实现、测试和构建验证。可逆的实现细节自行判断，只有继续工作会明显违背产品意图时才询问。

## 产品边界

- 目标平台：Apple Silicon，macOS 14+。
- UI：SwiftUI，使用符合 macOS 习惯的 `NavigationSplitView`，左侧 VM 列表，右侧详情和运行控制；支持浅色/深色模式。
- 工程：SwiftPM executable app，Swift 5.9+，不要引入第三方 Swift 包。
- 虚拟化后端：**QEMU `qemu-system-aarch64` + `-accel hvf -cpu host`**。MVP 不以 `Virtualization.framework` 作为 Windows 后端，因为它没有完整的 Windows 客体设备/驱动体验。
- QEMU 由用户通过 `brew install qemu` 独立安装。本版本只探测和调用它，不下载、不捆绑、不重新分发 QEMU，也不自动下载 Windows。
- 安装介质必须由用户选择 Microsoft 官方 Windows 11 ARM64 ISO。
- 当前只允许同时运行一台 VM；把这个约束在 UI 中说清楚。

## 必须实现的功能

1. 新建 VM：名称、CPU、内存、磁盘容量、ARM64 ISO。
2. 建议默认值：主机一半 CPU（2–8 核范围内）、主机一半内存（4–16 GiB 范围内）、64 GiB 磁盘。
3. 数据保存到 `~/Library/Application Support/WinLift/Virtual Machines/<UUID>.winliftvm/`：
   - `config.json`
   - `disk.raw`
   - `efi-vars.fd`
   - `qemu.log`
4. `disk.raw` 必须使用稀疏文件，不能真的预写 64 GiB 零数据。VM 创建中途失败时，只回滚本次新建的 bundle。
5. 探测以下 QEMU 位置，并允许环境变量覆盖：
   - `/opt/homebrew/bin/qemu-system-aarch64`
   - `/usr/local/bin/qemu-system-aarch64`
   - `/opt/local/bin/qemu-system-aarch64`
   - `PATH`
   - `WINLIFT_QEMU_SYSTEM`
6. 探测 `edk2-aarch64-code.fd`，允许 `WINLIFT_QEMU_FIRMWARE` 覆盖。处理 Homebrew symlink 后的 Cellar `share/qemu` 路径。
7. QEMU 配置必须使用：
   - ARM `virt` machine、GICv3、HVF、host CPU；
   - 两个 pflash：只读 EDK2 code + 每 VM 可写 EFI vars；
   - raw 磁盘通过 NVMe 暴露，避免 Windows 安装时依赖 VirtIO 磁盘驱动；
   - `nec-usb-xhci`、`usb-kbd`、`usb-tablet`，输入和安装介质显式挂到同一 USB bus；
   - ISO 用只读 raw drive + `usb-storage`；
   - user-mode network + `usb-net`；
   - CoreAudio + `usb-audio`；
   - `ramfb` 和 Cocoa display；
   - `-qmp stdio`、`-monitor none`、`-serial none`。
8. 路径直接作为 `Process.arguments` 数组元素传递，绝不能拼 shell 命令。QEMU 子选项中的逗号必须按 QEMU 规则双写转义。
9. 生命周期：
   - 等待 QMP greeting 后发送 `qmp_capabilities`；
   - 暂停发送 `stop`；
   - 恢复发送 `cont`；
   - 正常关机发送 `system_powerdown`；
   - 强制停止必须放在次级菜单并明确警告数据损坏风险。
10. 捕获 stdout/stderr，界面显示有界日志并写入 `qemu.log`。进程退出后正确恢复 UI 状态；非预期非零退出应显示错误。
11. Windows 安装完成后允许关闭 ISO 挂载，并在 UI 中明确提示这一动作。
12. 提供“在 Finder 中显示 VM bundle”、QEMU 缺失提示和官方 Windows ARM64 ISO 下载链接。
13. 给每台 VM 配置 QEMU `-pidfile`。App 重启后若 pidfile 指向仍存活的进程，禁止再次打开同一磁盘；只有 `kill(pid, 0)` 证明进程不存在时才清理 stale pidfile。虚拟机运行时阻止正常退出 WinLift，构建脚本也不得杀掉控制器并遗留 QEMU。

## 代码结构与质量

- 建立 `WinLiftCore` library target，放入不依赖 SwiftUI/AppKit 的纯逻辑：`VirtualMachine`、校验、存储布局、QEMU 探测、QEMU 参数生成。
- executable target 中分离 `Models`、`Services`、`Views`、`App`。不要把所有内容塞进一个 `ContentView.swift`。
- UI 状态必须在 `@MainActor` 上；pipe readability handler 和 termination handler 回到 MainActor 后才能更新可观察状态。
- 不要使用 `try!`、强制解包路径或静默吞掉影响用户的错误。
- 使用系统语义颜色和 material；sidebar 保持原生 source-list 风格，不要铺满自定义卡片。
- 重要操作同时提供按钮和键盘菜单入口。
- 不要把 Windows ISO、产品密钥、用户路径或虚拟磁盘提交到 Git。

## 测试与验收

至少写 XCTest 覆盖：

- 合法/非法 CPU、内存、磁盘和 ISO 配置；
- UUID bundle 路径不变量；
- QEMU 参数包含 HVF、NVMe、USB 输入/网络、QMP；
- 关闭 ISO 后命令中不再出现 installer drive；
- 含逗号路径的转义；
- QEMU 环境变量覆盖探测。

提供：

- `script/build_and_run.sh`：停止旧 WinLift、`swift build`、生成真正的 `dist/WinLift.app`、adhoc codesign、用 `open -n` 启动；支持 `--debug`、`--logs`、`--telemetry`、`--verify`。
- `.codex/environments/environment.toml` 的 Run action。
- 中文 `README.md`：依赖、构建、安装 Windows、数据目录、限制、许可。

最终必须在真实 macOS 环境执行：

```bash
swift test
./script/build_and_run.sh --verify
```

如果构建失败，继续修到测试通过且 App 能启动。不要声称已经验证未实际执行的步骤。交付时只报告：核心设计、已实现内容、测试/构建结果、仍然存在的技术限制。

## 明确的非目标

- v0.1 不做 Intel Mac/x64 Windows。
- v0.1 不做 3D 游戏性能承诺。
- v0.1 不做快照、克隆、共享文件夹、剪贴板同步、USB 直通 UI。
- v0.1 不捆绑 QEMU，不规避 QEMU 的 GPL 义务。
- v0.1 可暂不实现 TPM/Secure Boot，但 README 必须解释 Windows 安装检查和开发测试绕过；后续实现 TPM 时必须把 `swtpm` 进程所有权、持久化 state、socket 生命周期和异常回收作为一个完整功能完成。

---
