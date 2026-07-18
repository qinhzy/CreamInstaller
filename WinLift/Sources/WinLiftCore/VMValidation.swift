import Foundation

public enum VMValidationError: LocalizedError, Equatable, Sendable {
    case emptyName
    case nameTooLong
    case invalidName
    case invalidCPUCount(allowed: ClosedRange<Int>)
    case invalidMemorySize(allowed: ClosedRange<Int>)
    case invalidDiskSize(allowed: ClosedRange<Int>)
    case missingInstaller
    case invalidInstallerExtension

    public var errorDescription: String? {
        switch self {
        case .emptyName:
            return "虚拟机名称不能为空。"
        case .nameTooLong:
            return "虚拟机名称不能超过 64 个字符。"
        case .invalidName:
            return "虚拟机名称不能包含控制字符。"
        case let .invalidCPUCount(allowed):
            return "CPU 核心数必须在 \(allowed.lowerBound)–\(allowed.upperBound) 之间。"
        case let .invalidMemorySize(allowed):
            return "内存必须在 \(allowed.lowerBound)–\(allowed.upperBound) GiB 之间。"
        case let .invalidDiskSize(allowed):
            return "磁盘必须在 \(allowed.lowerBound)–\(allowed.upperBound) GiB 之间。"
        case .missingInstaller:
            return "首次安装需要选择 Windows 11 ARM64 ISO。"
        case .invalidInstallerExtension:
            return "安装介质必须是 .iso 文件。"
        }
    }
}

public enum VMValidator {
    public static let memoryRange = 4...128
    public static let diskRange = 32...2_048

    public static func validate(
        _ machine: VirtualMachine,
        hostProcessorCount: Int = ProcessInfo.processInfo.activeProcessorCount,
        hostMemoryGiB: Int = Int(ProcessInfo.processInfo.physicalMemory / 1_073_741_824)
    ) throws {
        let trimmedName = machine.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw VMValidationError.emptyName
        }
        guard trimmedName.count <= 64 else {
            throw VMValidationError.nameTooLong
        }
        guard trimmedName.unicodeScalars.allSatisfy({
            !CharacterSet.controlCharacters.contains($0)
        }) else {
            throw VMValidationError.invalidName
        }

        let maximumCPUCount = max(2, min(hostProcessorCount, 32))
        let cpuRange = 2...maximumCPUCount
        guard cpuRange.contains(machine.cpuCount) else {
            throw VMValidationError.invalidCPUCount(allowed: cpuRange)
        }
        let maximumMemoryGiB = max(
            memoryRange.lowerBound,
            min(hostMemoryGiB, memoryRange.upperBound)
        )
        let allowedMemoryRange = memoryRange.lowerBound...maximumMemoryGiB
        guard allowedMemoryRange.contains(machine.memorySizeGiB) else {
            throw VMValidationError.invalidMemorySize(allowed: allowedMemoryRange)
        }
        guard diskRange.contains(machine.diskSizeGiB) else {
            throw VMValidationError.invalidDiskSize(allowed: diskRange)
        }

        if machine.attachInstaller {
            guard let path = machine.installerISOPath, !path.isEmpty else {
                throw VMValidationError.missingInstaller
            }
            guard URL(fileURLWithPath: path).pathExtension.lowercased() == "iso" else {
                throw VMValidationError.invalidInstallerExtension
            }
        }
    }
}
