#if os(macOS)
import AppKit
import Combine
import Darwin
import Foundation
import WinLiftCore

enum AppModelError: LocalizedError {
    case installerMissing(String)
    case detachedQEMUStillRunning(Int32)
    case machineIsRunning
    case diskShrinkNotSupported
    case logFileMissing
    case logFileCouldNotOpen

    var errorDescription: String? {
        switch self {
        case let .installerMissing(path):
            return "找不到 Windows 安装镜像：\(path)"
        case let .detachedQEMUStillRunning(pid):
            return "这台虚拟机已有 QEMU 进程在运行（PID \(pid)）。请先在原窗口中正常关闭它。"
        case .machineIsRunning:
            return "虚拟机正在运行。请先正常关机，再执行这个操作。"
        case .diskShrinkNotSupported:
            return "虚拟磁盘只支持扩容，不支持缩小。"
        case .logFileMissing:
            return "这台虚拟机还没有 qemu.log 日志文件。"
        case .logFileCouldNotOpen:
            return "无法使用默认应用打开 qemu.log。"
        }
    }
}

struct HostResources {
    let processorCount: Int
    let memoryGiB: Int

    init(processInfo: ProcessInfo = .processInfo) {
        processorCount = max(1, processInfo.activeProcessorCount)
        memoryGiB = max(1, Int(processInfo.physicalMemory / 1_073_741_824))
    }
}

@MainActor
public final class AppModel: ObservableObject {
    @Published private(set) var machines: [VirtualMachine] = []
    @Published public var selectedMachineID: UUID?
    @Published public var isPresentingCreateVM = false
    @Published var editingDraft: VMEditDraft?
    @Published var machinePendingDeletion: VirtualMachine?
    @Published private(set) var isCreatingVM = false
    @Published private(set) var qemuInstallation: QEMUInstallation?
    @Published private(set) var qemuProblem: String?
    @Published private(set) var qemuVersion: String?
    @Published private(set) var qemuVersionProblem: String?
    @Published private(set) var installerMissingMachineIDs = Set<UUID>()
    @Published var errorMessage: String?
    @Published var noticeMessage: String?

    let hostResources = HostResources()
    public let runtime: QEMUProcessController
    private let store: VMFileStore
    private let provisioner: VMProvisioner
    private let fileManager: FileManager
    private var cancellables = Set<AnyCancellable>()

    public init(
        store: VMFileStore = .live(),
        runtime: QEMUProcessController? = nil,
        fileManager: FileManager = .default
    ) {
        self.store = store
        // 不放进默认参数：@MainActor 隔离的默认参数值需要 Swift 5.10+。
        self.runtime = runtime ?? QEMUProcessController()
        self.fileManager = fileManager
        provisioner = VMProvisioner(store: store, fileManager: fileManager)

        self.runtime.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        reload()
        refreshQEMUInstallation()
    }

    public var selectedMachine: VirtualMachine? {
        guard let selectedMachineID else { return nil }
        return machines.first(where: { $0.id == selectedMachineID })
    }

    public var canStartSelectedMachine: Bool {
        guard selectedMachine != nil else { return false }
        return runtime.canStart && qemuInstallation != nil
    }

    /// 编辑、删除、更换 ISO 等操作只允许在这台机器没有运行时执行。
    public var canModifySelectedMachine: Bool {
        guard let machine = selectedMachine else { return false }
        return runtime.activeMachineID != machine.id
    }

    func reload() {
        do {
            let result = try store.loadAll()
            machines = result.machines
            refreshInstallerMissingCache()
            if selectedMachineID == nil || !machines.contains(where: { $0.id == selectedMachineID }) {
                selectedMachineID = machines.first?.id
            }
            noticeMessage = result.warnings.isEmpty ? nil : result.warnings.joined(separator: "\n")
        } catch {
            errorMessage = "虚拟机列表读取失败：\(error.localizedDescription)"
        }
    }

    public func refreshQEMUInstallation() {
        do {
            let installation = try QEMUDiscovery.discover(fileManager: fileManager)
            qemuInstallation = installation
            qemuProblem = nil
            do {
                qemuVersion = try QEMUVersionProbe.version(at: installation.executableURL)
                qemuVersionProblem = nil
            } catch {
                qemuVersion = nil
                qemuVersionProblem = error.localizedDescription
            }
        } catch {
            qemuInstallation = nil
            qemuProblem = error.localizedDescription
            qemuVersion = nil
            qemuVersionProblem = nil
        }
    }

    func createVM(from draft: VMCreationDraft) async -> Bool {
        guard !isCreatingVM else { return false }
        isCreatingVM = true
        defer { isCreatingVM = false }

        let machine = VirtualMachine(
            name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
            cpuCount: draft.cpuCount,
            memorySizeGiB: draft.memorySizeGiB,
            diskSizeGiB: draft.diskSizeGiB,
            installerISOPath: draft.installerISOURL?.path,
            attachInstaller: true
        )

        do {
            try validate(machine)
            if let isoPath = machine.installerISOPath,
               !fileManager.fileExists(atPath: isoPath) {
                throw AppModelError.installerMissing(isoPath)
            }
            let provisioner = self.provisioner
            try await Task.detached(priority: .userInitiated) { [provisioner, machine] in
                try provisioner.provision(machine)
            }.value
            reload()
            selectedMachineID = machine.id
            return true
        } catch {
            errorMessage = "创建虚拟机失败：\(error.localizedDescription)"
            return false
        }
    }

    public func startSelectedMachine() {
        guard let machine = selectedMachine else { return }
        start(machine)
    }

    func start(_ machine: VirtualMachine) {
        guard let installation = qemuInstallation else {
            errorMessage = qemuProblem ?? "QEMU 尚未安装。"
            return
        }

        do {
            try validate(machine)
            try provisioner.validateArtifacts(for: machine)
            try ensureNoDetachedProcess(for: machine)

            refreshInstallerMissingStatus(for: machine)

            if isInstallerMissing(for: machine), let isoPath = machine.installerISOPath {
                throw AppModelError.installerMissing(isoPath)
            }

            try runtime.start(
                machine: machine,
                layout: store.layout,
                installation: installation
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setInstallerAttached(_ isAttached: Bool, for machineID: UUID) {
        guard runtime.activeMachineID != machineID,
              let index = machines.firstIndex(where: { $0.id == machineID }) else {
            return
        }

        var updated = machines[index]
        updated.attachInstaller = isAttached

        do {
            try validate(updated)
            try store.save(updated)
            machines[index] = updated
            refreshInstallerMissingStatus(for: updated)
        } catch {
            errorMessage = "配置保存失败：\(error.localizedDescription)"
        }
    }

    func isInstallerMissing(for machine: VirtualMachine) -> Bool {
        installerMissingMachineIDs.contains(machine.id)
    }

    func replaceInstallerISO(with url: URL, for machineID: UUID) {
        guard let index = machines.firstIndex(where: { $0.id == machineID }) else { return }
        guard runtime.activeMachineID != machineID else {
            errorMessage = AppModelError.machineIsRunning.localizedDescription
            return
        }
        guard url.pathExtension.lowercased() == "iso" else {
            errorMessage = VMValidationError.invalidInstallerExtension.localizedDescription
            return
        }

        var updated = machines[index]
        updated.installerISOPath = url.path

        do {
            try validate(updated)
            try store.save(updated)
            machines[index] = updated
            refreshInstallerMissingStatus(for: updated)
        } catch {
            errorMessage = "更换 ISO 失败：\(error.localizedDescription)"
        }
    }

    public func beginEditingSelectedMachine() {
        guard let machine = selectedMachine else { return }
        beginEditing(machine)
    }

    func beginEditing(_ machine: VirtualMachine) {
        guard runtime.activeMachineID != machine.id else {
            errorMessage = AppModelError.machineIsRunning.localizedDescription
            return
        }
        editingDraft = VMEditDraft(machine: machine)
    }

    func applyEdit(_ draft: VMEditDraft) -> Bool {
        guard let index = machines.firstIndex(where: { $0.id == draft.machineID }) else {
            return false
        }
        let current = machines[index]
        guard runtime.activeMachineID != current.id else {
            errorMessage = AppModelError.machineIsRunning.localizedDescription
            return false
        }
        guard draft.diskSizeGiB >= current.diskSizeGiB else {
            errorMessage = AppModelError.diskShrinkNotSupported.localizedDescription
            return false
        }
        if let iso = draft.installerISOURL, iso.pathExtension.lowercased() != "iso" {
            errorMessage = VMValidationError.invalidInstallerExtension.localizedDescription
            return false
        }

        var updated = current
        updated.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.cpuCount = draft.cpuCount
        updated.memorySizeGiB = draft.memorySizeGiB
        updated.diskSizeGiB = draft.diskSizeGiB
        if let iso = draft.installerISOURL {
            updated.installerISOPath = iso.path
        }

        do {
            try validate(updated)
            if updated.diskSizeGiB > current.diskSizeGiB {
                try provisioner.growDisk(for: updated)
            }
            try store.save(updated)
            machines[index] = updated
            refreshInstallerMissingStatus(for: updated)
            return true
        } catch {
            errorMessage = "保存配置失败：\(error.localizedDescription)"
            return false
        }
    }

    public func requestDelete(_ machine: VirtualMachine) {
        guard runtime.activeMachineID != machine.id else {
            errorMessage = AppModelError.machineIsRunning.localizedDescription
            return
        }
        machinePendingDeletion = machine
    }

    func confirmDelete() {
        guard let machine = machinePendingDeletion else { return }
        machinePendingDeletion = nil

        do {
            try ensureNoDetachedProcess(for: machine)
            try fileManager.trashItem(
                at: store.layout.bundleURL(for: machine.id),
                resultingItemURL: nil
            )
            runtime.forget(machineID: machine.id)
            reload()
        } catch {
            errorMessage = "删除失败：\(error.localizedDescription)"
        }
    }

    public func revealBundle(for machineID: UUID) {
        NSWorkspace.shared.activateFileViewerSelecting([
            store.layout.bundleURL(for: machineID)
        ])
    }

    func resetEFIVariables(for machine: VirtualMachine) {
        guard runtime.activeMachineID != machine.id else {
            errorMessage = AppModelError.machineIsRunning.localizedDescription
            return
        }

        do {
            try ensureNoDetachedProcess(for: machine)
            try provisioner.resetEFIVariables(for: machine)
            noticeMessage = "已重置“\(machine.name)”的 EFI 变量。"
        } catch {
            errorMessage = "重置 EFI 变量失败：\(error.localizedDescription)"
        }
    }

    func openLogFile(for machine: VirtualMachine) {
        guard runtime.activeMachineID != machine.id else {
            errorMessage = AppModelError.machineIsRunning.localizedDescription
            return
        }

        let url = store.layout.logURL(for: machine.id)
        guard fileManager.fileExists(atPath: url.path) else {
            errorMessage = AppModelError.logFileMissing.localizedDescription
            return
        }
        guard NSWorkspace.shared.open(url) else {
            errorMessage = AppModelError.logFileCouldNotOpen.localizedDescription
            return
        }
    }

    func openQEMUInstallPage() {
        guard let url = URL(string: "https://formulae.brew.sh/formula/qemu") else { return }
        NSWorkspace.shared.open(url)
    }

    func openWindowsDownloadPage() {
        guard let url = URL(string: "https://www.microsoft.com/software-download/windows11arm64") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    func dismissError() {
        errorMessage = nil
    }

    func refreshInstallerMissingStatus(for machine: VirtualMachine) {
        if installerIsMissingOnDisk(for: machine) {
            installerMissingMachineIDs.insert(machine.id)
        } else {
            installerMissingMachineIDs.remove(machine.id)
        }
    }

    private func refreshInstallerMissingCache() {
        installerMissingMachineIDs = Set(
            machines.lazy
                .filter { self.installerIsMissingOnDisk(for: $0) }
                .map(\.id)
        )
    }

    private func installerIsMissingOnDisk(for machine: VirtualMachine) -> Bool {
        guard machine.attachInstaller, let path = machine.installerISOPath, !path.isEmpty else {
            return false
        }
        return !fileManager.fileExists(atPath: path)
    }

    private func validate(_ machine: VirtualMachine) throws {
        try VMValidator.validate(
            machine,
            hostProcessorCount: hostResources.processorCount,
            hostMemoryGiB: hostResources.memoryGiB
        )
    }

    private func ensureNoDetachedProcess(for machine: VirtualMachine) throws {
        let pidURL = store.layout.runtimePIDURL(for: machine.id)
        guard let text = try? String(contentsOf: pidURL, encoding: .utf8),
              let pid = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)),
              pid > 1 else {
            return
        }

        if Darwin.kill(pid, 0) == 0 || errno == EPERM {
            throw AppModelError.detachedQEMUStillRunning(pid)
        }

        // QEMU did not get a chance to remove an old pidfile. It is safe to
        // remove only after kill(pid, 0) proves the process no longer exists.
        try? fileManager.removeItem(at: pidURL)
    }
}
#endif
