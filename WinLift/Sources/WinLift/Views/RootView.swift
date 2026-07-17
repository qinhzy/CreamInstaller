#if os(macOS)
import SwiftUI
import WinLiftCore

struct RootView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var runtime: QEMUProcessController

    init(model: AppModel) {
        self.model = model
        runtime = model.runtime
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $model.selectedMachineID) {
                Section("虚拟机") {
                    ForEach(model.machines) { machine in
                        SidebarMachineRow(
                            machine: machine,
                            state: state(for: machine)
                        )
                        .tag(machine.id)
                    }
                }

                if let notice = model.noticeMessage {
                    Section("读取警告") {
                        Label(notice, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("WinLift")
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 340)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        model.isPresentingCreateVM = true
                    } label: {
                        Label("新建虚拟机", systemImage: "plus")
                    }
                    .help("新建 Windows 虚拟机 (⌘N)")
                }
            }
        } detail: {
            if let machine = model.selectedMachine {
                VMDetailView(model: model, runtime: runtime, machine: machine)
            } else {
                ContentUnavailableView {
                    Label("还没有虚拟机", systemImage: "macwindow")
                } description: {
                    Text("创建一台 Windows 11 ARM64 虚拟机，然后从官方 ISO 安装系统。")
                } actions: {
                    Button("新建虚拟机") {
                        model.isPresentingCreateVM = true
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .sheet(isPresented: $model.isPresentingCreateVM) {
            CreateVMView(model: model)
        }
        .alert(
            "操作失败",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { isPresented in
                    if !isPresented { model.dismissError() }
                }
            )
        ) {
            Button("好", role: .cancel) {
                model.dismissError()
            }
        } message: {
            Text(model.errorMessage ?? "未知错误")
        }
    }

    private func state(for machine: VirtualMachine) -> VMRuntimeState {
        if runtime.activeMachineID == machine.id {
            return runtime.state
        }
        if runtime.activeMachineID == nil, runtime.lastMachineID == machine.id {
            return runtime.state
        }
        return .stopped
    }
}

private struct SidebarMachineRow: View {
    let machine: VirtualMachine
    let state: VMRuntimeState

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "desktopcomputer")
                .foregroundStyle(.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(machine.name)
                    .lineLimit(1)

                Text("\(machine.cpuCount) 核 · \(machine.memorySizeGiB) GiB")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
                .help(state.title)
        }
        .padding(.vertical, 2)
    }

    private var statusColor: Color {
        switch state {
        case .stopped:
            return .secondary.opacity(0.5)
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
#endif
