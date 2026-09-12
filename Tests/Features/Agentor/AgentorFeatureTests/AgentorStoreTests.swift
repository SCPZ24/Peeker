import AgentorProtocol
import FunctionCardKit
import XCTest
import PeekerCore
@testable import AgentorFeature

@MainActor
final class AgentorStoreTests: XCTestCase {
    func testWritebackFailureRetainsInputWithoutResubmittingOrShowingSuccessNotice() {
        var answersSent = 0
        let store = AgentorStore(dependencies: AgentorFeatureDependencies(publishPrompt: { _ in }, revokePrompt: { _ in }, setEditingText: { _ in }))
        let key = AgentorSessionKey(agent: .openCode, sessionID: "session")
        let request = AgentorQuestionRequest(requestID: "request", occurredAt: Date(), session: key, supportsWriteback: true,
            questions: [AgentorQuestion(id: "q", answerKey: "answer", body: "Question", kind: .text)])
        store.receive(request) { response in if response.kind == .answer { answersSent += 1 } }
        var draft = AgentorQuestionDraft()
        draft.text = "未保存の回答\n第二行"
        store.setDraft(draft, questionID: "q", requestID: "request")
        store.submit(requestID: "request")
        store.receive(AgentorEvent(eventID: "failed", occurredAt: Date(), session: key, name: .writebackFailed, requestID: "request"))
        XCTAssertEqual(answersSent, 1)
        XCTAssertEqual(store.retainedDrafts.first?.drafts["q"]?.text, draft.text)
        XCTAssertNil(store.reducer.sessions[key]?.resolutionNotice)
        XCTAssertNil(store.reducer.pendingRequests["request"])
        store.discardRetainedDraft("request")
        XCTAssertTrue(store.retainedDrafts.isEmpty)
    }

    func testTerminalPromptOmitsSessionLabel() {
        var prompts: [FunctionCardPrompt] = []
        let store = AgentorStore(dependencies: AgentorFeatureDependencies(
            publishPrompt: { prompts.append($0) },
            revokePrompt: { _ in },
            setEditingText: { _ in }
        ))
        let key = AgentorSessionKey(agent: .claude, sessionID: "session")

        store.receive(AgentorEvent(
            eventID: "start",
            occurredAt: Date(timeIntervalSince1970: 1),
            session: key,
            workingDirectoryName: "Peeker",
            name: .turnStarted
        ))
        store.receive(AgentorEvent(
            eventID: "end",
            occurredAt: Date(timeIntervalSince1970: 2),
            session: key,
            name: .turnEnded,
            outcome: .normal
        ))

        let context = AppLanguageContext.shared
        let previous = context.selection
        defer { context.selection = previous }
        context.selection = .english
        XCTAssertEqual(prompts.last?.message?.resolve(), "Completed · Claude Code")
        context.selection = .japanese
        XCTAssertEqual(prompts.last?.message?.resolve(), "完了 · Claude Code")
        context.selection = .simplifiedChinese
        XCTAssertEqual(prompts.last?.message?.resolve(), "已完成 · Claude Code")
        XCTAssertFalse(prompts.last?.summary.contains("Peeker") ?? true)
    }
}
