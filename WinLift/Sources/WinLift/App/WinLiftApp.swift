#if os(macOS)
import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    // 闭包在主线程的 applicationShouldTerminate 中同步调用，
    // 且需要读取 @MainActor 的运行时状态，因此必须标注 MainActor 隔离。
    var runtimeIsActive: @MainActor () -> Bool = { false }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard runtimeIsActive() else { return .terminateNow }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Windows 仍在运行"
        alert.informativeText = "请先在 WinLift 中正常关闭虚拟机，再退出应用，以免留下失去控制的 QEMU 进程或损坏磁盘。"
        alert.addButton(withTitle: "返回 WinLift")
        alert.runModal()
        return .terminateCancel
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
                    appDelegate.runtimeIsActive = {
                        model.runtime.state.isActive
                    }
                }
        }
        .windowStyle(.automatic)
        .commands {
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

                Button("正常关机") {
                    model.runtime.requestShutdown()
                }
                .disabled(!model.runtime.canRequestShutdown)

                Divider()

                Button("刷新 QEMU 状态") {
                    model.refreshQEMUInstallation()
                }
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
