import Foundation
import FunctionCardKit
import MacPlatform
import PeekerCore
import PeekerProtocol
import PersistenceCore

public struct StartupPersistenceError: LocalizedError, Sendable, Equatable {
    public let message: String

    public init(message: String) {
        self.message = message
    }

    public var errorDescription: String? { message }
}

@MainActor
public struct FunctionCardHostActions {
    public let setPopoverPresented: @MainActor @Sendable (Bool) -> Void
    public let setDragging: @MainActor @Sendable (Bool) -> Void
    public let setEditingText: @MainActor @Sendable (Bool) -> Void
    public let publishPrompt: @MainActor @Sendable (FunctionCardPrompt) -> Void
    public let revokePrompt: @MainActor @Sendable (String) -> Void
    public let setCardEnabled: @MainActor @Sendable (FeatureID, Bool) throws -> Void

    public init(
        setPopoverPresented: @escaping @MainActor @Sendable (Bool) -> Void,
        setDragging: @escaping @MainActor @Sendable (Bool) -> Void,
        setEditingText: @escaping @MainActor @Sendable (Bool) -> Void,
        publishPrompt: @escaping @MainActor @Sendable (FunctionCardPrompt) -> Void = { _ in },
        revokePrompt: @escaping @MainActor @Sendable (String) -> Void = { _ in },
        setCardEnabled: @escaping @MainActor @Sendable (FeatureID, Bool) throws -> Void = { _, _ in }
    ) {
        self.setPopoverPresented = setPopoverPresented
        self.setDragging = setDragging
        self.setEditingText = setEditingText
        self.publishPrompt = publishPrompt
        self.revokePrompt = revokePrompt
        self.setCardEnabled = setCardEnabled
    }
}

@MainActor
public final class FunctionCardHostActionsBridge {
    private weak var coordinator: IslandCoordinator?

    public init() {}

    public var actions: FunctionCardHostActions {
        FunctionCardHostActions(
            setPopoverPresented: { [self] in coordinator?.setPopoverPresented($0) },
            setDragging: { [self] in coordinator?.setDragging($0) },
            setEditingText: { [self] in coordinator?.setEditingText($0) },
            publishPrompt: { [self] in coordinator?.publishPrompt($0) },
            revokePrompt: { [self] in coordinator?.revokePrompt(token: $0) },
            setCardEnabled: { [self] id, enabled in
                guard let coordinator else { return }
                try coordinator.registry.setEnabled(id, enabled: enabled)
            }
        )
    }

    public func attach(to coordinator: IslandCoordinator) {
        self.coordinator = coordinator
    }
}

@MainActor
public struct FunctionCardModuleContext {
    public let persistence: Result<AppDatabase, StartupPersistenceError>
    public let clock: any Clock
    public let resolver: BusinessDayResolver
    public let eventHub: TemporalEventHub
    public let preferences: FeaturePreferenceStore
    public let hostActions: FunctionCardHostActions

    public init(
        persistence: Result<AppDatabase, StartupPersistenceError>,
        clock: any Clock,
        resolver: BusinessDayResolver,
        eventHub: TemporalEventHub,
        preferences: FeaturePreferenceStore,
        hostActions: FunctionCardHostActions
    ) {
        self.persistence = persistence
        self.clock = clock
        self.resolver = resolver
        self.eventHub = eventHub
        self.preferences = preferences
        self.hostActions = hostActions
    }
}

public typealias FunctionCardCommandHandler = @MainActor @Sendable (CommandInvocation) async -> PeekerEnvelope

@MainActor
public struct FunctionCardRuntimeRegistration {
    public let card: FunctionCardRegistration
    public let handleCommand: FunctionCardCommandHandler
    public let enablementChanged: @MainActor @Sendable (Bool) async -> Void
    public let temporalContextChanged: @MainActor @Sendable () async -> Void

    public init(
        card: FunctionCardRegistration,
        handleCommand: @escaping FunctionCardCommandHandler = { _ in
            .failure(PeekerError(code: "invalid_usage", message: "This feature does not expose commands"))
        },
        enablementChanged: @escaping @MainActor @Sendable (Bool) async -> Void = { _ in },
        temporalContextChanged: @escaping @MainActor @Sendable () async -> Void = {}
    ) {
        self.card = card
        self.handleCommand = handleCommand
        self.enablementChanged = enablementChanged
        self.temporalContextChanged = temporalContextChanged
    }
}

@MainActor
public protocol FunctionCardModule {
    var id: FeatureID { get }
    var databaseMigrations: [AppDatabaseMigration] { get }
    func makeRegistration(context: FunctionCardModuleContext) -> FunctionCardRegistration
    func makeRuntimeRegistration(context: FunctionCardModuleContext) -> FunctionCardRuntimeRegistration
}

public extension FunctionCardModule {
    func makeRuntimeRegistration(context: FunctionCardModuleContext) -> FunctionCardRuntimeRegistration {
        FunctionCardRuntimeRegistration(card: makeRegistration(context: context))
    }
}

public enum FunctionCardModuleCatalogError: Error, Equatable {
    case duplicateFeatureID(FeatureID)
    case duplicateMigrationID(String)
}

@MainActor
public struct FunctionCardModuleCatalog {
    private let modules: [any FunctionCardModule]
    public let databaseMigrations: [AppDatabaseMigration]

    public init(modules: [any FunctionCardModule]) throws {
        var featureIDs = Set<FeatureID>()
        var migrationIDs = Set<String>()
        var migrations: [AppDatabaseMigration] = []

        for module in modules {
            guard featureIDs.insert(module.id).inserted else {
                throw FunctionCardModuleCatalogError.duplicateFeatureID(module.id)
            }
            for migration in module.databaseMigrations {
                guard migrationIDs.insert(migration.id).inserted else {
                    throw FunctionCardModuleCatalogError.duplicateMigrationID(migration.id)
                }
                migrations.append(migration)
            }
        }

        self.modules = modules
        databaseMigrations = migrations
    }

    public func makeRuntimeRegistrations(
        context: FunctionCardModuleContext
    ) -> [FunctionCardRuntimeRegistration] {
        modules.map { $0.makeRuntimeRegistration(context: context) }
    }

    public func makeRegistrations(
        context: FunctionCardModuleContext
    ) -> [FunctionCardRegistration] {
        makeRuntimeRegistrations(context: context).map(\.card)
    }
}

@MainActor
public final class FunctionCardCommandRouter {
    private let handlers: [FeatureID: FunctionCardCommandHandler]

    public init(registrations: [FunctionCardRuntimeRegistration]) throws {
        var handlers: [FeatureID: FunctionCardCommandHandler] = [:]
        for registration in registrations {
            guard handlers[registration.card.id] == nil else {
                throw FunctionCardModuleCatalogError.duplicateFeatureID(registration.card.id)
            }
            handlers[registration.card.id] = registration.handleCommand
        }
        self.handlers = handlers
    }

    public func handle(_ invocation: CommandInvocation) async -> PeekerEnvelope {
        let id = FeatureID(rawValue: invocation.featureID)
        guard let handler = handlers[id] else {
            return .failure(PeekerError(
                code: "not_found",
                message: "Unknown feature: \(invocation.featureID)"
            ))
        }
        return await handler(invocation)
    }
}
