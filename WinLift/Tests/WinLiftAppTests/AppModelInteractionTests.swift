#if os(macOS)
import Foundation
import XCTest
@testable import WinLiftAppCore
@testable import WinLiftCore

/// 覆盖 AppModel 的真实交互流：创建、删除（含游离进程拦截）、
/// 编辑与磁盘扩容、更换 ISO、ISO 缺失检测。文件系统操作全部落在
/// 独立的临时目录里。
final class AppModelInteractionTests: XCTestCase {
    private var root: URL!
    private var isoURL: URL!
    private var store: VMFileStore!
    private var model: AppModel!

    @MainActor
    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinLiftAppTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        isoURL = root.appendingPathComponent("Windows11_ARM64.iso")
        FileManager.default.createFile(atPath: isoURL.path, contents: Data("iso".utf8))

        store = VMFileStore(layout: VMStorageLayout(rootURL: root.appendingPathComponent("VMs")))
        model = AppModel(store: store, runtime: QEMUProcessController(), fileManager: .default)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeDraft(diskSizeGiB: Int = 64) -> VMCreationDraft {
        var draft = VMCreationDraft()
        draft.name = "交互测试机"
        draft.cpuCount = 2
        draft.memorySizeGiB = 4
        draft.diskSizeGiB = diskSizeGiB
        draft.installerISOURL = isoURL
        return draft
    }

    private func apparentDiskSize(of machine: VirtualMachine) throws -> UInt64 {
        let attributes = try FileManager.default.attributesOfItem(
            atPath: store.layout.diskURL(for: machine.id).path
        )
        return (attributes[.size] as? NSNumber)?.uint64Value ?? 0
    }

    // MARK: - 创建

    @MainActor
    func testCreateProvisionsBundleAndSelectsMachine() async throws {
        let created = await model.createVM(from: makeDraft())
        XCTAssertTrue(created)
        XCTAssertEqual(model.machines.count, 1)

        let machine = try XCTUnwrap(model.machines.first)
        XCTAssertEqual(model.selectedMachineID, machine.id)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: store.layout.configurationURL(for: machine.id).path
        ))
        XCTAssertEqual(try apparentDiskSize(of: machine), 64 << 30)

        // 稀疏文件：表观 64 GiB，实际占用应远小于 1 MiB。
        let values = try store.layout.diskURL(for: machine.id)
            .resourceValues(forKeys: [.totalFileAllocatedSizeKey])
        XCTAssertLessThan(values.totalFileAllocatedSize ?? .max, 1 << 20)
    }

    @MainActor
    func testCreateWithoutISOFailsWithError() async {
        var draft = makeDraft()
        draft.installerISOURL = nil

        let created = await model.createVM(from: draft)
        XCTAssertFalse(created)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertTrue(model.machines.isEmpty)
    }

    @MainActor
    func testCreateWithMissingISOFileFailsWithError() async {
        var draft = makeDraft()
        draft.installerISOURL = root.appendingPathComponent("不存在.iso")

        let created = await model.createVM(from: draft)
        XCTAssertFalse(created)
        XCTAssertNotNil(model.errorMessage)
    }

    // MARK: - 删除

    @MainActor
    func testDeleteMovesBundleAwayAfterConfirmation() async throws {
        let created = await model.createVM(from: makeDraft())
        XCTAssertTrue(created)
        let machine = try XCTUnwrap(model.machines.first)
        let bundlePath = store.layout.bundleURL(for: machine.id).path

        model.requestDelete(machine)
        XCTAssertEqual(model.machinePendingDeletion?.id, machine.id)

        model.confirmDelete()
        XCTAssertNil(model.errorMessage)
        XCTAssertTrue(model.machines.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: bundlePath))
    }

    @MainActor
    func testDeleteIsBlockedWhileDetachedQEMUOwnsPidfile() async throws {
        let created = await model.createVM(from: makeDraft())
        XCTAssertTrue(created)
        let machine = try XCTUnwrap(model.machines.first)

        // 用测试进程自己的 PID 模拟一个仍然存活的游离 QEMU。
        let pidURL = store.layout.runtimePIDURL(for: machine.id)
        try String(ProcessInfo.processInfo.processIdentifier)
            .write(to: pidURL, atomically: true, encoding: .utf8)

        model.requestDelete(machine)
        model.confirmDelete()

        XCTAssertNotNil(model.errorMessage)
        XCTAssertEqual(model.machines.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: store.layout.bundleURL(for: machine.id).path
        ))
    }

    @MainActor
    func testStalePidfileDoesNotBlockDeletion() async throws {
        let created = await model.createVM(from: makeDraft())
        XCTAssertTrue(created)
        let machine = try XCTUnwrap(model.machines.first)

        // macOS 的 PID 上限是 99998；999999 一定不存在。
        let pidURL = store.layout.runtimePIDURL(for: machine.id)
        try "999999".write(to: pidURL, atomically: true, encoding: .utf8)

        model.requestDelete(machine)
        model.confirmDelete()

        XCTAssertNil(model.errorMessage)
        XCTAssertTrue(model.machines.isEmpty)
    }

    // MARK: - 编辑

    @MainActor
    func testApplyEditRenamesAndGrowsDisk() async throws {
        let created = await model.createVM(from: makeDraft())
        XCTAssertTrue(created)
        let machine = try XCTUnwrap(model.machines.first)

        model.beginEditing(machine)
        var draft = try XCTUnwrap(model.editingDraft)
        draft.name = "改名后的机器"
        draft.cpuCount = 2
        draft.memorySizeGiB = 8
        draft.diskSizeGiB = 96

        XCTAssertTrue(model.applyEdit(draft))
        let updated = try XCTUnwrap(model.machines.first)
        XCTAssertEqual(updated.name, "改名后的机器")
        XCTAssertEqual(updated.memorySizeGiB, 8)
        XCTAssertEqual(updated.diskSizeGiB, 96)
        XCTAssertEqual(try apparentDiskSize(of: updated), 96 << 30)

        // 修改已持久化：从磁盘重新加载后仍然一致。
        let reloaded = try store.loadAll().machines
        XCTAssertEqual(reloaded.first?.name, "改名后的机器")
        XCTAssertEqual(reloaded.first?.diskSizeGiB, 96)
    }

    @MainActor
    func testApplyEditRejectsDiskShrink() async throws {
        let created = await model.createVM(from: makeDraft())
        XCTAssertTrue(created)
        let machine = try XCTUnwrap(model.machines.first)

        model.beginEditing(machine)
        var draft = try XCTUnwrap(model.editingDraft)
        draft.diskSizeGiB = 32

        XCTAssertFalse(model.applyEdit(draft))
        XCTAssertNotNil(model.errorMessage)
        XCTAssertEqual(model.machines.first?.diskSizeGiB, 64)
        XCTAssertEqual(try apparentDiskSize(of: machine), 64 << 30)
    }

    @MainActor
    func testResetEFIVariablesRebuildsStoppedMachineFlash() async throws {
        let created = await model.createVM(from: makeDraft())
        XCTAssertTrue(created)
        let machine = try XCTUnwrap(model.machines.first)
        let url = store.layout.efiVariablesURL(for: machine.id)
        try Data(repeating: 0, count: 64).write(to: url)

        model.resetEFIVariables(for: machine)

        XCTAssertNil(model.errorMessage)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        XCTAssertEqual(
            (attributes[.size] as? NSNumber)?.uint64Value,
            VMProvisioner.efiVariablesSizeBytes
        )
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        XCTAssertEqual(try handle.read(upToCount: 1), Data([0xFF]))
    }

    // MARK: - 安装介质

    @MainActor
    func testReplaceISORejectsNonISOFile() async throws {
        let created = await model.createVM(from: makeDraft())
        XCTAssertTrue(created)
        let machine = try XCTUnwrap(model.machines.first)

        let imageURL = root.appendingPathComponent("disk.img")
        FileManager.default.createFile(atPath: imageURL.path, contents: Data())

        model.replaceInstallerISO(with: imageURL, for: machine.id)

        XCTAssertNotNil(model.errorMessage)
        XCTAssertEqual(model.machines.first?.installerISOPath, isoURL.path)
    }

    @MainActor
    func testReplaceISOPersistsNewPath() async throws {
        let created = await model.createVM(from: makeDraft())
        XCTAssertTrue(created)
        let machine = try XCTUnwrap(model.machines.first)

        let newISO = root.appendingPathComponent("Windows11_新版.iso")
        FileManager.default.createFile(atPath: newISO.path, contents: Data())

        model.replaceInstallerISO(with: newISO, for: machine.id)

        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.machines.first?.installerISOPath, newISO.path)
        XCTAssertEqual(try store.loadAll().machines.first?.installerISOPath, newISO.path)
    }

    @MainActor
    func testInstallerMissingDetection() async throws {
        let created = await model.createVM(from: makeDraft())
        XCTAssertTrue(created)
        let machine = try XCTUnwrap(model.machines.first)
        XCTAssertFalse(model.isInstallerMissing(for: machine))

        try FileManager.default.removeItem(at: isoURL)
        // 侧栏读取缓存，不会因为一次 View 重绘就重新 stat 文件。
        XCTAssertFalse(model.isInstallerMissing(for: try XCTUnwrap(model.machines.first)))
        model.reload()
        XCTAssertTrue(model.isInstallerMissing(for: try XCTUnwrap(model.machines.first)))

        // 弹出 ISO 后不再视为缺失。
        model.setInstallerAttached(false, for: machine.id)
        XCTAssertFalse(model.isInstallerMissing(for: try XCTUnwrap(model.machines.first)))
    }
}
#endif
