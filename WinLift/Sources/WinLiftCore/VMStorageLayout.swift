import Foundation

public struct VMStorageLayout: Sendable {
    public let rootURL: URL

    public init(rootURL: URL) {
        self.rootURL = rootURL
    }

    public func bundleURL(for machineID: UUID) -> URL {
        rootURL
            .appendingPathComponent(machineID.uuidString, isDirectory: true)
            .appendingPathExtension("winliftvm")
    }

    public func configurationURL(for machineID: UUID) -> URL {
        bundleURL(for: machineID).appendingPathComponent("config.json")
    }

    public func diskURL(for machineID: UUID) -> URL {
        bundleURL(for: machineID).appendingPathComponent("disk.raw")
    }

    public func efiVariablesURL(for machineID: UUID) -> URL {
        bundleURL(for: machineID).appendingPathComponent("efi-vars.fd")
    }

    public func logURL(for machineID: UUID) -> URL {
        bundleURL(for: machineID).appendingPathComponent("qemu.log")
    }

    public func runtimePIDURL(for machineID: UUID) -> URL {
        bundleURL(for: machineID).appendingPathComponent("qemu.pid")
    }
}
