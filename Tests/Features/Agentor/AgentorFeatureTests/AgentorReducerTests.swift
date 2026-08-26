import AgentorProtocol
import XCTest
@testable import AgentorFeature

final class AgentorReducerTests: XCTestCase {
    func testSessionsQuestionsToolsAndTerminalOutcomeReduceDeterministically() {
        let start = Date(timeIntervalSince1970: 100)
        let key = AgentorSessionKey(agent: .claude, sessionID: "session")
        var reducer = AgentorReducer()

        XCTAssertEqual(reducer.apply(event("start", at: start, key: key, name: .turnStarted)), [.started(key, eventID: "start")])
        _ = reducer.apply(event("tool", at: start.addingTimeInterval(1), key: key, name: .toolStarted, toolID: "tool-1"))
        XCTAssertEqual(reducer.sessions[key]?.status, .runningTool)

        let question = request("request", key: key, occurredAt: start.addingTimeInterval(2))
        XCTAssertNil(reducer.open(question).1)
        XCTAssertEqual(reducer.sessions[key]?.status, .waitingForAnswer)
        XCTAssertEqual(reducer.pendingRequests.count, 1)

        _ = reducer.apply(event("done", at: start.addingTimeInterval(3), key: key, name: .turnEnded, outcome: .normal))
        XCTAssertTrue(reducer.sessions.isEmpty)
        XCTAssertTrue(reducer.pendingRequests.isEmpty)

        _ = reducer.apply(event("late", at: start.addingTimeInterval(4), key: key, name: .toolStarted, toolID: "tool-2"))
        XCTAssertTrue(reducer.sessions.isEmpty)
    }

    func testExplicitStartWithoutTurnIDCreatesANewGeneration() {
        let key = AgentorSessionKey(agent: .openCode, sessionID: "session")
        var reducer = AgentorReducer()
        _ = reducer.apply(AgentorEvent(
            eventID: "first", occurredAt: Date(timeIntervalSince1970: 1),
            session: key, name: .turnStarted
        ))
        let firstGeneration = reducer.sessions[key]?.generation
        _ = reducer.open(request("pending", key: key, occurredAt: Date(timeIntervalSince1970: 2)))

        let effects = reducer.apply(AgentorEvent(
            eventID: "second", occurredAt: Date(timeIntervalSince1970: 3),
            session: key, name: .turnStarted
        ))

        XCTAssertNotEqual(reducer.sessions[key]?.generation, firstGeneration)
        XCTAssertTrue(reducer.pendingRequests.isEmpty)
        XCTAssertTrue(effects.contains(.requestResolved(key, "pending", upstream: true)))
        XCTAssertTrue(effects.contains(.started(key, eventID: "second")))
    }

    func testSubagentQuestionAttachesToParentAndConcurrentRequestsRemainOrdered() {
        let parent = AgentorSessionKey(agent: .openCode, sessionID: "parent")
        let child = AgentorSessionKey(agent: .openCode, sessionID: "child")
        var reducer = AgentorReducer()
        _ = reducer.apply(event("start", at: Date(timeIntervalSince1970: 1), key: parent, name: .turnStarted))

        var first = request("one", key: child, occurredAt: Date(timeIntervalSince1970: 2), parent: "parent")
        var second = request("two", key: child, occurredAt: Date(timeIntervalSince1970: 3), parent: "parent")
        first = AgentorQuestionRequest(
            requestID: first.requestID, occurredAt: first.occurredAt, session: first.session,
            turnID: first.turnID, parentSessionID: first.parentSessionID, title: first.title,
            workingDirectoryName: first.workingDirectoryName, process: first.process,
            supportsWriteback: false, questions: first.questions
        )
        second = AgentorQuestionRequest(
            requestID: second.requestID, occurredAt: second.occurredAt, session: second.session,
            turnID: second.turnID, parentSessionID: second.parentSessionID, title: second.title,
            workingDirectoryName: second.workingDirectoryName, process: second.process,
            supportsWriteback: false, questions: second.questions
        )
        _ = reducer.open(first)
        _ = reducer.open(second)

        XCTAssertEqual(reducer.sessions[parent]?.pendingRequestIDs, ["one", "two"])
        XCTAssertNil(reducer.sessions[child])
    }

    func testRuntimeCapacityRejectsThe101stSessionAndQuestion() {
        var reducer = AgentorReducer()
        for index in 0..<AgentorContract.maximumActiveSessions {
            let key = AgentorSessionKey(agent: .pi, sessionID: "s-\(index)")
            _ = reducer.apply(event("e-\(index)", at: Date(timeIntervalSince1970: Double(index)), key: key, name: .turnStarted))
        }
        let overflowKey = AgentorSessionKey(agent: .pi, sessionID: "overflow")
        XCTAssertEqual(
            reducer.apply(event("overflow", at: Date(timeIntervalSince1970: 200), key: overflowKey, name: .turnStarted)),
            [.droppedCapacity]
        )

        var questionReducer = AgentorReducer()
        let key = AgentorSessionKey(agent: .claude, sessionID: "session")
        for index in 0..<AgentorContract.maximumPendingRequests {
            XCTAssertNil(questionReducer.open(request("r-\(index)", key: key, occurredAt: Date(timeIntervalSince1970: Double(index)))).1)
        }
        XCTAssertEqual(
            questionReducer.open(request("overflow", key: key, occurredAt: Date(timeIntervalSince1970: 200))).1,
            .capacityExceeded
        )
    }

    func testDraftProducesWireValuesInQuestionOrder() {
        let key = AgentorSessionKey(agent: .openCode, sessionID: "s")
        let request = AgentorQuestionRequest(
            requestID: "r", session: key, supportsWriteback: true,
            questions: [
                AgentorQuestion(id: "q1", answerKey: "first", body: "First", kind: .multiple, options: [
                    AgentorQuestionOption(id: "a", label: "A", wireValue: "a"),
                    AgentorQuestionOption(id: "b", label: "B", wireValue: "b"),
                ]),
                AgentorQuestion(id: "q2", answerKey: "second", body: "Second", kind: .text),
            ]
        )
        var reducer = AgentorReducer()
        _ = reducer.open(request)
        var first = AgentorQuestionDraft()
        first.selectedValues = ["b", "a"]
        reducer.setDraft(first, questionID: "q1", requestID: "r")
        var second = AgentorQuestionDraft()
        second.text = "answer"
        reducer.setDraft(second, questionID: "q2", requestID: "r")

        XCTAssertEqual(reducer.markSubmitting("r"), [
            AgentorAnswer(questionID: "q1", answerKey: "first", values: ["a", "b"]),
            AgentorAnswer(questionID: "q2", answerKey: "second", values: ["answer"]),
        ])
    }

    private func event(
        _ id: String,
        at date: Date,
        key: AgentorSessionKey,
        name: AgentorEventName,
        toolID: String? = nil,
        outcome: AgentorTurnOutcome? = nil
    ) -> AgentorEvent {
        AgentorEvent(eventID: id, occurredAt: date, session: key, turnID: "turn", name: name, toolID: toolID, outcome: outcome)
    }

    private func request(
        _ id: String,
        key: AgentorSessionKey,
        occurredAt: Date,
        parent: String? = nil
    ) -> AgentorQuestionRequest {
        AgentorQuestionRequest(
            requestID: id, occurredAt: occurredAt, session: key, parentSessionID: parent,
            supportsWriteback: true,
            questions: [AgentorQuestion(
                id: "q-\(id)", answerKey: "Question \(id)", body: "Question", kind: .single,
                options: [AgentorQuestionOption(id: "yes", label: "Yes", wireValue: "yes")]
            )]
        )
    }
}
