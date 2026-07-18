#if os(macOS)
import AppKit
import Combine
import SwiftUI
import WinLiftAppCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?

    private var terminationWatcher: AnyCancellable?
    private var terminationTimeoutTask: Task<Void, Never>?
    private var wantsGracefulShutdown = false
    private var shutdownRequestSent = false
    private var forceStopSent = false

    /// 正常关机迟迟未完成时，隔这么久再次询问用户。
    private static let terminationTimeout: UInt64 = 90_000_000_000

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model, model.runtime.state.isActive else { return .terminateNow }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Windows 仍在运行"
        alert.informativeText = """
        可以先发送正常关机请求，等 Windows 退出后自动关闭 WinLift。\
        强制停止会立即结束 QEMU，可能损坏虚拟机磁盘。\
        如果关机迟迟没有完成，可以回到窗口中改用强制停止。
        """
        alert.addButton(withTitle: "正常关机后退出")
        alert.addButton(withTitle: "取消")
        alert.addButton(withTitle: "强制停止并退出")
        if alert.buttons.count == 3 {
            alert.buttons[2].hasDestructiveAction = true
        }

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            beginTermination(model: model, graceful: true)
            return .terminateLater
        case .alertThirdButtonReturn:
            beginTermination(model: model, graceful: false)
            return .terminateLater
        default:
            return .terminateCancel
        }
    }

    private func beginTermination(model: AppModel, graceful: Bool) {
        wantsGracefulShutdown = graceful
        shutdownRequestSent = false
        forceStopSent = false

        advanceTermination(model: model)
        terminationWatcher = model.runtime.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak model] _ in
                Task { @MainActor [weak self, weak model] in
                    guard let self, let model else { return }
                    self.advanceTermination(model: model)
                }
            }
        scheduleTerminationTimeout(model: model)
    }

    private func advanceTermination(model: AppModel) {
        let runtime = model.runtime

        guard runtime.state.isActive else {
            finishTerminationWatchers()
            NSApp.reply(toApplicationShouldTerminate: true)
            return
        }

        if wantsGracefulShutdown {
            // .starting 阶段 QMP 尚未就绪；等状态推进后再发送关机。
            if !shutdownRequestSent, runtime.canRequestShutdown {
                shutdownRequestSent = true
                runtime.requestShutdown()
            }
        } else if !forceStopSent {
            forceStopSent = true
            runtime.forceStop()
        }
    }

    private func scheduleTerminationTimeout(model: AppModel) {
        terminationTimeoutTask?.cancel()
        terminationTimeoutTask = Task { [weak self, weak model] in
            try? await Task.sleep(nanoseconds: Self.terminationTimeout)
            guard !Task.isCancelled, let self, let model else { return }
            self.handleTerminationTimeout(model: model)
        }
    }

    private func handleTerminationTimeout(model: AppModel) {
        guard model.runtime.state.isActive else { return }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Windows 还没有完成关机"
        alert.informativeText = """
        可以继续等待；也可以强制停止并退出（可能损坏虚拟机磁盘），\
        或者取消退出、回到 WinLift 继续使用。
        """
        alert.addButton(withTitle: "继续等待")
        alert.addButton(withTitle: "取消退出")
        alert.addButton(withTitle: "强制停止并退出")
        if alert.buttons.count == 3 {
            alert.buttons[2].hasDestructiveAction = true
        }

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            scheduleTerminationTimeout(model: model)
        case .alertThirdButtonReturn:
            wantsGracefulShutdown = false
            advanceTermination(model: model)
            scheduleTerminationTimeout(model: model)
        default:
            cancelTermination()
        }
    }

    private func cancelTermination() {
        finishTerminationWatchers()
        NSApp.reply(toApplicationShouldTerminate: false)
    }

    private func finishTerminationWatchers() {
        terminationWatcher = nil
        terminationTimeoutTask?.cancel()
        terminationTimeoutTask = nil
    }
}

@main
struct WinLiftApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .frame(minWidth: 900, minHeight: 620)
                .onAppear {
                    appDelegate.model = model
                }
        }
        .defaultSize(width: 1080, height: 700)
        .windowStyle(.automatic)
        .commands {
            WinLiftCommands(model: model)
        }
    }
}

private struct WinLiftCommands: Commands {
    @ObservedObject var model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("新建虚拟机…") {
                model.isPresentingCreateVM = true
            }
            .keyboardShortcut("n", modifiers: .command)
        }

        CommandMenu("虚拟机") {
            Button("启动") {
                model.startSelectedMachine()
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(!model.canStartSelectedMachine)

            if model.runtime.state == .paused {
                Button("继续") {
                    model.runtime.resume()
                }
                .keyboardShortcut("p", modifiers: .command)
                .disabled(!model.runtime.canResume)
            } else {
                Button("暂停") {
                    model.runtime.pause()
                }
                .keyboardShortcut("p", modifiers: .command)
                .disabled(!model.runtime.canPause)
            }

            Button("正常关机") {
                model.runtime.requestShutdown()
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(!model.runtime.canRequestShutdown)

            Divider()

            Button("编辑配置…") {
                model.beginEditingSelectedMachine()
            }
            .keyboardShortcut("i", modifiers: .command)
            .disabled(model.selectedMachine == nil || !model.canModifySelectedMachine)

            Button("在 Finder 中显示") {
                if let machineID = model.selectedMachineID {
                    model.revealBundle(for: machineID)
                }
            }
            .disabled(model.selectedMachine == nil)

            Button("删除虚拟机…", role: .destructive) {
                if let machine = model.selectedMachine {
                    model.requestDelete(machine)
                }
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(model.selectedMachine == nil || !model.canModifySelectedMachine)

            Divider()

            Button("刷新 QEMU 状态") {
                model.refreshQEMUInstallation()
            }
        }
    }
}
#else
// WinLift 的图形界面只在 macOS 上可用。其他平台的构建只用于编译
// WinLiftCore、运行测试和 CI 的 QEMU 冒烟脚本。
@main
enum WinLiftUnsupportedPlatformMain {
    static func main() {
        print("WinLift 的图形界面仅支持 macOS 14+（Apple Silicon）。")
        print("当前平台构建仅用于 WinLiftCore 测试与 QEMU 参数验证。")
    }
}
#endif
