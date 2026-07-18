import Foundation
import XCTest
@testable import WinLiftAppCore
@testable import WinLiftCore

final class QMPStateReducerTests: XCTestCase {
    func testFragmentedEventStreamDrivesRuntimeState() {
        var parser = QMPStreamParser()
        var state = VMRuntimeState.running
        var states: [VMRuntimeState] = []

        let chunks = [
            "{\"event\":\"ST",
            "OP\"}\n{\"event\":\"RESUME\"}\n{\"event\":\"SHUT",
            "DOWN\",\"data\":{\"guest\":true}}\n"
        ]
        for chunk in chunks {
            for message in parser.consume(Data(chunk.utf8)) {
                state = QMPStateReducer.state(after: message, currentState: state)
                states.append(state)
            }
        }

        XCTAssertEqual(states, [.paused, .running, .stopping])
    }

    func testPowerdownAlsoConfirmsStoppingAndUnknownEventsDoNotChangeState() {
        XCTAssertEqual(
            QMPStateReducer.state(after: .event("POWERDOWN"), currentState: .running),
            .stopping
        )
        XCTAssertEqual(
            QMPStateReducer.state(after: .event("RESET"), currentState: .paused),
            .paused
        )
    }
}
