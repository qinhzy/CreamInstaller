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
        Form {
            heroSection

            if let qemuProblem = model.qemuProblem {
                bannerSection {
                    QEMURequirementBanner(
                        message: qemuProblem,
                        installAction: model.openQEMUInstallPage
                    )
                }
            }

            if model.isInstallerMissing(for: machine) {
                bannerSection {
                    MissingISOBanner(
                        path: machine.installerISOPath ?? "",
                        replaceAction: replaceISO,
                        isEnabled: !isThisMachineActive
                    )
                }
            }

            hardwareSection
            installerSection

            if machine.attachInstaller {
                tipsSection
            }

            if isLogForThisMachine, !runtime.logText.isEmpty {
                logSection
            }
        }
        .formStyle(.grouped)
        .navigationTitle(machine.name)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                controls
                moreMenu
            }
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

    // MARK: - Hero

    private var heroSection: some View {
        Section {
            VStack(spacing: 16) {
                virtualScreen
                controlStrip
            }
            .padding(.top, 4)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }
    }

    /// 「虚拟显示器」：深色屏幕承载启动按钮与状态；实际画面在 QEMU 窗口中。
    private var virtualScreen: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.13, green: 0.15, blue: 0.22),
                            Color(red: 0.05, green: 0.06, blue: 0.10)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            // 屏幕顶部的柔和反光
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0.09), .clear],
                        startPoint: .top,
                        endPoint: .center
                    )
                )

            screenContent

            VStack {
                Spacer()
                HStack(alignment: .bottom) {
                    StatusCapsule(
                        state: displayedState,
                        startedAt: isThisMachineActive ? runtime.startedAt : nil
                    )

                    Spacer()

                    if displayedState == .running {
                        Text("Windows 画面显示在独立的 QEMU 窗口中")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.45))
                    }
                }
                .padding(14)
            }
        }
        .frame(height: 280)
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.22), radius: 16, y: 6)
        .animation(.snappy, value: displayedState)
    }

    @ViewBuilder
    private var screenContent: some View {
        switch displayedState {
        case .stopped:
            VStack(spacing: 10) {
                Button {
                    model.selectedMachineID = machine.id
                    model.start(machine)
                } label: {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 58, weight: .regular))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .disabled(!runtime.canStart || model.qemuInstallation == nil)
                .help("启动虚拟机 (⌘R)")

                Text("启动 Windows")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.white.opacity(0.65))
            }

        case .starting:
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
                Text("正在启动…")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.65))
            }

        case .running:
            Image(systemName: "macwindow.on.rectangle")
                .font(.system(size: 46, weight: .light))
                .foregroundStyle(.white.opacity(0.22))
                .symbolEffect(.pulse, options: .repeating, isActive: true)

        case .paused:
            VStack(spacing: 10) {
                Button {
                    runtime.resume()
                } label: {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 58))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .disabled(!runtime.canResume)
                .help("继续运行 (⌘P)")

                Text("已暂停")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.white.opacity(0.65))
            }

        case .stopping:
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
                Text("正在关机，请等待 Windows 退出…")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.65))
            }

        case let .failed(message):
            VStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 34))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .padding(.horizontal, 40)
            }
        }
    }

    private var controlStrip: some View {
        HStack(spacing: 10) {
            Spacer()
            controls
            moreMenu
            Spacer()
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

    // MARK: - Sections

    private func bannerSection<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        Section {
            content()
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
        }
    }

    private var hardwareSection: some View {
        Section {
            LabeledContent {
                Text("\(machine.cpuCount) 核")
                    .monospacedDigit()
            } label: {
                Label {
                    Text("处理器")
                } icon: {
                    SettingsIconChip(systemImage: "cpu", tint: .blue)
                }
            }

            LabeledContent {
                Text("\(machine.memorySizeGiB) GiB")
                    .monospacedDigit()
            } label: {
                Label {
                    Text("内存")
                } icon: {
                    SettingsIconChip(systemImage: "memorychip", tint: .green)
                }
            }

            LabeledContent {
                Text("\(machine.diskSizeGiB) GiB · 稀疏")
                    .monospacedDigit()
            } label: {
                Label {
                    Text("虚拟磁盘")
                } icon: {
                    SettingsIconChip(systemImage: "internaldrive", tint: .purple)
                }
            }

            LabeledContent {
                Text("ARM64 · Apple HVF")
            } label: {
                Label {
                    Text("虚拟化")
                } icon: {
                    SettingsIconChip(systemImage: "bolt.fill", tint: .orange)
                }
            }

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
        } header: {
            Text("硬件")
        }
    }

    private var installerSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { machine.attachInstaller },
                set: { model.setInstallerAttached($0, for: machine.id) }
            )) {
                Label {
                    Text("启动时挂载 Windows ISO")
                } icon: {
                    SettingsIconChip(systemImage: "opticaldisc", tint: .cyan)
                }
            }
            .disabled(isThisMachineActive)
            .help("Windows 安装完成后关闭此开关，相当于弹出安装光盘")

            if let path = machine.installerISOPath {
                LabeledContent {
                    Text(URL(fileURLWithPath: path).lastPathComponent)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(path)
                        .textSelection(.enabled)
                } label: {
                    Text("镜像文件")
                }
            }

            HStack {
                Button("更换 ISO…") {
                    replaceISO()
                }
                .disabled(isThisMachineActive)

                Text("也可以把 .iso 文件直接拖到本页任意位置。")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        } header: {
            Text("安装介质")
        } footer: {
            Text("Windows 安装完成并首次进入桌面后，请关闭上面的开关，避免下次重新进入安装器。")
        }
    }

    private var tipsSection: some View {
        Section("安装小贴士") {
            InstallTips()
        }
    }

    private var logSection: some View {
        Section {
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
                .help("只清空界面显示；qemu.log 文件保持完整")
            }
        } header: {
            Text("运行日志")
        } footer: {
            Text("完整日志保存在虚拟机目录的 qemu.log 中。")
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

// MARK: - Banners

private struct QEMURequirementBanner: View {
    let message: String
    let installAction: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "shippingbox.fill")
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
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
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                .symbolRenderingMode(.hierarchical)
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
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Install tips

private struct InstallTips: View {
    @State private var isExpanded = false
    @State private var didCopy = false

    private let bypassCommands = """
    reg add HKLM\\SYSTEM\\Setup\\LabConfig /v BypassTPMCheck /t REG_DWORD /d 1 /f
    reg add HKLM\\SYSTEM\\Setup\\LabConfig /v BypassSecureBootCheck /t REG_DWORD /d 1 /f
    """

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
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
        } label: {
            Label {
                Text("安装器提示“此电脑无法运行 Windows 11”怎么办？")
            } icon: {
                SettingsIconChip(systemImage: "lightbulb.fill", tint: .yellow)
            }
        }
    }
}
#endif
