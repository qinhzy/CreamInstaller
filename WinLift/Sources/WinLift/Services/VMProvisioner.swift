import Foundation
import WinLiftCore

enum VMProvisioningError: LocalizedError {
    case bundleAlreadyExists
    case couldNotCreateFile(String)
    case missingArtifacts

    var errorDescription: String? {
        switch self {
        case .bundleAlreadyExists:
            return "同一 ID 的虚拟机目录已经存在。"
        case let .couldNotCreateFile(path):
            return "无法创建虚拟磁盘文件：\(path)"
        case .missingArtifacts:
            return "虚拟磁盘或 EFI 状态文件缺失，无法启动。"
        }
    }
}

struct VMProvisioner {
    private static let gibibyte = UInt64(1_073_741_824)
    private static let defaultEFIVariablesSize = UInt64(64 * 1_024 * 1_024)

    let store: VMFileStore
    private let fileManager: FileManager

    init(store: VMFileStore, fileManager: FileManager = .default) {
        self.store = store
        self.fileManager = fileManager
    }

    func provision(_ machine: VirtualMachine) throws {
        try VMValidator.validate(machine)

        let bundleURL = store.layout.bundleURL(for: machine.id)
        guard !fileManager.fileExists(atPath: bundleURL.path) else {
            throw VMProvisioningError.bundleAlreadyExists
        }

        try fileManager.createDirectory(at: bundleURL, withIntermediateDirectories: true)

        do {
            try createSparseFile(
                at: store.layout.diskURL(for: machine.id),
                size: UInt64(machine.diskSizeGiB) * Self.gibibyte
            )
            try createEFIVariablesFile(at: store.layout.efiVariablesURL(for: machine.id))
            try store.save(machine)
        } catch {
            try? fileManager.removeItem(at: bundleURL)
            throw error
        }
    }

    func validateArtifacts(for machine: VirtualMachine) throws {
        guard store.artifactsExist(for: machine) else {
            throw VMProvisioningError.missingArtifacts
        }
    }

    private func createSparseFile(at url: URL, size: UInt64) throws {
        guard fileManager.createFile(atPath: url.path, contents: nil) else {
            throw VMProvisioningError.couldNotCreateFile(url.path)
        }

        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.truncate(atOffset: size)
    }

    private func createEFIVariablesFile(at url: URL) throws {
        guard fileManager.createFile(atPath: url.path, contents: nil) else {
            throw VMProvisioningError.couldNotCreateFile(url.path)
        }

        // A newly erased pflash contains 0xFF rather than zero bytes. EDK2 can
        // initialize its variable store from this erased-flash state.
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }

        let chunk = Data(repeating: 0xFF, count: 1_024 * 1_024)
        let chunkCount = Int(Self.defaultEFIVariablesSize / UInt64(chunk.count))
        for _ in 0..<chunkCount {
            try handle.write(contentsOf: chunk)
        }
    }
}
