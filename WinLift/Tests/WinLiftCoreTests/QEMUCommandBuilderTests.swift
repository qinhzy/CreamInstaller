import Foundation
import XCTest
@testable import WinLiftCore

final class QEMUCommandBuilderTests: XCTestCase {
    private let machineID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!

    func testBuildsAcceleratedARMCommandWithNativeWindowsDevices() {
        let arguments = makeArguments(attachInstaller: true)

        XCTAssertEqual(value(after: "-accel", in: arguments), "hvf")
        XCTAssertEqual(value(after: "-cpu", in: arguments), "host")
        XCTAssertTrue(arguments.contains("nvme,drive=systemdisk,serial=WINLIFT-AAAAAAAABBBB,bootindex=1"))
        XCTAssertTrue(arguments.contains("nec-usb-xhci,id=usb-bus"))
        XCTAssertTrue(arguments.contains("usb-kbd,bus=usb-bus.0"))
        XCTAssertTrue(arguments.contains("usb-tablet,bus=usb-bus.0"))
        XCTAssertTrue(arguments.contains("usb-net,netdev=net0,bus=usb-bus.0"))
        XCTAssertTrue(arguments.contains("ramfb"))
        XCTAssertTrue(arguments.contains("usb-storage,drive=installer,removable=true,bootindex=0,bus=usb-bus.0"))
        XCTAssertEqual(value(after: "-qmp", in: arguments), "stdio")
        XCTAssertEqual(value(after: "-pidfile", in: arguments)?.hasSuffix("qemu.pid"), true)
    }

    func testOmitsInstallerAfterInstallationIsComplete() {
        let arguments = makeArguments(attachInstaller: false)

        XCTAssertFalse(arguments.contains(where: { $0.contains("usb-storage,drive=installer") }))
        XCTAssertFalse(arguments.contains(where: { $0.contains("id=installer") }))
    }

    func testEscapesCommaInsideQEMUOptionPath() {
        XCTAssertEqual(
            QEMUCommandBuilder.escapedOptionValue("/Users/William/VMs/a,b/disk.raw"),
            "/Users/William/VMs/a,,b/disk.raw"
        )
    }

    private func makeArguments(attachInstaller: Bool) -> [String] {
        let machine = VirtualMachine(
            id: machineID,
            name: "Windows Test",
            cpuCount: 4,
            memorySizeGiB: 8,
            diskSizeGiB: 64,
            installerISOPath: "/Users/test/Windows11_ARM64.iso",
            attachInstaller: attachInstaller
        )
        let layout = VMStorageLayout(rootURL: URL(fileURLWithPath: "/tmp/WinLift Tests"))
        let installation = QEMUInstallation(
            executableURL: URL(fileURLWithPath: "/opt/homebrew/bin/qemu-system-aarch64"),
            firmwareURL: URL(fileURLWithPath: "/opt/homebrew/share/qemu/edk2-aarch64-code.fd")
        )

        return QEMUCommandBuilder.arguments(
            machine: machine,
            layout: layout,
            installation: installation
        )
    }

    private func value(after option: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: option), index + 1 < arguments.endIndex else {
            return nil
        }
        return arguments[index + 1]
    }
}
