# 给 Codex 的 WinLift 继续开发 Prompt

把下面整段 Prompt 交给 Codex。项目位于仓库的 `WinLift/` 目录。

---

你是一名资深 macOS 虚拟化工程师。请**继续完善当前仓库中的 WinLift 项目，不要重新脚手架、不要改变既有架构**。开始前先完整阅读 `WinLift/` 下的 README.md、Documentation/ARCHITECTURE.md、Documentation/VERIFICATION.md 和全部源码。

## 项目现状（必须先理解，不要推翻）

WinLift 是 Apple Silicon Mac 上的 Windows 11 ARM64 虚拟机管理器：SwiftUI 管理界面 + 用户自装的 QEMU `qemu-system-aarch64` + Apple HVF 加速 + NVMe 磁盘 + ARM64 UEFI（EDK2 双 pflash）+ QMP stdio 生命周期控制。SwiftPM 工程，Swift 5.9+ 语法、实际由 Xcode 15.4（Swift 5.10）编译，macOS 14+，**禁止引入第三方 Swift 包**。

Target 布局（不要合并或改名）：
- `WinLiftCore`：纯逻辑库（VM 值类型、校验、存储布局、QEMU 探测、参数生成），macOS/Linux 双平台编译。
- `WinLiftAppCore`：App 逻辑与视图库（Models/Services/Views），macOS 专属文件用 `#if os(macOS)` 守卫，Linux 上编译为空以便跑测试。
- `WinLift`：executable，只含入口与 AppDelegate，通过小的 public API 面使用 WinLiftAppCore。
- `QEMUArgsDump`（产品名 `winlift-qemu-args`）：输出与 App 同源的 QEMU argv，供脚本验证。
- 测试：`WinLiftCoreTests` + `WinLiftAppTests`，当前共 36 个，全部必须保持通过。

验证基础设施（已存在，必须继续使用）：
- 仓库根 `.github/workflows/winlift.yml`：macos-14（Apple Silicon）job 跑 `swift test` + `./script/build_and_run.sh --verify`（构建 .app、adhoc 签名、启动并确认进程）；ubuntu-24.04（swift:6.0.3-noble 容器）job 跑 Linux 侧 `swift test` + `python3 script/qemu_smoke_linux.py`。
- `script/qemu_smoke_linux.py`：用 `winlift-qemu-args` 生成的真实参数在 Linux QEMU（TCG）上引导 EDK2 并驱动完整 QMP 生命周期，只替换 `hvf`→`tcg`、`host`→`cortex-a72`、`cocoa`→`none`、`coreaudio`→`none` 四个值。

## 本轮任务（按优先级实现）

### 任务 1：CI 截图闭环（最高优先级）
macOS job 在 `--verify` 启动 App 后等待约 4 秒，用 `screencapture -x` 截取屏幕（能定位窗口则只截窗口），以 `actions/upload-artifact@v4` 上传 PNG。可选加分：切换深色模式再截一张。验收标准：workflow artifact 中能看到 WinLift 主窗口的真实渲染。

### 任务 2：QMP 事件驱动状态机
`QEMUProcessController.consumeQMPOutput` 目前只扫描 greeting，丢弃了 QEMU 的 STOP/RESUME/SHUTDOWN/POWERDOWN 事件；暂停/继续是乐观置位。改为：
- 把「字节流 → 按行拆分 → JSON 分类（greeting/return/event）」抽成**可独立测试的纯解析器**（放 WinLiftAppCore 的非隔离类型或 WinLiftCore），必须正确处理 chunk 在行中间断开、一次到达多行的情况；
- 事件驱动状态：STOP→`.paused`，RESUME→`.running`，SHUTDOWN（guest 发起）→`.stopping`；客体在 Windows 里自行关机时 UI 要立刻显示"正在关机"；
- `pause()`/`resume()` 可保留即时反馈，但最终以事件为准校正；
- 新增单元测试：喂入分片字节流断言事件序列与状态迁移（含行边界拆分用例）。

### 任务 3：异步创建虚拟机
`AppModel.createVM` 目前同步跑在 MainActor 上（含写 64 MiB EFI 变量文件），会卡 UI 且表单里的 ProgressView 永远不会显示。把 provision 移到后台执行，`isCreatingVM` 真正生效，错误回主线程呈现。相应更新 `WinLiftAppTests` 中的调用（可能变 async）。防重复提交语义保持。

### 任务 4：QEMU 安装体检
- 读取 QEMU 二进制的 Mach-O/fat header（纯 Swift 读文件头，不要调用 lipo），检测是否含 arm64 切片；Apple Silicon 上发现 x86_64-only 时给出明确文案"检测到 Intel 版 QEMU，HVF 不可用，请安装 arm64 版"；
- 校验固件文件尺寸必须为 64 MiB，不符给专门文案；
- 运行 `qemu-system-aarch64 --version` 解析版本并显示在 UI 的 QEMU 状态区；
- 以上全部配单元测试（构造假 Mach-O 头文件、版本字符串解析、固件尺寸）。

### 任务 5：中等项打包
- 日志节流：QEMU 输出先入缓冲，每约 250ms 批量发布一次 `logText`，避免启动期高频重排；
- `qemu.log` 启动时若超 5 MB 轮转为 `qemu.log.old`；
- `isInstallerMissing` 改为模型内缓存（reload/替换 ISO/开关挂载/启动前刷新），侧栏不再每次渲染做文件 stat；
- `VMValidator` 增加 `hostMemoryGiB` 参数，内存上限取 `min(128, 主机内存)`（与 CPU 同样的机制），配测试；
- 详情页新增"重置 EFI 变量"（仅停止时可用，确认对话框，重建 64 MiB 0xFF 文件），配测试；
- 详情页停止状态提供"查看日志文件"（`NSWorkspace` 打开 qemu.log）。

## 硬性约束

- 架构不变：QEMU 外置探测（不捆绑）、`-accel hvf -cpu host`、NVMe raw 稀疏盘、双 pflash、USB 键鼠/网络/音频、ramfb + Cocoa、`-qmp stdio`、pidfile 防重入。参数经 `Process.arguments` 数组传递，QEMU 子选项逗号双写转义。
- 现有功能与测试不得回退：删除进废纸篓、编辑/磁盘只增不减扩容、更换 ISO/拖放、优雅退出 90 秒看门狗、菜单快捷键（⌘N/⌘R/⌘P/⇧⌘R/⌘I/⌘⌫）。
- `#if os(macOS)` 守卫策略保持，Linux 上 `swift test` 必须继续可编译可运行。
- 不要用 `try!`、强制解包路径或吞掉用户可见错误；UI 状态只在 `@MainActor` 上改。
- 不提交 ISO、虚拟磁盘、用户路径到 Git。

## 已知编译/测试陷阱（前几轮实际踩过，别再踩）

1. Swift 5.10 下，`Task { self?.xxx }` 隐式捕获外层 `[weak self]`（可变绑定）是**硬错误**：并发闭包必须写显式捕获列表 `Task { @MainActor [weak self] in ... }`。
2. `@MainActor` 隔离的默认参数值需要 Swift 5.10+（SE-0411）；README 承诺 5.9，请在函数体内构造。
3. XCTestCase 子类整类标 `@MainActor` 在 Swift 6 是错误：逐个测试方法标注。
4. `URL ==` 对目录尾斜杠敏感：路径比较用 `.standardizedFileURL.path`。
5. `createdAt` 经 ISO8601 编码丢亚秒精度：测试不要对 Date 做全值相等比较。
6. Python 冒烟脚本严禁 `select()` + 带缓冲 `readline()` 混用（QEMU 一次写多行会丢行）：用读线程 + 队列（现有实现已如此）。
7. `-name` 必须显式 `guest=` 键，否则名字含 `=` 会被解析成未知子选项。
8. macOS runner 无嵌套虚拟化：HVF 在 CI 不可用，不要试图在 CI 里真启动 Windows。

## 验证与交付（诚实性要求，逐条执行）

1. 本地能跑什么跑什么：Linux 容器可跑 `swift test`（守卫使然）与 `python3 script/qemu_smoke_linux.py`；macOS 专属验证（App 构建/启动/截图）**必须**通过推送分支让 GitHub Actions 的 macos-14 job 执行，并在交付说明中引用具体 run 编号与结果。
2. 最终必须达到：两个 CI job 全绿；`swift test` 全部通过（36 个既有 + 新增）；`--verify` 通过；冒烟脚本通过；截图 artifact 产出。
3. **绝对不要声称执行了实际没有执行的验证**。哪一步在你的环境跑不了，就明确写"未在本环境执行，由 CI run #N 验证"或"需要真机人工验证"。
4. 更新 README.md（新功能）与 Documentation/VERIFICATION.md（CI 记录表追加行），交付时报告：改动内容、测试/CI 结果（含 run 编号）、仍存在的限制。

## 本轮非目标

SPICE 画面嵌入主窗口、swtpm/TPM/Secure Boot、QMP Unix socket 崩溃重接管（这三项是后续独立轮次，需要单独设计）；磁盘缩容（数据毁灭性，现有拒绝行为有测试钉住，不许改）；Intel Mac / x64 Windows；3D 加速承诺。

---
