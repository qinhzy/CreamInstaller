import Foundation
import XCTest
@testable import WinLiftCore

final class VMStorageLayoutTests: XCTestCase {
    func testArtifactsStayInsideIDBasedBundle() {
        let root = URL(fileURLWithPath: "/Users/test/Library/Application Support/WinLift/Virtual Machines")
        let layout = VMStorageLayout(rootURL: root)
        let id = UUID(uuidString: "01234567-89AB-CDEF-0123-456789ABCDEF")!

        let bundle = layout.bundleURL(for: id)
        XCTAssertEqual(bundle.pathExtension, "winliftvm")
        XCTAssertEqual(layout.configurationURL(for: id).lastPathComponent, "config.json")
        XCTAssertEqual(layout.diskURL(for: id).lastPathComponent, "disk.raw")
        XCTAssertEqual(layout.efiVariablesURL(for: id).lastPathComponent, "efi-vars.fd")
        XCTAssertEqual(layout.runtimePIDURL(for: id).lastPathComponent, "qemu.pid")
        XCTAssertTrue(layout.diskURL(for: id).path.hasPrefix(bundle.path + "/"))
    }
}
