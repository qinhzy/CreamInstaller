import Foundation

public struct QEMUInstallation: Hashable, Sendable {
    public let executableURL: URL
    public let firmwareURL: URL

    public init(executableURL: URL, firmwareURL: URL) {
        self.executableURL = executableURL
        self.firmwareURL = firmwareURL
    }
}

public enum QEMUDiscoveryError: LocalizedError, Equatable, Sendable {
    case executableNotFound
    case firmwareNotFound
    case invalidExecutableOverride(String)
    case invalidFirmwareOverride(String)

    public var errorDescription: String? {
        switch self {
        case .executableNotFound:
            return "没有找到 qemu-system-aarch64。请先运行：brew install qemu"
        case .firmwareNotFound:
            return "找到了 QEMU，但没有找到 edk2-aarch64-code.fd 固件。请重新安装 QEMU。"
        case let .invalidExecutableOverride(path):
            return "WINLIFT_QEMU_SYSTEM 指向的文件不可执行：\(path)"
        case let .invalidFirmwareOverride(path):
            return "WINLIFT_QEMU_FIRMWARE 指向的固件不可读取：\(path)"
        }
    }
}

public enum QEMUDiscovery {
    public static func discover(
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> QEMUInstallation {
        let executableURL: URL

        if let override = environment["WINLIFT_QEMU_SYSTEM"], !override.isEmpty {
            guard fileManager.isExecutableFile(atPath: override) else {
                throw QEMUDiscoveryError.invalidExecutableOverride(override)
            }
            executableURL = URL(fileURLWithPath: override)
        } else {
            guard let discovered = executableCandidates(environment: environment)
                .first(where: { fileManager.isExecutableFile(atPath: $0.path) }) else {
                throw QEMUDiscoveryError.executableNotFound
            }
            executableURL = discovered
        }

        let firmwareURL: URL
        if let override = environment["WINLIFT_QEMU_FIRMWARE"], !override.isEmpty {
            guard fileManager.isReadableFile(atPath: override) else {
                throw QEMUDiscoveryError.invalidFirmwareOverride(override)
            }
            firmwareURL = URL(fileURLWithPath: override)
        } else {
            guard let discovered = firmwareCandidates(for: executableURL)
                .first(where: { fileManager.isReadableFile(atPath: $0.path) }) else {
                throw QEMUDiscoveryError.firmwareNotFound
            }
            firmwareURL = discovered
        }

        return QEMUInstallation(
            executableURL: executableURL.resolvingSymlinksInPath(),
            firmwareURL: firmwareURL.resolvingSymlinksInPath()
        )
    }

    public static func executableCandidates(environment: [String: String]) -> [URL] {
        var paths: [String] = [
            "/opt/homebrew/bin/qemu-system-aarch64",
            "/usr/local/bin/qemu-system-aarch64",
            "/opt/local/bin/qemu-system-aarch64"
        ]

        if let path = environment["PATH"] {
            paths.append(contentsOf: path.split(separator: ":").map {
                String($0) + "/qemu-system-aarch64"
            })
        }

        var seen = Set<String>()
        return paths.compactMap { path in
            guard seen.insert(path).inserted else { return nil }
            return URL(fileURLWithPath: path)
        }
    }

    public static func firmwareCandidates(for executableURL: URL) -> [URL] {
        let resolvedExecutable = executableURL.resolvingSymlinksInPath()
        let resolvedPrefix = resolvedExecutable
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let fixedPaths = [
            "/opt/homebrew/share/qemu/edk2-aarch64-code.fd",
            "/usr/local/share/qemu/edk2-aarch64-code.fd",
            "/opt/local/share/qemu/edk2-aarch64-code.fd"
        ].map { URL(fileURLWithPath: $0) }

        let derived = resolvedPrefix
            .appendingPathComponent("share/qemu", isDirectory: true)
            .appendingPathComponent("edk2-aarch64-code.fd")

        var candidates = [derived] + fixedPaths
        var seen = Set<String>()
        candidates = candidates.filter { seen.insert($0.path).inserted }
        return candidates
    }
}
