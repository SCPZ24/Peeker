import Foundation
import FunctionCardKit
import MacPlatform
import PeekerCore
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

    public init(
        setPopoverPresented: @escaping @MainActor @Sendable (Bool) -> Void,
        setDragging: @escaping @MainActor @Sendable (Bool) -> Void,
        setEditingText: @escaping @MainActor @Sendable (Bool) -> Void
    ) {
        self.setPopoverPresented = setPopoverPresented
        self.setDragging = setDragging
        self.setEditingText = setEditingText
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
            setEditingText: { [self] in coordinator?.setEditingText($0) }
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
    public let audio: any AudioNotifying
    public let preferences: FeaturePreferenceStore
    public let hostActions: FunctionCardHostActions

    public init(
        persistence: Result<AppDatabase, StartupPersistenceError>,
        clock: any Clock,
        resolver: BusinessDayResolver,
        eventHub: TemporalEventHub,
        audio: any AudioNotifying,
        preferences: FeaturePreferenceStore,
        hostActions: FunctionCardHostActions
    ) {
        self.persistence = persistence
        self.clock = clock
        self.resolver = resolver
        self.eventHub = eventHub
        self.audio = audio
        self.preferences = preferences
        self.hostActions = hostActions
    }
}

@MainActor
public protocol FunctionCardModule {
    var id: FeatureID { get }
    var databaseMigrations: [AppDatabaseMigration] { get }
    func makeRegistration(context: FunctionCardModuleContext) -> FunctionCardRegistration
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

    public func makeRegistrations(
        context: FunctionCardModuleContext
    ) -> [FunctionCardRegistration] {
        modules.map { $0.makeRegistration(context: context) }
    }
}
