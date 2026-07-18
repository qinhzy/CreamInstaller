import Foundation
import Dispatch

#if os(Linux)
import Glibc
#elseif os(macOS)
import Darwin
#endif

public enum MachOArchitecture: Hashable, Sendable {
    case arm64
    case x86_64
    case other(UInt32)
}

public enum MachOInspectionError: Error, Equatable, Sendable {
    case truncatedHeader
    case invalidMagic
    case unreasonableArchitectureCount(UInt32)
}

/// Reads only the Mach-O header (including all fat-architecture records).
public enum MachOInspector {
    private static let cpuTypeARM64: UInt32 = 0x0100_000C
    private static let cpuTypeX86_64: UInt32 = 0x0100_0007
    private static let maximumArchitectureCount: UInt32 = 128

    public static func architectures(at url: URL) throws -> Set<MachOArchitecture> {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var header = try handle.read(upToCount: 8) ?? Data()
        guard header.count >= 8 else {
            throw MachOInspectionError.truncatedHeader
        }

        let descriptor = try descriptor(for: header)
        switch descriptor.kind {
        case .thin:
            guard let cpuType = uint32(in: header, at: 4, order: descriptor.byteOrder) else {
                throw MachOInspectionError.truncatedHeader
            }
            return [architecture(for: cpuType)]

        case let .fat(recordSize):
            guard let count = uint32(in: header, at: 4, order: descriptor.byteOrder) else {
                throw MachOInspectionError.truncatedHeader
            }
            guard count <= maximumArchitectureCount else {
                throw MachOInspectionError.unreasonableArchitectureCount(count)
            }

            let requiredByteCount = 8 + Int(count) * recordSize
            while header.count < requiredByteCount {
                let remaining = requiredByteCount - header.count
                guard let chunk = try handle.read(upToCount: remaining), !chunk.isEmpty else {
                    break
                }
                header.append(chunk)
            }
            guard header.count >= requiredByteCount else {
                throw MachOInspectionError.truncatedHeader
            }

            var architectures = Set<MachOArchitecture>()
            for index in 0..<Int(count) {
                let offset = 8 + index * recordSize
                guard let cpuType = uint32(
                    in: header,
                    at: offset,
                    order: descriptor.byteOrder
                ) else {
                    throw MachOInspectionError.truncatedHeader
                }
                architectures.insert(architecture(for: cpuType))
            }
            return architectures
        }
    }

    private enum ByteOrder {
        case bigEndian
        case littleEndian
    }

    private enum HeaderKind {
        case thin
        case fat(recordSize: Int)
    }

    private struct HeaderDescriptor {
        let byteOrder: ByteOrder
        let kind: HeaderKind
    }

    private static func descriptor(for data: Data) throws -> HeaderDescriptor {
        let magic = Array(data.prefix(4))
        switch magic {
        case [0xFE, 0xED, 0xFA, 0xCE], [0xFE, 0xED, 0xFA, 0xCF]:
            return HeaderDescriptor(byteOrder: .bigEndian, kind: .thin)
        case [0xCE, 0xFA, 0xED, 0xFE], [0xCF, 0xFA, 0xED, 0xFE]:
            return HeaderDescriptor(byteOrder: .littleEndian, kind: .thin)
        case [0xCA, 0xFE, 0xBA, 0xBE]:
            return HeaderDescriptor(byteOrder: .bigEndian, kind: .fat(recordSize: 20))
        case [0xBE, 0xBA, 0xFE, 0xCA]:
            return HeaderDescriptor(byteOrder: .littleEndian, kind: .fat(recordSize: 20))
        case [0xCA, 0xFE, 0xBA, 0xBF]:
            return HeaderDescriptor(byteOrder: .bigEndian, kind: .fat(recordSize: 32))
        case [0xBF, 0xBA, 0xFE, 0xCA]:
            return HeaderDescriptor(byteOrder: .littleEndian, kind: .fat(recordSize: 32))
        default:
            throw MachOInspectionError.invalidMagic
        }
    }

    private static func uint32(in data: Data, at offset: Int, order: ByteOrder) -> UInt32? {
        guard offset >= 0, offset + 4 <= data.count else { return nil }
        let bytes = Array(data[offset..<(offset + 4)])
        switch order {
        case .bigEndian:
            return UInt32(bytes[0]) << 24
                | UInt32(bytes[1]) << 16
                | UInt32(bytes[2]) << 8
                | UInt32(bytes[3])
        case .littleEndian:
            return UInt32(bytes[3]) << 24
                | UInt32(bytes[2]) << 16
                | UInt32(bytes[1]) << 8
                | UInt32(bytes[0])
        }
    }

    private static func architecture(for cpuType: UInt32) -> MachOArchitecture {
        switch cpuType {
        case cpuTypeARM64:
            return .arm64
        case cpuTypeX86_64:
            return .x86_64
        default:
            return .other(cpuType)
        }
    }
}

public enum QEMUVersionError: LocalizedError, Equatable, Sendable {
    case couldNotLaunch(String)
    case nonzeroExit(Int32)
    case unrecognizedOutput
    case timedOut

    public var errorDescription: String? {
        switch self {
        case let .couldNotLaunch(message):
            return "无法运行 qemu-system-aarch64 --version：\(message)"
        case let .nonzeroExit(status):
            return "qemu-system-aarch64 --version 退出状态码为 \(status)。"
        case .unrecognizedOutput:
            return "无法解析 QEMU 版本输出。"
        case .timedOut:
            return "等待 QEMU 版本信息超时。请检查安装是否完整。"
        }
    }
}

public enum QEMUVersionParser {
    public static func parse(_ output: String) -> String? {
        let marker = "QEMU emulator version"
        guard let markerRange = output.range(of: marker, options: .caseInsensitive) else {
            return nil
        }

        let suffix = output[markerRange.upperBound...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard var token = suffix.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) else {
            return nil
        }
        if token.first == "v" || token.first == "V" {
            token.removeFirst()
        }

        let version = token.prefix { character in
            character.isNumber || character == "." || character == "-"
        }
        guard version.contains(where: { $0.isNumber }) else { return nil }
        return String(version)
    }
}

public enum QEMUVersionProbe {
    public static func version(
        at executableURL: URL,
        timeout: TimeInterval = 5
    ) throws -> String {
        let process = Process()
        let standardOutput = Pipe()
        let standardError = Pipe()
        let termination = DispatchSemaphore(value: 0)
        process.executableURL = executableURL
        process.arguments = ["--version"]
        process.standardOutput = standardOutput
        process.standardError = standardError
        process.terminationHandler = { _ in
            termination.signal()
        }

        do {
            try process.run()
        } catch {
            throw QEMUVersionError.couldNotLaunch(error.localizedDescription)
        }
        guard termination.wait(timeout: .now() + max(0, timeout)) == .success else {
            stop(process, waitingOn: termination)
            throw QEMUVersionError.timedOut
        }

        var outputData = standardOutput.fileHandleForReading.readDataToEndOfFile()
        outputData.append(standardError.fileHandleForReading.readDataToEndOfFile())
        guard process.terminationStatus == 0 else {
            throw QEMUVersionError.nonzeroExit(process.terminationStatus)
        }
        guard let version = QEMUVersionParser.parse(String(decoding: outputData, as: UTF8.self)) else {
            throw QEMUVersionError.unrecognizedOutput
        }
        return version
    }

    private static func stop(
        _ process: Process,
        waitingOn termination: DispatchSemaphore
    ) {
        if process.isRunning {
            process.terminate()
        }
        if termination.wait(timeout: .now() + 1) == .success {
            return
        }

#if os(Linux) || os(macOS)
        if process.isRunning {
            _ = kill(process.processIdentifier, SIGKILL)
            _ = termination.wait(timeout: .now() + 1)
        }
#endif
    }
}
