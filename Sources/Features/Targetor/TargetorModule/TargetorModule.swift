import Foundation
import FeatureRuntimeKit
import FunctionCardKit
import MacPlatform
import PeekerCore
import PersistenceCore
import TargetorFeature
import TargetorGRDBAdapter

@MainActor
public struct TargetorModule: FunctionCardModule {
    public init() {}

    public var id: FeatureID { .targetor }
    public var databaseMigrations: [AppDatabaseMigration] { TargetorDatabaseMigrations.all }

    public func makeRegistration(context: FunctionCardModuleContext) -> FunctionCardRegistration {
        makeRuntimeRegistration(context: context).card
    }

    public func makeRuntimeRegistration(context: FunctionCardModuleContext) -> FunctionCardRuntimeRegistration {
        let repository: any TargetorRepository
        switch context.persistence {
        case let .success(database): repository = TargetorGRDBRepository(database: database)
        case let .failure(error): repository = UnavailableTargetorRepository(error: error)
        }
        let preferences = TargetorModulePreferences(store: context.preferences)
        let manifest = try? FunctionCardIconManifest(
            featureID: .targetor,
            bundle: .main,
            resourceSubdirectory: "Targetor/Lucide"
        )
        let dependencies = TargetorFeatureDependencies(
            repository: repository,
            clock: context.clock,
            eventHub: context.eventHub,
            refreshTime: preferences.refreshTime,
            iconManifest: manifest,
            setDragging: context.hostActions.setDragging,
            onRefreshTimeChanged: { preferences.saveRefreshTime($0) },
            publishPrompt: { result in
                let period = result.target.currentPeriod
                context.hostActions.publishPrompt(FunctionCardPrompt(
                    token: result.event.id.uuidString,
                    sourceID: .targetor,
                    iconDescriptor: .bundleSVG(featureID: .targetor, manifestResourceName: "target"),
                    moduleName: "Targetor",
                    summary: result.target.target.title,
                    message: L10n.message("已打卡：%1$@ %2$@/%3$@", result.target.target.title, String(period?.count ?? 0), String(period?.maxCountSnapshot ?? result.target.target.maxCount)),
                    style: .success
                ))
            }
        )
        let store = TargetorFeatureFactory.makeStore(dependencies: dependencies)
        let enabledState = TargetorEnablementState()
        return FunctionCardRuntimeRegistration(
            card: TargetorFeatureFactory.makeRegistration(store: store, dependencies: dependencies),
            handleCommand: { invocation in
                await TargetorCommandHandler(
                    store: store,
                    enabledState: enabledState,
                    setEnabled: { try context.hostActions.setCardEnabled(.targetor, $0) },
                    isValidIcon: { manifest?.contains($0) == true }
                ).handle(invocation.arguments)
            },
            enablementChanged: { enabled in enabledState.enabled = enabled },
            temporalContextChanged: { await store.handleTemporalEvent() }
        )
    }
}

@MainActor
private final class TargetorModulePreferences {
    private enum Key {
        static let refreshHour = "targetorRefreshHour"
        static let refreshMinute = "targetorRefreshMinute"
    }
    private let store: FeaturePreferenceStore

    init(store: FeaturePreferenceStore) {
        self.store = store
        store.register(defaults: [Key.refreshHour: 0, Key.refreshMinute: 0])
    }

    var refreshTime: RefreshTime {
        (try? RefreshTime(
            hour: store.integer(forKey: Key.refreshHour),
            minute: store.integer(forKey: Key.refreshMinute)
        )) ?? .midnight
    }

    func saveRefreshTime(_ value: RefreshTime) {
        store.set(value.hour, forKey: Key.refreshHour)
        store.set(value.minute, forKey: Key.refreshMinute)
    }
}

private final class UnavailableTargetorRepository: TargetorRepository, Sendable {
    private let error: StartupPersistenceError
    init(error: StartupPersistenceError) { self.error = error }
    func recover(now: Date, refreshTime: RefreshTime, resolver: TargetorPeriodResolver) async throws { throw error }
    func snapshot(scope: TargetorArchiveScope) async throws -> TargetorSnapshot { throw error }
    func create(target: TargetorTarget, firstPeriod: TargetorPeriod) async throws { throw error }
    func update(target: TargetorTarget, replacingCurrentWith period: TargetorPeriod?, settleAtMilliseconds: Int64?) async throws { throw error }
    func archive(targetID: UUID, atMilliseconds: Int64) async throws -> TargetorTargetState { throw error }
    func reorder(activeTargetIDs: [UUID], atMilliseconds: Int64) async throws { throw error }
    func checkin(targetID: UUID, eventID: UUID, atMilliseconds: Int64) async throws -> TargetorCheckinResult { throw error }
    func uncheck(eventID: UUID) async throws -> TargetorTargetState { throw error }
    func history(targetID: UUID, fromMilliseconds: Int64?, toMilliseconds: Int64?) async throws -> TargetorHistory { throw error }
}
