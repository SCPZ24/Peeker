import AgentorProtocol
import XCTest
@testable import AgentorModule

final class CodexTranscriptMonitorTests: XCTestCase {
    func testParserAcceptsOnlyQuestionResolutionAndAbortShapes() throws {
        let session = AgentorSessionKey(agent: .codex, sessionID: "session")
        let arguments = #"{"questions":[{"id":"target","header":"Target","question":"Choose","options":[{"label":"A","description":"First"}]}]}"#
        let question: [String: Any] = [
            "type": "response_item",
            "payload": ["type": "function_call", "name": "request_user_input", "call_id": "call", "arguments": arguments],
        ]
        guard case let .question(request)? = CodexTranscriptMonitor.parse(question, session: session, turnID: "turn") else {
            return XCTFail("Expected question")
        }
        XCTAssertEqual(request.requestID, "call")
        XCTAssertEqual(request.questions.first?.options.first?.wireValue, "A")
        XCTAssertFalse(request.supportsWriteback)

        let output: [String: Any] = ["type": "response_item", "payload": ["type": "function_call_output", "call_id": "call", "output": "sensitive"]]
        guard case let .resolved(_, requestID, _, _)? = CodexTranscriptMonitor.parse(output, session: session, turnID: "turn") else {
            return XCTFail("Expected resolution")
        }
        XCTAssertEqual(requestID, "call")

        let aborted: [String: Any] = ["type": "event_msg", "payload": ["type": "turn_aborted", "turn_id": "turn", "reason": "interrupted"]]
        guard case let .aborted(_, _, outcome, _, _)? = CodexTranscriptMonitor.parse(aborted, session: session, turnID: nil) else {
            return XCTFail("Expected abort")
        }
        XCTAssertEqual(outcome, .cancel)
        XCTAssertNil(CodexTranscriptMonitor.parse(["type": "response_item", "payload": ["type": "message", "content": "secret"]], session: session, turnID: nil))
    }

    func testPartialCodexOptionsBecomeUnsafeInsteadOfDisplayingSubset() throws {
        let session = AgentorSessionKey(agent: .codex, sessionID: "session")
        let arguments = #"{"questions":[{"id":"q","question":"Choose","options":[{"label":"A"},{"description":"missing"}]}]}"#
        let object: [String: Any] = [
            "type": "response_item",
            "payload": ["type": "function_call", "name": "request_user_input", "call_id": "call", "arguments": arguments],
        ]
        guard case let .question(request)? = CodexTranscriptMonitor.parse(object, session: session, turnID: nil) else {
            return XCTFail("Expected question")
        }
        XCTAssertNotNil(request.validationFailure)
        XCTAssertTrue(request.questions[0].options.isEmpty)
    }
}
