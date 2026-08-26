import AgentorFeature
import AgentorProtocol
import FeatureRuntimeKit
import FunctionCardKit
import MacPlatform
import PeekerCore
import PeekerProtocol
import PersistenceCore
import XCTest
@testable import AgentorModule

@MainActor
final class AgentorModuleTests: XCTestCase {
    func testModuleRegistersFourthDefaultCardWithoutDatabaseMigrationOrCommand() async {
        let module = AgentorModule()
        let context = FunctionCardModuleContext(
            persistence: .failure(StartupPersistenceError(message: "unused")),
            clock: SystemClock(),
            resolver: BusinessDayResolver(),
            eventHub: TemporalEventHub(clock: SystemClock(), scheduler: DispatchTemporalScheduler()),
            preferences: FeaturePreferenceStore(defaults: UserDefaults(suiteName: UUID().uuidString)!),
            hostActions: FunctionCardHostActions(
                setPopoverPresented: { _ in }, setDragging: { _ in }, setEditingText: { _ in }
            )
        )
        let registration = module.makeRuntimeRegistration(context: context)

        XCTAssertEqual(module.id, .agentor)
        XCTAssertTrue(module.databaseMigrations.isEmpty)
        XCTAssertEqual(registration.card.defaultOrder, 3)
        XCTAssertEqual(registration.card.introducedConfigurationVersion, 3)
        XCTAssertTrue(registration.card.defaultEnabled)
        let response = await registration.handleCommand(CommandInvocation(featureID: "agentor", arguments: [], category: .read))
        XCTAssertFalse(response.ok)
    }

    func testSessionProcessExitRemovesSessionWithoutCrashing() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let socketURL = directory.appendingPathComponent("agentor.sock")
        let store = AgentorStore(dependencies: AgentorFeatureDependencies(
            publishPrompt: { _ in }, revokePrompt: { _ in }, setEditingText: { _ in }
        ))
        let runtime = AgentorRuntimeController(store: store, socketURL: socketURL)
        runtime.setEnabled(true)
        defer {
            runtime.setEnabled(false)
            try? FileManager.default.removeItem(at: directory)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["0.2"]
        try process.run()
        let pid = process.processIdentifier
        guard let processInfo = AgentorProcessInspector.processInfo(pid) else {
            XCTFail("Expected process metadata")
            return
        }
        let key = AgentorSessionKey(agent: .claude, sessionID: "process-exit")
        let request = AgentorRequest(event: AgentorEvent(
            eventID: "start",
            session: key,
            process: AgentorProcessIdentity(pid: pid, startedAt: processInfo.startedAt, scope: .session),
            name: .turnStarted
        ))

        let response = try await Task.detached {
            try AgentorIPCClient(socketURL: socketURL).request(request, timeout: 2)
        }.value
        XCTAssertEqual(response, .ack)
        XCTAssertNotNil(store.reducer.sessions[key])

        while process.isRunning { try await Task.sleep(for: .milliseconds(20)) }
        for _ in 0..<50 where store.reducer.sessions[key] != nil {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertNil(store.reducer.sessions[key])
    }
}
