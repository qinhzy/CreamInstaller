import Foundation
import XCTest
@testable import WinLiftCore

final class QEMUDiscoveryTests: XCTestCase {
    func testExplicitOverridesAreUsed() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let executable = root.appendingPathComponent("qemu-system-aarch64")
        let firmware = root.appendingPathComponent("edk2-aarch64-code.fd")
        try writeExecutable(at: executable, cpuType: 0x0100_000C)
        try createSparseFile(at: firmware, size: QEMUDiscovery.expectedFirmwareSizeBytes)

        let result = try QEMUDiscovery.discover(environment: [
            "WINLIFT_QEMU_SYSTEM": executable.path,
            "WINLIFT_QEMU_FIRMWARE": firmware.path
        ])

        XCTAssertEqual(result.executableURL.path, executable.path)
        XCTAssertEqual(result.firmwareURL.path, firmware.path)
    }

    func testStandardHomebrewPathIsFirstCandidate() {
        let candidates = QEMUDiscovery.executableCandidates(environment: [:])
        XCTAssertEqual(candidates.first?.path, "/opt/homebrew/bin/qemu-system-aarch64")
    }

    func testPATHDirectoriesAreSearchedAfterFixedLocations() {
        let candidates = QEMUDiscovery.executableCandidates(environment: [
            "PATH": "/first/bin:/second/bin"
        ])
        XCTAssertTrue(candidates.map(\.path).contains("/first/bin/qemu-system-aarch64"))
        XCTAssertTrue(candidates.map(\.path).contains("/second/bin/qemu-system-aarch64"))
    }

    func testInvalidExecutableOverrideIsReported() {
        XCTAssertThrowsError(try QEMUDiscovery.discover(environment: [
            "WINLIFT_QEMU_SYSTEM": "/nonexistent/qemu-system-aarch64"
        ])) { error in
            XCTAssertEqual(
                error as? QEMUDiscoveryError,
                .invalidExecutableOverride("/nonexistent/qemu-system-aarch64")
            )
        }
    }

    func testInvalidFirmwareOverrideIsReported() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let executable = root.appendingPathComponent("qemu-system-aarch64")
        try writeExecutable(at: executable, cpuType: 0x0100_000C)

        XCTAssertThrowsError(try QEMUDiscovery.discover(environment: [
            "WINLIFT_QEMU_SYSTEM": executable.path,
            "WINLIFT_QEMU_FIRMWARE": "/nonexistent/edk2-aarch64-code.fd"
        ])) { error in
            XCTAssertEqual(
                error as? QEMUDiscoveryError,
                .invalidFirmwareOverride("/nonexistent/edk2-aarch64-code.fd")
            )
        }
    }

    func testMachOInspectorReadsThinARM64Header() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = root.appendingPathComponent("thin-arm64")
        try writeExecutable(at: executable, cpuType: 0x0100_000C)

        XCTAssertEqual(try MachOInspector.architectures(at: executable), [.arm64])
    }

    func testMachOInspectorReadsFatHeaderWithARM64Slice() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = root.appendingPathComponent("universal-qemu")
        try fatMachOHeader(cpuTypes: [0x0100_0007, 0x0100_000C]).write(to: executable)

        XCTAssertEqual(
            try MachOInspector.architectures(at: executable),
            [.x86_64, .arm64]
        )
        XCTAssertNoThrow(try QEMUDiscovery.validateExecutableArchitecture(
            at: executable,
            requiresARM64: true
        ))
    }

    func testIntelOnlyMachOProducesActionableHVFError() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = root.appendingPathComponent("intel-qemu")
        try writeExecutable(at: executable, cpuType: 0x0100_0007)

        XCTAssertThrowsError(try QEMUDiscovery.validateExecutableArchitecture(
            at: executable,
            requiresARM64: true
        )) { error in
            XCTAssertEqual(error as? QEMUDiscoveryError, .intelExecutableOnAppleSilicon)
            XCTAssertEqual(
                error.localizedDescription,
                "检测到 Intel 版 QEMU，HVF 不可用，请安装 arm64 版。"
            )
        }
    }

    func testInvalidFirmwareSizeIsReportedSeparately() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = root.appendingPathComponent("qemu-system-aarch64")
        let firmware = root.appendingPathComponent("edk2-aarch64-code.fd")
        try writeExecutable(at: executable, cpuType: 0x0100_000C)
        try createSparseFile(at: firmware, size: 1_048_576)

        XCTAssertThrowsError(try QEMUDiscovery.discover(environment: [
            "WINLIFT_QEMU_SYSTEM": executable.path,
            "WINLIFT_QEMU_FIRMWARE": firmware.path
        ])) { error in
            XCTAssertEqual(
                error as? QEMUDiscoveryError,
                .invalidFirmwareSize(
                    expectedBytes: QEMUDiscovery.expectedFirmwareSizeBytes,
                    actualBytes: 1_048_576
                )
            )
        }
    }

    func testParsesQEMUVersionStrings() {
        XCTAssertEqual(
            QEMUVersionParser.parse("QEMU emulator version 9.2.3\nCopyright..."),
            "9.2.3"
        )
        XCTAssertEqual(
            QEMUVersionParser.parse("QEMU emulator version v10.0.0 (Homebrew)"),
            "10.0.0"
        )
        XCTAssertNil(QEMUVersionParser.parse("not QEMU output"))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func writeExecutable(at url: URL, cpuType: UInt32) throws {
        try thinMachOHeader(cpuType: cpuType).write(to: url)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: url.path
        )
    }

    private func createSparseFile(at url: URL, size: UInt64) throws {
        try Data().write(to: url)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.truncate(atOffset: size)
    }

    private func thinMachOHeader(cpuType: UInt32) -> Data {
        var data = Data([0xCF, 0xFA, 0xED, 0xFE])
        data.append(contentsOf: littleEndianBytes(cpuType))
        return data
    }

    private func fatMachOHeader(cpuTypes: [UInt32]) -> Data {
        var data = Data([0xCA, 0xFE, 0xBA, 0xBE])
        data.append(contentsOf: bigEndianBytes(UInt32(cpuTypes.count)))
        for cpuType in cpuTypes {
            data.append(contentsOf: bigEndianBytes(cpuType))
            data.append(Data(repeating: 0, count: 16))
        }
        return data
    }

    private func bigEndianBytes(_ value: UInt32) -> [UInt8] {
        [
            UInt8((value >> 24) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF)
        ]
    }

    private func littleEndianBytes(_ value: UInt32) -> [UInt8] {
        Array(bigEndianBytes(value).reversed())
    }
}
