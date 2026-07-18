# WinLift 架构

## 目标边界

v0.1 的目标是让 Apple Silicon Mac 用户从官方 ARM64 ISO 创建并启动一台 Windows 虚拟机，同时保持工程足够小、可测试、可继续演进。虚拟机管理和 UI 由 WinLift 负责，硬件模拟由用户独立安装的 QEMU 负责，CPU 虚拟化交给 macOS HVF。

```mermaid
flowchart TD
    UI[SwiftUI 界面] --> Model[AppModel]
    Model --> Store[VMFileStore]
    Model --> Runtime[QEMUProcessController]
    Runtime --> Builder[QEMUCommandBuilder]
    Builder --> QEMU[QEMU + HVF]
    Store --> Bundle[.winliftvm bundle]
```

## 模块

| 模块 | 职责 |
| --- | --- |
| `WinLiftCore` | VM 值类型、校验、路径布局、QEMU 探测和纯命令生成 |
| `VMFileStore` | JSON 配置加载/保存和 artifact 存在性检查 |
| `VMProvisioner` | 原子式创建 VM bundle、稀疏磁盘和 EFI 变量文件 |
| `QEMUProcessController` | 子进程、节流日志和 QMP 事件驱动生命周期控制 |
| `AppModel` | UI 用例编排、选择状态和错误呈现 |
| `Views` | macOS sidebar/detail/create sheet |

## 设备选择

- `-accel hvf -cpu host`：同架构硬件加速。
- `nvme` + raw sparse disk：避免 Windows 安装阶段依赖 VirtIO 磁盘驱动。
- `nec-usb-xhci`、`usb-kbd`、`usb-tablet`：Windows 原生 USB 输入设备。
- `usb-net` + user-mode networking：优先使用客体自带的 USB/RNDIS 类驱动，不要求桥接权限。
- `usb-audio` + CoreAudio：简单的播放通道。
- `ramfb`：无需额外驱动的基础 framebuffer。
- 两个 pflash：只读 EDK2 代码和每台 VM 独立的可写变量存储。

## 生命周期

QEMU 以 `-qmp stdio` 启动。纯逻辑 `QMPStreamParser` 保留跨回调的字节缓冲，按换行拆分完整 JSON，并区分 greeting、return 与 event；因此任意行中分片或一次多行都不会丢失。WinLift 等待 greeting，发送 `qmp_capabilities`，之后用：

- `stop` 暂停；
- `cont` 恢复；
- `system_powerdown` 触发 ACPI 正常关机。

运行状态最终由 QMP 事件校正：`STOP` → paused、`RESUME` → running、
`SHUTDOWN`/`POWERDOWN` → stopping。暂停与继续仍可乐观更新以获得即时反馈。

QEMU stdout/stderr 会立即追加到磁盘日志，但 UI 只约每 250 ms 批量发布一次；
启动前若 `qemu.log` 超过 5 MiB，则轮转为 `qemu.log.old`。

“强制停止”只作为恢复手段，它向 QEMU 发送终止信号，可能导致客体文件系统损坏。

## 持久化不变量

- bundle 目录始终由 UUID 命名，显示名称不会影响磁盘路径。
- `config.json` 原子写入。
- 创建任一 artifact 失败时只回滚本次新建的 bundle。
- 创建的文件系统 provision 在后台任务执行，所有可观察 UI 状态仍由 `AppModel` 的 MainActor 更新。
- ISO 保持外部引用，不复制 Microsoft 安装介质。
- 只有关闭 ISO 挂载后，配置才允许没有 installer 路径。

## QEMU 安装体检

`QEMUDiscovery` 保持外置探测，不捆绑 QEMU。Apple Silicon 上会直接读取
Mach-O 或 fat header，拒绝 x86_64-only QEMU；固件必须恰好为 64 MiB。
`qemu-system-aarch64 --version` 的输出由纯解析器提取并显示在侧栏状态区。

## 后续演进

TPM/Secure Boot 应作为一个完整阶段实现：管理独立 `swtpm` 进程、持久化 TPM state、用 Unix socket 连接 QEMU，并在启动失败时确保两个进程一致回收。不要只添加几个 QEMU 参数而遗漏进程所有权和恢复逻辑。
