#if os(macOS)
import SwiftUI

struct EditVMView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: AppModel
    @State private var draft: VMEditDraft

    private let maximumCPUCount = max(
        2,
        min(ProcessInfo.processInfo.activeProcessorCount, 32)
    )
    private let maximumMemoryGiB = max(
        4,
        min(128, Int(ProcessInfo.processInfo.physicalMemory / 1_073_741_824))
    )

    init(model: AppModel, draft: VMEditDraft) {
        self.model = model
        _draft = State(initialValue: draft)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 30))
                    .foregroundStyle(.tint)

                VStack(alignment: .leading, spacing: 3) {
                    Text("编辑虚拟机配置")
                        .font(.title2.weight(.semibold))
                    Text("修改会在下次启动时生效")
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

                    Stepper(
                        value: $draft.diskSizeGiB,
                        in: draft.minimumDiskSizeGiB...2_048,
                        step: 16
                    ) {
                        LabeledContent("磁盘") {
                            Text("\(draft.diskSizeGiB) GiB")
                                .monospacedDigit()
                        }
                    }

                    Text("磁盘只支持扩容。扩容后需要在 Windows 的“磁盘管理”中扩展分区才能使用新空间。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("安装介质") {
                    HStack {
                        Image(systemName: "opticaldisc")
                            .foregroundStyle(.secondary)

                        Text(displayedISOName)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.primary)
                            .help(draft.installerISOURL?.path ?? draft.currentISOPath ?? "")

                        Spacer()

                        Button("更换…") {
                            if let url = ISOPicker.pick() {
                                draft.installerISOURL = url
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button("取消", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("保存") {
                    if model.applyEdit(draft) {
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(20)
        }
        .frame(width: 570, height: 560)
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first, url.pathExtension.lowercased() == "iso" else {
                return false
            }
            draft.installerISOURL = url
            return true
        }
    }

    private var displayedISOName: String {
        if let url = draft.installerISOURL {
            return url.lastPathComponent
        }
        if let path = draft.currentISOPath, !path.isEmpty {
            return URL(fileURLWithPath: path).lastPathComponent
        }
        return "尚未选择 ISO"
    }
}
#endif
