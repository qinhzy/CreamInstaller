import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct CreateVMView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: AppModel
    @State private var draft = VMCreationDraft()

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
                Image(systemName: "plus.rectangle.on.rectangle")
                    .font(.system(size: 30))
                    .foregroundStyle(.tint)

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

                    Text("磁盘使用稀疏文件，只会随着 Windows 写入数据逐渐占用空间。")
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

                        Spacer()

                        Button("选择…") {
                            chooseISO()
                        }
                    }

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

                Spacer()

                if model.isCreatingVM {
                    ProgressView()
                        .controlSize(.small)
                }

                Button("创建") {
                    if model.createVM(from: draft) {
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canCreate || model.isCreatingVM)
            }
            .padding(20)
        }
        .frame(width: 570, height: 590)
    }

    private var canCreate: Bool {
        !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && draft.installerISOURL != nil
    }

    private func chooseISO() {
        let panel = NSOpenPanel()
        panel.title = "选择 Windows 11 ARM64 ISO"
        panel.prompt = "选择"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if let isoType = UTType(filenameExtension: "iso") {
            panel.allowedContentTypes = [isoType]
        }

        if panel.runModal() == .OK {
            draft.installerISOURL = panel.url
        }
    }
}
