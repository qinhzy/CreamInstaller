import AppKit
import SwiftUI
import WinLiftCore

struct VMDetailView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var runtime: QEMUProcessController
    let machine: VirtualMachine

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

                if machine.attachInstaller {
                    InstallerBanner()
                }

                hardwareCard
                installerCard

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
            }
        }
    }

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
                StatusBadge(state: displayedState)
            }

            Spacer()

            controls
        }
    }

    @ViewBuilder
    private var controls: some View {
        if !isThisMachineActive {
            Button {
                model.startSelectedMachine()
            } label: {
                Label("启动", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!model.canStartSelectedMachine)
        } else {
            if runtime.state == .paused {
                Button {
                    runtime.resume()
                } label: {
                    Label("继续", systemImage: "play.fill")
                }
                .disabled(!runtime.canResume)
            } else if runtime.state == .running {
                Button {
                    runtime.pause()
                } label: {
                    Label("暂停", systemImage: "pause.fill")
                }
                .disabled(!runtime.canPause)
            }

            Button {
                runtime.requestShutdown()
            } label: {
                Label("关机", systemImage: "power")
            }
            .disabled(!runtime.canRequestShutdown)

            Menu {
                Button("强制停止", role: .destructive) {
                    runtime.forceStop()
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .help("更多控制")
        }
    }

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

            Button("在 Finder 中显示虚拟机文件") {
                model.revealBundle(for: machine.id)
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

            if let path = machine.installerISOPath {
                Text(path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(2)
            }

            Text("Windows 安装完成并首次进入桌面后，请关闭上面的开关，避免下次重新进入安装器。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var logCard: some View {
        DetailCard(title: "运行日志", systemImage: "terminal") {
            ScrollView([.horizontal, .vertical]) {
                Text(runtime.logText.isEmpty ? "等待 QEMU 输出…" : runtime.logText)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 140, maxHeight: 260)

            HStack {
                Spacer()
                Button("清空显示") {
                    runtime.clearLog()
                }
            }
        }
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

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(state.title)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
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
