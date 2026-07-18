#if os(macOS)
import AppKit
import SwiftUI
import WinLiftCore

struct VMDetailView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var runtime: QEMUProcessController
    let machine: VirtualMachine

    @State private var isConfirmingForceStop = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                if let qemuProblem = model.qemuProblem {
                    QEMURequirementBanner(
                        message: qemuProblem,
                        installAction: model.openQEMUInstallPage
                    )
                }

                if model.isInstallerMissing(for: machine) {
                    MissingISOBanner(
                        path: machine.installerISOPath ?? "",
                        replaceAction: replaceISO,
                        isEnabled: !isThisMachineActive
                    )
                } else if machine.attachInstaller {
                    InstallerBanner()
                }

                hardwareCard
                installerCard

                if machine.attachInstaller {
                    InstallTipsCard()
                }

                if isLogForThisMachine, !runtime.logText.isEmpty {
                    logCard
                }
            }
            .padding(24)
            .frame(maxWidth: 940, alignment: .leading)
        }
        .navigationTitle(machine.name)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                controls
                moreMenu
            }
        }
        .confirmationDialog(
            "强制停止虚拟机？",
            isPresented: $isConfirmingForceStop
        ) {
            Button("强制停止", role: .destructive) {
                runtime.forceStop()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("这相当于直接断电：未写入磁盘的数据会丢失，可能损坏 Windows 文件系统。优先使用“关机”。")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.blue.gradient)
                Image(systemName: "window.ceiling")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(.white)
            }
            .frame(width: 68, height: 68)

            VStack(alignment: .leading, spacing: 6) {
                Text(machine.name)
                    .font(.largeTitle.weight(.semibold))
                StatusBadge(
                    state: displayedState,
                    startedAt: isThisMachineActive ? runtime.startedAt : nil
                )
            }

            Spacer()

            controls
        }
    }

    // MARK: - Controls

    @ViewBuilder
    private var controls: some View {
        if !isThisMachineActive {
            Button {
                model.selectedMachineID = machine.id
                model.start(machine)
            } label: {
                Label("启动", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!runtime.canStart || model.qemuInstallation == nil)
            .help("启动虚拟机 (⌘R)")
        } else {
            if runtime.state == .paused {
                Button {
                    runtime.resume()
                } label: {
                    Label("继续", systemImage: "play.fill")
                }
                .disabled(!runtime.canResume)
                .help("继续运行 (⌘P)")
            } else {
                Button {
                    runtime.pause()
                } label: {
                    Label("暂停", systemImage: "pause.fill")
                }
                .disabled(!runtime.canPause)
                .help("暂停虚拟机 (⌘P)")
            }

            Button {
                runtime.requestShutdown()
            } label: {
                Label("关机", systemImage: "power")
            }
            .disabled(!runtime.canRequestShutdown)
            .help("发送 ACPI 正常关机请求 (⇧⌘R)")
        }
    }

    private var moreMenu: some View {
        Menu {
            Button("编辑配置…") {
                model.beginEditing(machine)
            }
            .disabled(isThisMachineActive)

            Button("在 Finder 中显示虚拟机文件") {
                model.revealBundle(for: machine.id)
            }

            Divider()

            Button("强制停止…", role: .destructive) {
                isConfirmingForceStop = true
            }
            .disabled(!isThisMachineActive)

            Button("删除虚拟机…", role: .destructive) {
                model.requestDelete(machine)
            }
            .disabled(isThisMachineActive)
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .help("更多操作")
    }

    // MARK: - Cards

    private var hardwareCard: some View {
        DetailCard(title: "硬件", systemImage: "cpu") {
            Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 12) {
                GridRow {
                    PropertyLabel(title: "处理器", value: "\(machine.cpuCount) 核")
                    PropertyLabel(title: "内存", value: "\(machine.memorySizeGiB) GiB")
                }
                GridRow {
                    PropertyLabel(title: "虚拟磁盘", value: "\(machine.diskSizeGiB) GiB（稀疏）")
                    PropertyLabel(title: "架构", value: "ARM64 · HVF")
                }
            }

            Divider()

            HStack {
                Button("编辑配置…") {
                    model.beginEditing(machine)
                }
                .disabled(isThisMachineActive)
                .help(isThisMachineActive ? "先关机才能修改配置" : "修改名称、CPU、内存或扩容磁盘 (⌘I)")

                Button("在 Finder 中显示虚拟机文件") {
                    model.revealBundle(for: machine.id)
                }
            }
        }
    }

    private var installerCard: some View {
        DetailCard(title: "安装介质", systemImage: "opticaldisc") {
            Toggle(
                "启动时挂载 Windows ISO",
                isOn: Binding(
                    get: { machine.attachInstaller },
                    set: { model.setInstallerAttached($0, for: machine.id) }
                )
            )
            .disabled(isThisMachineActive)
            .help("Windows 安装完成后关闭此开关，相当于弹出安装光盘")

            if let path = machine.installerISOPath {
                Text(path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .help(path)
            }

            HStack {
                Button("更换 ISO…") {
                    replaceISO()
                }
                .disabled(isThisMachineActive)

                Text("也可以把 .iso 文件直接拖到这里。")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Text("Windows 安装完成并首次进入桌面后，请关闭上面的开关，避免下次重新进入安装器。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard !isThisMachineActive,
                  let url = urls.first,
                  url.pathExtension.lowercased() == "iso" else {
                return false
            }
            model.replaceInstallerISO(with: url, for: machine.id)
            return true
        }
    }

    private var logCard: some View {
        DetailCard(title: "运行日志", systemImage: "terminal") {
            ScrollViewReader { proxy in
                ScrollView([.horizontal, .vertical]) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(runtime.logText)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Color.clear
                            .frame(height: 1)
                            .id("log-bottom")
                    }
                }
                .frame(minHeight: 140, maxHeight: 260)
                .onChange(of: runtime.logText) { _, _ in
                    proxy.scrollTo("log-bottom", anchor: .bottom)
                }
                .onAppear {
                    proxy.scrollTo("log-bottom", anchor: .bottom)
                }
            }

            HStack {
                Spacer()

                Button("复制日志") {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(runtime.logText, forType: .string)
                }
                .disabled(runtime.logText.isEmpty)

                Button("清空显示") {
                    runtime.clearLog()
                }
                .help("只清空界面显示；qemu.log 文件保持完整 (⌘K)")
            }
        }
    }

    // MARK: - Helpers

    private func replaceISO() {
        guard let url = ISOPicker.pick() else { return }
        model.replaceInstallerISO(with: url, for: machine.id)
    }

    private var isThisMachineActive: Bool {
        runtime.activeMachineID == machine.id
    }

    private var displayedState: VMRuntimeState {
        (isThisMachineActive || isLogForThisMachine) ? runtime.state : .stopped
    }

    private var isLogForThisMachine: Bool {
        runtime.lastMachineID == machine.id
    }
}

// MARK: - Components

private struct DetailCard<Content: View>: View {
    let title: String
    let systemImage: String
    let content: Content

    init(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.55), lineWidth: 0.5)
        }
    }
}

private struct PropertyLabel: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct StatusBadge: View {
    let state: VMRuntimeState
    let startedAt: Date?

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(state.title)

            if let startedAt, state == .running || state == .paused {
                Text("·")
                Text(startedAt, style: .timer)
                    .monospacedDigit()
                    .help("自本次启动以来的时间")
            }
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
        .animation(.default, value: state)
    }

    private var color: Color {
        switch state {
        case .stopped:
            return .secondary
        case .starting, .stopping:
            return .orange
        case .running:
            return .green
        case .paused:
            return .yellow
        case .failed:
            return .red
        }
    }
}

private struct QEMURequirementBanner: View {
    let message: String
    let installAction: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "shippingbox")
                .font(.title2)
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 5) {
                Text("需要 QEMU")
                    .font(.headline)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("brew install qemu")
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            }

            Spacer()

            Button("安装说明", action: installAction)
        }
        .padding(16)
        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct MissingISOBanner: View {
    let path: String
    let replaceAction: () -> Void
    let isEnabled: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 5) {
                Text("找不到 Windows 安装 ISO")
                    .font(.headline)
                Text("文件可能被移动或删除：\(path)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }

            Spacer()

            Button("重新选择…", action: replaceAction)
                .disabled(!isEnabled)
        }
        .padding(16)
        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct InstallerBanner: View {
    var body: some View {
        Label(
            "当前会挂载 Windows 安装 ISO。系统安装完成后请将它弹出。",
            systemImage: "info.circle"
        )
        .font(.callout)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.blue.opacity(0.09), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct InstallTipsCard: View {
    @State private var isExpanded = false
    @State private var didCopy = false

    private let bypassCommands = """
    reg add HKLM\\SYSTEM\\Setup\\LabConfig /v BypassTPMCheck /t REG_DWORD /d 1 /f
    reg add HKLM\\SYSTEM\\Setup\\LabConfig /v BypassSecureBootCheck /t REG_DWORD /d 1 /f
    """

    var body: some View {
        DetailCard(title: "安装小贴士", systemImage: "lightbulb") {
            DisclosureGroup(
                "安装器提示“此电脑无法运行 Windows 11”怎么办？",
                isExpanded: $isExpanded
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("当前版本没有虚拟 TPM/Secure Boot。在安装界面按 Shift+F10（部分键盘需加 Fn）打开命令提示符，执行下面两条命令后关闭窗口、重新继续安装：")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    Text(bypassCommands)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))

                    HStack {
                        Button(didCopy ? "已复制" : "复制命令") {
                            let pasteboard = NSPasteboard.general
                            pasteboard.clearContents()
                            pasteboard.setString(bypassCommands, forType: .string)
                            didCopy = true
                            Task { @MainActor in
                                try? await Task.sleep(nanoseconds: 2_000_000_000)
                                didCopy = false
                            }
                        }

                        Text("这个绕过方式只适合开发测试；正式使用请遵循 Microsoft 的授权条款。")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.top, 8)
            }
        }
    }
}
#endif
