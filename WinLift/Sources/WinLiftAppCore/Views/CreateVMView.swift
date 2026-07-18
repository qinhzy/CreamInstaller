#if os(macOS)
import Foundation
import SwiftUI

struct CreateVMView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: AppModel
    @State private var draft = VMCreationDraft()
    @FocusState private var isNameFieldFocused: Bool

    private let maximumCPUCount = max(
        2,
        min(ProcessInfo.processInfo.activeProcessorCount, 32)
    )
    private let maximumMemoryGiB = max(
        4,
        min(128, Int(ProcessInfo.processInfo.physicalMemory / 1_073_741_824))
    )

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                AppMarkChip(systemImage: "plus", size: 46)

                VStack(alignment: .leading, spacing: 3) {
                    Text("新建 Windows 虚拟机")
                        .font(.title2.weight(.semibold))
                    Text("为 Apple Silicon 配置 Windows 11 ARM64")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(24)

            Divider()

            Form {
                Section("名称") {
                    TextField("虚拟机名称", text: $draft.name)
                        .focused($isNameFieldFocused)
                }

                Section("硬件") {
                    Stepper(value: $draft.cpuCount, in: 2...maximumCPUCount) {
                        LabeledContent("CPU") {
                            Text("\(draft.cpuCount) 核")
                                .monospacedDigit()
                        }
                    }

                    Stepper(value: $draft.memorySizeGiB, in: 4...maximumMemoryGiB) {
                        LabeledContent("内存") {
                            Text("\(draft.memorySizeGiB) GiB")
                                .monospacedDigit()
                        }
                    }

                    Stepper(value: $draft.diskSizeGiB, in: 32...2_048, step: 16) {
                        LabeledContent("磁盘") {
                            Text("\(draft.diskSizeGiB) GiB")
                                .monospacedDigit()
                        }
                    }

                    Text("主机共 \(model.hostResources.processorCount) 核 · \(model.hostResources.memoryGiB) GiB 内存；建议分配不超过一半，磁盘使用稀疏文件、按需占用空间。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("安装介质") {
                    HStack {
                        Image(systemName: "opticaldisc")
                            .foregroundStyle(.secondary)

                        Text(draft.installerISOURL?.lastPathComponent ?? "尚未选择 ARM64 ISO")
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(draft.installerISOURL == nil ? .secondary : .primary)
                            .help(draft.installerISOURL?.path ?? "")

                        Spacer()

                        Button("选择…") {
                            if let url = ISOPicker.pick() {
                                draft.installerISOURL = url
                            }
                        }
                    }

                    Text("也可以把 .iso 文件直接拖到这个窗口。")
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    Button("从 Microsoft 下载 Windows 11 ARM64 ISO") {
                        model.openWindowsDownloadPage()
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
            }
            .formStyle(.grouped)
            .disabled(model.isCreatingVM)

            Divider()

            HStack {
                Button("取消", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                if let hint = missingRequirementHint {
                    Text(hint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 8)
                }

                Spacer()

                if model.isCreatingVM {
                    ProgressView()
                        .controlSize(.small)
                }

                Button("创建") {
                    Task { @MainActor in
                        if await model.createVM(from: draft) {
                            dismiss()
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canCreate || model.isCreatingVM)
            }
            .padding(20)
        }
        .frame(width: 570, height: 620)
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first, url.pathExtension.lowercased() == "iso" else {
                return false
            }
            draft.installerISOURL = url
            return true
        }
        .onAppear {
            isNameFieldFocused = true
        }
    }

    private var canCreate: Bool {
        !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && draft.installerISOURL != nil
    }

    private var missingRequirementHint: String? {
        let nameMissing = draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let isoMissing = draft.installerISOURL == nil

        switch (nameMissing, isoMissing) {
        case (true, true):
            return "还需要：名称和 Windows ISO"
        case (true, false):
            return "还需要：虚拟机名称"
        case (false, true):
            return "还需要：Windows 11 ARM64 ISO"
        case (false, false):
            return nil
        }
    }
}
#endif
