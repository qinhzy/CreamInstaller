# WinLift

WinLift 是一个面向 Apple Silicon Mac 的 Windows 11 ARM64 虚拟机管理器 MVP。它使用原生 SwiftUI 管理虚拟机，用 QEMU 模拟设备，并通过 Apple Hypervisor Framework（`hvf`）进行硬件加速。

> 当前版本是可评审的开发者 MVP，不是 Parallels Desktop 的完整替代品。它可以创建虚拟磁盘、挂载 Windows ARM64 ISO、启动 QEMU 图形窗口，并通过 QMP 完成暂停、恢复和正常关机。

## 为什么使用 QEMU

Apple 的 `Virtualization.framework` 主要面向 macOS 和 Linux 客体。WinLift 的 Windows MVP 使用 QEMU，是为了给 Windows 提供更合适的标准设备组合：NVMe 磁盘、USB 键鼠、USB 网络、RAM framebuffer 和 ARM64 UEFI；CPU 仍由 `hvf` 原生加速。

## 系统要求

- Apple Silicon Mac（M1 或更新）
- macOS 14 或更新版本
- Xcode 15+ 或 Command Line Tools（提供 Swift 5.9+）
- [Homebrew QEMU](https://formulae.brew.sh/formula/qemu)（必须包含 arm64 切片，EDK2 固件必须为 64 MiB）
- [Windows 11 ARM64 ISO](https://www.microsoft.com/software-download/windows11arm64)

安装 QEMU：

```bash
brew install qemu
```

## 构建与运行

```bash
./script/build_and_run.sh
```

脚本会执行 SwiftPM 构建、生成 `dist/WinLift.app`、临时签名并启动应用。其他模式：

```bash
./script/build_and_run.sh --verify
./script/build_and_run.sh --debug
./script/build_and_run.sh --logs
```

运行核心测试：

```bash
swift test
```

## 验证与调试工具

- `swift run winlift-qemu-args --root <VM 根目录> --qemu <qemu 路径> --firmware <code.fd> [--iso <ISO>]`
  输出 WinLift 实际用于启动 QEMU 的完整参数（每行一个），与应用共用同一份
  `QEMUCommandBuilder`，便于排障和脚本验证。
- `script/qemu_smoke_linux.py`（Linux/CI 专用）：用真实的 `qemu-system-aarch64` + EDK2
  固件按上面生成的参数执行完整 QMP 生命周期冒烟测试，只替换 `hvf`、`host`、
  `cocoa`、`coreaudio` 四个 macOS 专属值，其余参数与 macOS 上完全一致。
- 仓库根目录的 `.github/workflows/winlift.yml` 会在 macos-14（Apple Silicon）上运行
  `swift test` 与 `./script/build_and_run.sh --verify`，并在 Linux 上运行核心测试与
  QEMU 冒烟测试；macOS job 还会在 App 启动后截取真实主窗口并上传 PNG artifact。
  实际执行记录见 `Documentation/VERIFICATION.md`。

## 安装 Windows

1. 在 WinLift 中点“新建虚拟机”。
2. 选择 Microsoft 官方 Windows 11 ARM64 ISO。
3. 建议至少分配 4 个 CPU 核心、8 GiB 内存和 64 GiB 磁盘。
4. 点“启动”。Windows 安装器会出现在独立的 QEMU Cocoa 窗口中。
5. 完成安装并首次进入桌面后，正常关闭 Windows，然后在 WinLift 中关闭“启动时挂载 Windows ISO”。

Windows 11 可能因为当前 MVP 没有虚拟 TPM/Secure Boot 而阻止安装。若出现“此电脑无法运行 Windows 11”，在安装界面按 `Shift+F10`（部分 Mac 键盘需加 `Fn`），执行：

```bat
reg add HKLM\SYSTEM\Setup\LabConfig /v BypassTPMCheck /t REG_DWORD /d 1 /f
reg add HKLM\SYSTEM\Setup\LabConfig /v BypassSecureBootCheck /t REG_DWORD /d 1 /f
```

关闭命令提示符并重新继续安装。这个绕过方式只适合开发测试；是否获得 Microsoft 支持取决于 Windows 的当前政策和你的许可条件。

## 数据位置

虚拟机保存在：

```text
~/Library/Application Support/WinLift/Virtual Machines/
└── <UUID>.winliftvm/
    ├── config.json
    ├── disk.raw
    ├── efi-vars.fd
    ├── qemu.log
    ├── qemu.log.old      # qemu.log 超过 5 MiB 后的上一轮日志
    └── qemu.pid          # 仅运行时存在
```

`disk.raw` 是稀疏文件：Finder 显示的是虚拟容量，实际磁盘占用随客体写入增长。

## 已实现

- 原生 macOS `NavigationSplitView` 管理界面，自带应用图标
- VM 创建、编辑（名称/CPU/内存/磁盘扩容）、删除（移到废纸篓，二次确认）
- VM 配置校验和 JSON 持久化
- 稀疏 RAW 磁盘与持久化 EFI 变量存储；磁盘只增不减的在线扩容
- VM 创建在后台完成，64 MiB EFI 初始化期间表单会显示真实进度且阻止重复提交
- Homebrew、MacPorts 和环境变量形式的 QEMU/UEFI 自动探测；后台检查 QEMU arm64 Mach-O 切片、64 MiB 固件与版本，版本进程 5 秒超时，不阻塞界面
- ARM64 + HVF 启动参数
- NVMe、NEC xHCI、USB 键鼠、USB RNDIS 网络、USB 音频、RAM framebuffer
- ISO 挂载/弹出、更换 ISO（按钮或直接拖放 .iso）、ISO 文件缺失警示
- 分片安全的 QMP 行/JSON 解析；STOP、RESUME、SHUTDOWN、POWERDOWN 事件驱动暂停、运行和关机状态
- QMP 暂停、恢复、ACPI 关机与强制停止（强制停止有确认对话框）；控制通道写入失败时不再发布虚假的暂停/运行/关机状态
- 运行 PID 防重入；运行中退出可选“正常关机后退出”或“强制停止并退出”
- 完整菜单栏命令与快捷键（⌘N 新建、⌘R 启动、⌘P 暂停/继续、⇧⌘R 关机、⌘I 编辑、⌘⌫ 删除）、侧栏右键菜单
- 运行时长显示、有界运行日志（约 250 ms 批量刷新、自动滚动、一键复制）；qemu.log 超过 5 MiB 自动轮转
- 停止状态可在后台原子重置 64 MiB EFI 变量存储（操作期间锁定冲突动作）、用系统默认应用查看 qemu.log
- ISO 缺失状态按加载/替换/挂载切换/启动节点缓存刷新，侧栏重绘不再重复访问文件系统
- 安装小贴士卡片：TPM/Secure Boot 检查绕过命令一键复制
- 53 项核心/App 测试，覆盖命令生成、QMP 分片与状态迁移、Mach-O/fat 解析、版本执行/超时与固件体检、主机资源校验、存储和交互逻辑

## 当前限制

- 一次只管理一台正在运行的虚拟机。
- QEMU 显示在独立窗口，尚未嵌入 WinLift 主窗口。
- 没有 TPM 2.0、Secure Boot、快照、克隆、共享目录、剪贴板同步和 USB 直通 UI。
- RAM framebuffer 适合安装和基本桌面，不提供 Parallels 级别的 3D 加速；不适合游戏。
- 运行中退出 WinLift 时会引导你选择"正常关机后退出"（等 Windows 退出后自动关闭，90 秒未完成会再次询问，可随时取消）或"强制停止并退出"。强制停止可能损坏客体文件系统。
- Intel Mac 和 x64 Windows 不在当前范围内。

下一阶段的合理顺序是：`swtpm`/Secure Boot → QMP Unix socket 与状态恢复 → 快照 → SPICE 显示及剪贴板 → 打包与更新机制。

## 环境变量

若 QEMU 不在常规位置，可显式指定：

```bash
export WINLIFT_QEMU_SYSTEM=/path/to/qemu-system-aarch64
export WINLIFT_QEMU_FIRMWARE=/path/to/edk2-aarch64-code.fd
```

## 许可

WinLift 源码使用 MIT License。QEMU 是独立安装的 GPL-2.0-only 软件；当前项目不重新分发 QEMU 二进制。
