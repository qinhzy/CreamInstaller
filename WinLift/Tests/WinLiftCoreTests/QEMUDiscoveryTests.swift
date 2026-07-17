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
        FileManager.default.createFile(atPath: executable.path, contents: Data())
        FileManager.default.createFile(atPath: firmware.path, contents: Data())
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executable.path
        )

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
        FileManager.default.createFile(atPath: executable.path, contents: Data())
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executable.path
        )

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
}
