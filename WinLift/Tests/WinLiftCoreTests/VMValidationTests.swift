import XCTest
@testable import WinLiftCore

final class VMValidationTests: XCTestCase {
    func testValidWindowsMachinePassesValidation() throws {
        let machine = makeMachine()
        XCTAssertNoThrow(try VMValidator.validate(machine, hostProcessorCount: 8))
    }

    func testInstallerIsRequiredWhenAttachmentIsEnabled() {
        var machine = makeMachine()
        machine.installerISOPath = nil

        XCTAssertThrowsError(try VMValidator.validate(machine, hostProcessorCount: 8)) { error in
            XCTAssertEqual(error as? VMValidationError, .missingInstaller)
        }
    }

    func testInstallerMayBeOmittedAfterInstallation() throws {
        var machine = makeMachine()
        machine.installerISOPath = nil
        machine.attachInstaller = false

        XCTAssertNoThrow(try VMValidator.validate(machine, hostProcessorCount: 8))
    }

    func testCPUCountCannotExceedHostLimit() {
        var machine = makeMachine()
        machine.cpuCount = 12

        XCTAssertThrowsError(try VMValidator.validate(machine, hostProcessorCount: 8)) { error in
            XCTAssertEqual(error as? VMValidationError, .invalidCPUCount(allowed: 2...8))
        }
    }

    func testMemoryBelowMinimumIsRejected() {
        var machine = makeMachine()
        machine.memorySizeGiB = 2

        XCTAssertThrowsError(try VMValidator.validate(machine, hostProcessorCount: 8)) { error in
            XCTAssertEqual(
                error as? VMValidationError,
                .invalidMemorySize(allowed: VMValidator.memoryRange)
            )
        }
    }

    func testDiskBelowMinimumIsRejected() {
        var machine = makeMachine()
        machine.diskSizeGiB = 16

        XCTAssertThrowsError(try VMValidator.validate(machine, hostProcessorCount: 8)) { error in
            XCTAssertEqual(
                error as? VMValidationError,
                .invalidDiskSize(allowed: VMValidator.diskRange)
            )
        }
    }

    func testInstallerMustHaveISOExtension() {
        var machine = makeMachine()
        machine.installerISOPath = "/Users/test/Windows11_ARM64.img"

        XCTAssertThrowsError(try VMValidator.validate(machine, hostProcessorCount: 8)) { error in
            XCTAssertEqual(error as? VMValidationError, .invalidInstallerExtension)
        }
    }

    func testControlCharactersInNameAreRejected() {
        var machine = makeMachine()
        machine.name = "Windows\u{07}11"

        XCTAssertThrowsError(try VMValidator.validate(machine, hostProcessorCount: 8)) { error in
            XCTAssertEqual(error as? VMValidationError, .invalidName)
        }
    }

    private func makeMachine() -> VirtualMachine {
        VirtualMachine(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            name: "Windows 11",
            cpuCount: 4,
            memorySizeGiB: 8,
            diskSizeGiB: 64,
            installerISOPath: "/Users/test/Windows11_ARM64.iso"
        )
    }
}
