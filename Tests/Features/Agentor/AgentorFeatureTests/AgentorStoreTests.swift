import AgentorProtocol
import FunctionCardKit
import XCTest
@testable import AgentorFeature

@MainActor
final class AgentorStoreTests: XCTestCase {
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

        XCTAssertEqual(prompts.last?.summary, "已完成 · Claude Code")
        XCTAssertFalse(prompts.last?.summary.contains("Peeker") ?? true)
    }
}
