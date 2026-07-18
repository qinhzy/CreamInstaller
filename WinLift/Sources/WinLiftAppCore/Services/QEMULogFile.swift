import Foundation

enum QEMULogFileError: LocalizedError {
    case couldNotCreate(String)

    var errorDescription: String? {
        switch self {
        case let .couldNotCreate(path):
            return "无法创建 QEMU 日志文件：\(path)"
        }
    }
}

enum QEMULogFile {
    static let rotationThresholdBytes = UInt64(5 * 1_024 * 1_024)

    static func openForAppending(
        at url: URL,
        rotationThresholdBytes thresholdBytes: UInt64 = QEMULogFile.rotationThresholdBytes,
        fileManager: FileManager = .default
    ) throws -> FileHandle {
        if fileManager.fileExists(atPath: url.path) {
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            let size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
            if size > thresholdBytes {
                let oldURL = url.appendingPathExtension("old")
                if fileManager.fileExists(atPath: oldURL.path) {
                    try fileManager.removeItem(at: oldURL)
                }
                try fileManager.moveItem(at: url, to: oldURL)
            }
        }

        if !fileManager.fileExists(atPath: url.path) {
            guard fileManager.createFile(atPath: url.path, contents: nil) else {
                throw QEMULogFileError.couldNotCreate(url.path)
            }
        }

        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        return handle
    }
}
