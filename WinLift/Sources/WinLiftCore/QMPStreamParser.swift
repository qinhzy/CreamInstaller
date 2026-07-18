import Foundation

/// A structural classification of one newline-delimited QMP JSON message.
public enum QMPMessage: Equatable, Sendable {
    case greeting
    case commandReturn
    case event(String)
    case other
}

/// Incrementally turns arbitrary QMP stdout chunks into complete JSON messages.
///
/// QEMU writes one JSON object per line, but `FileHandle` callbacks are free to
/// split a line at any byte or deliver several lines at once. Keeping the
/// pending bytes as `Data` also makes splits inside a multi-byte UTF-8 scalar
/// safe.
public struct QMPStreamParser: Sendable {
    private var pendingBytes = Data()

    public init() {}

    public mutating func consume(_ chunk: Data) -> [QMPMessage] {
        guard !chunk.isEmpty else { return [] }
        pendingBytes.append(chunk)

        var messages: [QMPMessage] = []
        while let newlineIndex = pendingBytes.firstIndex(of: 0x0A) {
            var line = Data(pendingBytes[..<newlineIndex])
            let nextIndex = pendingBytes.index(after: newlineIndex)
            pendingBytes.removeSubrange(pendingBytes.startIndex..<nextIndex)

            if line.last == 0x0D {
                line.removeLast()
            }
            guard !line.isEmpty else { continue }
            messages.append(Self.classify(line))
        }
        return messages
    }

    private static func classify(_ line: Data) -> QMPMessage {
        guard
            let json = try? JSONSerialization.jsonObject(with: line),
            let object = json as? [String: Any]
        else {
            return .other
        }

        if object["QMP"] != nil {
            return .greeting
        }
        if object.keys.contains("return") {
            return .commandReturn
        }
        if let event = object["event"] as? String {
            return .event(event)
        }
        return .other
    }
}
