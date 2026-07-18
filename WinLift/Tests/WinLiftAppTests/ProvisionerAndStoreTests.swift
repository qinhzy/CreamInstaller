import Foundation
import XCTest
@testable import WinLiftAppCore
@testable import WinLiftCore

/// VMProvisioner 与 VMFileStore 的纯文件系统行为，macOS 和 Linux 都执行。
final class ProvisionerAndStoreTests: XCTestCase {
    private var root: URL!
    private var store: VMFileStore!
    private var provisioner: VMProvisioner!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinLiftProvisionerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        store = VMFileStore(layout: VMStorageLayout(rootURL: root))
        provisioner = VMProvisioner(store: store)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeMachine(diskSizeGiB: Int = 64) -> VirtualMachine {
        VirtualMachine(
            name: "Provision 测试",
            cpuCount: 2,
            memorySizeGiB: 4,
            diskSizeGiB: diskSizeGiB,
            installerISOPath: "/tmp/fake/Windows11.iso"
        )
    }

    private func apparentSize(_ url: URL) throws -> UInt64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.size] as? NSNumber)?.uint64Value ?? 0
    }

    func testProvisionCreatesSparseDiskVarsAndConfig() throws {
        let machine = makeMachine()
        try provisioner.provision(machine)

        XCTAssertEqual(try apparentSize(store.layout.diskURL(for: machine.id)), 64 << 30)
        XCTAssertEqual(try apparentSize(store.layout.efiVariablesURL(for: machine.id)), 64 << 20)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: store.layout.configurationURL(for: machine.id).path
        ))
    }

    func testProvisionRefusesExistingBundle() throws {
        let machine = makeMachine()
        try FileManager.default.createDirectory(
            at: store.layout.bundleURL(for: machine.id),
            withIntermediateDirectories: true
        )

        XCTAssertThrowsError(try provisioner.provision(machine))
    }

    func testGrowDiskExtendsButNeverShrinks() throws {
        var machine = makeMachine()
        try provisioner.provision(machine)
        let diskURL = store.layout.diskURL(for: machine.id)

        machine.diskSizeGiB = 96
        try provisioner.growDisk(for: machine)
        XCTAssertEqual(try apparentSize(diskURL), 96 << 30)

        // 请求一个更小的容量必须是无操作，不能截断数据。
        machine.diskSizeGiB = 32
        try provisioner.growDisk(for: machine)
        XCTAssertEqual(try apparentSize(diskURL), 96 << 30)
    }

    func testStoreRoundTripsConfiguration() throws {
        let machine = makeMachine()
        try provisioner.provision(machine)

        let loaded = try store.loadAll()
        XCTAssertTrue(loaded.warnings.isEmpty)
        // createdAt 经 ISO8601 编码会丢掉亚秒精度，逐字段比较关键属性。
        XCTAssertEqual(loaded.machines.map(\.id), [machine.id])
        XCTAssertEqual(loaded.machines.first?.name, machine.name)
        XCTAssertEqual(loaded.machines.first?.cpuCount, machine.cpuCount)
        XCTAssertEqual(loaded.machines.first?.diskSizeGiB, machine.diskSizeGiB)
        XCTAssertEqual(loaded.machines.first?.installerISOPath, machine.installerISOPath)
    }

    func testCorruptedConfigurationBecomesWarningNotCrash() throws {
        let machine = makeMachine()
        try provisioner.provision(machine)
        try Data("not json".utf8).write(to: store.layout.configurationURL(for: machine.id))

        let loaded = try store.loadAll()
        XCTAssertTrue(loaded.machines.isEmpty)
        XCTAssertEqual(loaded.warnings.count, 1)
    }
}
