import Foundation
import XCTest
@testable import WinLiftCore

final class QMPStreamParserTests: XCTestCase {
    func testParsesFragmentedLinesAndMultipleLinesPerChunk() {
        var parser = QMPStreamParser()
        let chunks = [
            "{\"QMP\":{\"version\":{\"qemu\":{\"major\":9}}}}\r",
            "\n{\"return\":{}}\n{\"event\":\"ST",
            "OP\",\"data\":{}}\n{\"event\":\"RESUME\"}\n",
            "{\"event\":\"SHUT",
            "DOWN\",\"data\":{\"guest\":true}}\n"
        ]

        let messages = chunks.flatMap { parser.consume(Data($0.utf8)) }

        XCTAssertEqual(messages, [
            .greeting,
            .commandReturn,
            .event("STOP"),
            .event("RESUME"),
            .event("SHUTDOWN")
        ])
    }

    func testDoesNotEmitAnIncompleteLine() {
        var parser = QMPStreamParser()

        XCTAssertTrue(parser.consume(Data(#"{"event":"POWERDOWN"}"#.utf8)).isEmpty)
        XCTAssertEqual(parser.consume(Data("\n".utf8)), [.event("POWERDOWN")])
    }

    func testClassifiesUnknownAndInvalidJSONLinesWithoutLosingFollowingMessage() {
        var parser = QMPStreamParser()
        let data = Data("not-json\n{\"timestamp\":{}}\n{\"return\":null}\n".utf8)

        XCTAssertEqual(parser.consume(data), [.other, .other, .commandReturn])
    }
}
