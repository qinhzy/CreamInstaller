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
    case intelExecutableOnAppleSilicon
    case invalidFirmwareSize(expectedBytes: UInt64, actualBytes: UInt64)

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
        case .intelExecutableOnAppleSilicon:
            return "检测到 Intel 版 QEMU，HVF 不可用，请安装 arm64 版。"
        case let .invalidFirmwareSize(expectedBytes, actualBytes):
            let expectedMiB = expectedBytes / 1_048_576
            let actualMiB = actualBytes / 1_048_576
            return "QEMU 固件尺寸必须为 \(expectedMiB) MiB，当前为 \(actualMiB) MiB。请重新安装 QEMU。"
        }
    }
}

public enum QEMUDiscovery {
    public static let expectedFirmwareSizeBytes = UInt64(64 * 1_024 * 1_024)

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

#if os(macOS) && arch(arm64)
        try validateExecutableArchitecture(at: executableURL, requiresARM64: true)
#endif

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

        let resolvedFirmwareURL = firmwareURL.resolvingSymlinksInPath()
        let attributes = try fileManager.attributesOfItem(atPath: resolvedFirmwareURL.path)
        let firmwareSize = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        guard firmwareSize == expectedFirmwareSizeBytes else {
            throw QEMUDiscoveryError.invalidFirmwareSize(
                expectedBytes: expectedFirmwareSizeBytes,
                actualBytes: firmwareSize
            )
        }

        return QEMUInstallation(
            executableURL: executableURL.resolvingSymlinksInPath(),
            firmwareURL: resolvedFirmwareURL
        )
    }

    /// Unknown wrappers are left to normal process launch diagnostics; a
    /// positively identified x86_64-only Mach-O gets the actionable HVF error.
    public static func validateExecutableArchitecture(
        at executableURL: URL,
        requiresARM64: Bool
    ) throws {
        guard requiresARM64,
              let architectures = try? MachOInspector.architectures(at: executableURL),
              !architectures.contains(.arm64),
              architectures.contains(.x86_64) else {
            return
        }
        throw QEMUDiscoveryError.intelExecutableOnAppleSilicon
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
