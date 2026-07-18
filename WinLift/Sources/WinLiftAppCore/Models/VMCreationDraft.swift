import Foundation

struct VMCreationDraft {
    var name = "Windows 11"
    var cpuCount: Int
    var memorySizeGiB: Int
    var diskSizeGiB = 64
    var installerISOURL: URL?

    init(processInfo: ProcessInfo = .processInfo) {
        let processorCount = max(2, processInfo.activeProcessorCount)
        cpuCount = min(8, max(2, processorCount / 2))

        let gibibyte = UInt64(1_073_741_824)
        let physicalMemoryGiB = max(4, Int(processInfo.physicalMemory / gibibyte))
        memorySizeGiB = min(16, max(4, physicalMemoryGiB / 2))
    }
}
