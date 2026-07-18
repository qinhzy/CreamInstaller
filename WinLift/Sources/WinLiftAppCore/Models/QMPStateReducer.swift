import WinLiftCore

/// Keeps QMP-to-UI state transitions testable without launching QEMU.
enum QMPStateReducer {
    static func state(
        after message: QMPMessage,
        currentState: VMRuntimeState
    ) -> VMRuntimeState {
        guard case let .event(event) = message else { return currentState }

        switch event.uppercased() {
        case "STOP":
            return .paused
        case "RESUME":
            return .running
        case "SHUTDOWN", "POWERDOWN":
            return .stopping
        default:
            return currentState
        }
    }
}
