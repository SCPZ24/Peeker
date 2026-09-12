import AgentorFeature
import AgentorProtocol
import FeatureRuntimeKit
import Foundation
import FunctionCardKit
import PeekerCore
import PersistenceCore

@MainActor
public struct AgentorModule: FunctionCardModule {
    public init() {}

    public var id: FeatureID { .agentor }
    public var databaseMigrations: [AppDatabaseMigration] { [] }

    public func makeRegistration(context: FunctionCardModuleContext) -> FunctionCardRegistration {
        makeRuntimeRegistration(context: context).card
    }

    public func makeRuntimeRegistration(context: FunctionCardModuleContext) -> FunctionCardRuntimeRegistration {
        let integrationManager = AgentorIntegrationManager()
        let bridge = AgentorRuntimeBridge()
        let store = AgentorStore(dependencies: AgentorFeatureDependencies(
            publishPrompt: context.hostActions.publishPrompt,
            revokePrompt: context.hostActions.revokePrompt,
            setEditingText: context.hostActions.setEditingText,
            scanIntegrations: { await integrationManager.scan() },
            performIntegration: { agent, action in
                do { try await integrationManager.perform(agent, action: action) }
                catch let error as AgentorIntegrationError { throw AgentorIntegrationFailure(message: error.localizedMessage) }
            },
            focusOrigin: { key in await bridge.focus(key) }
        ))
        let runtime = AgentorRuntimeController(store: store)
        bridge.runtime = runtime
        return FunctionCardRuntimeRegistration(
            card: AgentorFeatureFactory.make(store: store),
            enablementChanged: { enabled in runtime.setEnabled(enabled) }
        )
    }
}

private final class AgentorRuntimeBridge: @unchecked Sendable {
    @MainActor weak var runtime: AgentorRuntimeController?

    @MainActor
    func focus(_ key: AgentorSessionKey) -> Bool {
        runtime?.focusOrigin(key) ?? false
    }
}
