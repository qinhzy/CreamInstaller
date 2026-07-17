import Foundation

public struct VirtualMachine: Codable, Hashable, Identifiable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public let id: UUID
    public var name: String
    public var cpuCount: Int
    public var memorySizeGiB: Int
    public var diskSizeGiB: Int
    public var installerISOPath: String?
    public var attachInstaller: Bool
    public let createdAt: Date

    public init(
        schemaVersion: Int = VirtualMachine.currentSchemaVersion,
        id: UUID = UUID(),
        name: String,
        cpuCount: Int,
        memorySizeGiB: Int,
        diskSizeGiB: Int,
        installerISOPath: String?,
        attachInstaller: Bool = true,
        createdAt: Date = Date()
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.name = name
        self.cpuCount = cpuCount
        self.memorySizeGiB = memorySizeGiB
        self.diskSizeGiB = diskSizeGiB
        self.installerISOPath = installerISOPath
        self.attachInstaller = attachInstaller
        self.createdAt = createdAt
    }
}
