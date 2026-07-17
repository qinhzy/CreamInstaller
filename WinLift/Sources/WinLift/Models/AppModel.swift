import AppKit
import Combine
import Darwin
import Foundation
import WinLiftCore

enum AppModelError: LocalizedError {
    case installerMissing(String)
    case detachedQEMUStillRunning(Int32)

    var errorDescription: String? {
        switch self {
        case let .installerMissing(path):
            return "找不到 Windows 安装镜像：\(path)"
        case let .detachedQEMUStillRunning(pid):
            return "这台虚拟机已有 QEMU 进程在运行（PID \(pid)）。请先在原窗口中正常关闭它。"
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var machines: [VirtualMachine] = []
    @Published var selectedMachineID: UUID?
    @Published var isPresentingCreateVM = false
    @Published private(set) var isCreatingVM = false
    @Published private(set) var qemuInstallation: QEMUInstallation?
    @Published private(set) var qemuProblem: String?
    @Published var errorMessage: String?
    @Published var noticeMessage: String?

    let runtime: QEMUProcessController
    private let store: VMFileStore
    private let provisioner: VMProvisioner
    private let fileManager: FileManager
    private var cancellables = Set<AnyCancellable>()

    init(
        store: VMFileStore = .live(),
        runtime: QEMUProcessController = QEMUProcessController(),
        fileManager: FileManager = .default
    ) {
        self.store = store
        self.runtime = runtime
        self.fileManager = fileManager
        provisioner = VMProvisioner(store: store, fileManager: fileManager)

        runtime.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        reload()
        refreshQEMUInstallation()
    }

    var selectedMachine: VirtualMachine? {
        guard let selectedMachineID else { return nil }
        return machines.first(where: { $0.id == selectedMachineID })
    }

    var canStartSelectedMachine: Bool {
        guard selectedMachine != nil else { return false }
        return runtime.canStart && qemuInstallation != nil
    }

    func reload() {
        do {
            let result = try store.loadAll()
            machines = result.machines
            if selectedMachineID == nil || !machines.contains(where: { $0.id == selectedMachineID }) {
                selectedMachineID = machines.first?.id
            }
            noticeMessage = result.warnings.isEmpty ? nil : result.warnings.joined(separator: "\n")
        } catch {
            errorMessage = "虚拟机列表读取失败：\(error.localizedDescription)"
        }
    }

    func refreshQEMUInstallation() {
        do {
            qemuInstallation = try QEMUDiscovery.discover(fileManager: fileManager)
            qemuProblem = nil
        } catch {
            qemuInstallation = nil
            qemuProblem = error.localizedDescription
        }
    }

    func createVM(from draft: VMCreationDraft) -> Bool {
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
            try VMValidator.validate(machine)
            if let isoPath = machine.installerISOPath,
               !fileManager.fileExists(atPath: isoPath) {
                throw AppModelError.installerMissing(isoPath)
            }
            try provisioner.provision(machine)
            reload()
            selectedMachineID = machine.id
            return true
        } catch {
            errorMessage = "创建虚拟机失败：\(error.localizedDescription)"
            return false
        }
    }

    func startSelectedMachine() {
        guard let machine = selectedMachine else { return }
        guard let installation = qemuInstallation else {
            errorMessage = qemuProblem ?? "QEMU 尚未安装。"
            return
        }

        do {
            try VMValidator.validate(machine)
            try provisioner.validateArtifacts(for: machine)
            try ensureNoDetachedProcess(for: machine)

            if machine.attachInstaller,
               let isoPath = machine.installerISOPath,
               !fileManager.fileExists(atPath: isoPath) {
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
            try VMValidator.validate(updated)
            try store.save(updated)
            machines[index] = updated
        } catch {
            errorMessage = "配置保存失败：\(error.localizedDescription)"
        }
    }

    func revealBundle(for machineID: UUID) {
        NSWorkspace.shared.activateFileViewerSelecting([
            store.layout.bundleURL(for: machineID)
        ])
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
