#if os(macOS)
import AppKit
import UniformTypeIdentifiers

enum ISOPicker {
    /// 弹出系统面板选择 Windows 11 ARM64 ISO；用户取消时返回 nil。
    @MainActor
    static func pick() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "选择 Windows 11 ARM64 ISO"
        panel.prompt = "选择"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if let isoType = UTType(filenameExtension: "iso") {
            panel.allowedContentTypes = [isoType]
        }

        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }
}
#endif
