import Foundation
import WinLiftCore

/// 编辑既有虚拟机时的临时状态。磁盘只允许扩容，下限固定为当前容量。
struct VMEditDraft: Identifiable {
    let machineID: UUID
    let minimumDiskSizeGiB: Int
    let currentISOPath: String?
    var name: String
    var cpuCount: Int
    var memorySizeGiB: Int
    var diskSizeGiB: Int
    /// 新选择的 ISO；nil 表示保留现有安装介质。
    var installerISOURL: URL?

    init(machine: VirtualMachine) {
        machineID = machine.id
        minimumDiskSizeGiB = machine.diskSizeGiB
        currentISOPath = machine.installerISOPath
        name = machine.name
        cpuCount = machine.cpuCount
        memorySizeGiB = machine.memorySizeGiB
        diskSizeGiB = machine.diskSizeGiB
    }

    var id: UUID { machineID }
}
