import Foundation
import WinLiftCore

struct VMLoadResult {
    var machines: [VirtualMachine]
    var warnings: [String]
}

enum VMStoreError: LocalizedError {
    case unsupportedSchema(Int)
    case bundleIdentifierMismatch

    var errorDescription: String? {
        switch self {
        case let .unsupportedSchema(version):
            return "配置版本 \(version) 高于当前应用支持的版本。"
        case .bundleIdentifierMismatch:
            return "配置中的虚拟机 ID 与 bundle 目录不一致。"
        }
    }
}

public struct VMFileStore {
    let layout: VMStorageLayout
    private let fileManager: FileManager

    init(layout: VMStorageLayout, fileManager: FileManager = .default) {
        self.layout = layout
        self.fileManager = fileManager
    }

    public static func live(fileManager: FileManager = .default) -> VMFileStore {
        let root = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("WinLift", isDirectory: true)
            .appendingPathComponent("Virtual Machines", isDirectory: true)
        return VMFileStore(layout: VMStorageLayout(rootURL: root), fileManager: fileManager)
    }

    func loadAll() throws -> VMLoadResult {
        try fileManager.createDirectory(
            at: layout.rootURL,
            withIntermediateDirectories: true
        )

        let bundleURLs = try fileManager.contentsOfDirectory(
            at: layout.rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        var machines: [VirtualMachine] = []
        var warnings: [String] = []
        let decoder = Self.makeDecoder()

        for bundleURL in bundleURLs where bundleURL.pathExtension == "winliftvm" {
            let configURL = bundleURL.appendingPathComponent("config.json")
            do {
                let data = try Data(contentsOf: configURL)
                let machine = try decoder.decode(VirtualMachine.self, from: data)
                guard machine.schemaVersion <= VirtualMachine.currentSchemaVersion else {
                    throw VMStoreError.unsupportedSchema(machine.schemaVersion)
                }
                // 用 path 比较：URL 相等比较会区分目录 URL 的尾部斜杠。
                guard layout.bundleURL(for: machine.id).standardizedFileURL.path
                    == bundleURL.standardizedFileURL.path else {
                    throw VMStoreError.bundleIdentifierMismatch
                }
                machines.append(machine)
            } catch {
                warnings.append("无法读取 \(bundleURL.lastPathComponent)：\(error.localizedDescription)")
            }
        }

        machines.sort { $0.createdAt > $1.createdAt }
        return VMLoadResult(machines: machines, warnings: warnings)
    }

    func save(_ machine: VirtualMachine) throws {
        let bundleURL = layout.bundleURL(for: machine.id)
        try fileManager.createDirectory(at: bundleURL, withIntermediateDirectories: true)
        let data = try Self.makeEncoder().encode(machine)
        try data.write(to: layout.configurationURL(for: machine.id), options: .atomic)
    }

    func artifactsExist(for machine: VirtualMachine) -> Bool {
        fileManager.fileExists(atPath: layout.diskURL(for: machine.id).path)
            && fileManager.fileExists(atPath: layout.efiVariablesURL(for: machine.id).path)
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
