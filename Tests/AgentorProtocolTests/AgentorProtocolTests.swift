import XCTest
@testable import AgentorProtocol

final class AgentorProtocolTests: XCTestCase {
    func testFrameRoundTripsQuestionRequest() throws {
        let question = AgentorQuestionRequest(
            requestID: "request-1",
            occurredAt: Date(timeIntervalSince1970: 1_000),
            session: AgentorSessionKey(agent: .claude, sessionID: "session-1"),
            supportsWriteback: true,
            questions: [AgentorQuestion(
                id: "q1", answerKey: "Choose", body: "Choose", kind: .single,
                options: [AgentorQuestionOption(id: "a", label: "A", wireValue: "a")]
            )]
        )
        let request = AgentorRequest(question: question)
        let decoded = try AgentorFrameCodec.decode(
            AgentorRequest.self,
            from: AgentorFrameCodec.encode(request)
        )
        XCTAssertEqual(decoded, request)
        XCTAssertNil(decoded.question?.validationFailure)
    }

    func testQuestionValidationRejectsDuplicateAnswerKeysAndTooManyOptions() {
        let options = (0..<6).map {
            AgentorQuestionOption(id: "o\($0)", label: "\($0)", wireValue: "\($0)")
        }
        let request = AgentorQuestionRequest(
            requestID: "r",
            session: AgentorSessionKey(agent: .openCode, sessionID: "s"),
            supportsWriteback: true,
            questions: [
                AgentorQuestion(id: "q1", answerKey: "same", body: "One", kind: .single, options: options),
                AgentorQuestion(id: "q2", answerKey: "same", body: "Two", kind: .text),
            ]
        )
        XCTAssertEqual(request.validationFailure, .invalidOptionCount)
    }

    func testFrameRejectsOversizedPayload() {
        let response = AgentorResponse.rejected(String(repeating: "x", count: AgentorContract.maximumFrameBytes))
        XCTAssertThrowsError(try AgentorFrameCodec.encode(response)) { error in
            XCTAssertEqual(error as? AgentorValidationError, .frameTooLarge)
        }
    }
}
