import Foundation
import FeatureRuntimeKit
import FunctionCardKit
import MacPlatform
import PeekerCore
import PersistenceCore
import TimerFeature
import TimerGRDBAdapter

@MainActor
public struct TimerModule: FunctionCardModule {
    public init() {}

    public var id: FeatureID { .timer }
    public var databaseMigrations: [AppDatabaseMigration] { TimerDatabaseMigrations.all }

    public func makeRegistration(
        context: FunctionCardModuleContext
    ) -> FunctionCardRegistration {
        makeRuntimeRegistration(context: context).card
    }

    public func makeRuntimeRegistration(
        context: FunctionCardModuleContext
    ) -> FunctionCardRuntimeRegistration {
        let repository: any TimerRepository
        switch context.persistence {
        case let .success(database):
            repository = TimerGRDBRepository(database: database)
        case let .failure(error):
            repository = UnavailableTimerRepository(error: error)
        }

        let preferences = TimerModulePreferences(store: context.preferences)
        let layoutState = FunctionCardLayoutState(currentExpandedSize: CGSize(
            width: 800,
            height: preferences.temporaryTasksEnabled ? 520 * 5 / 7 : 460 * 5 / 7
        ))
        let dependencies = TimerFeatureDependencies(
                repository: repository,
                clock: context.clock,
                resolver: context.resolver,
                eventHub: context.eventHub,
                publishPrompt: context.hostActions.publishPrompt,
                refreshTime: preferences.refreshTime,
                statisticsMode: TimerStatisticsMode(
                    rawValue: preferences.statisticsModeRawValue
                ) ?? .progress,
            temporaryTasksEnabled: preferences.temporaryTasksEnabled,
            layoutState: layoutState,
            setPopoverPresented: context.hostActions.setPopoverPresented,
            setEditingText: context.hostActions.setEditingText,
            onRefreshTimeChanged: { preferences.saveRefreshTime($0) },
            onStatisticsModeChanged: { preferences.statisticsModeRawValue = $0.rawValue },
            onTemporaryTasksEnabledChanged: { enabled in
                preferences.temporaryTasksEnabled = enabled
                layoutState.currentExpandedSize = CGSize(
                    width: 800,
                    height: enabled ? 520 * 5 / 7 : 460 * 5 / 7
                )
            }
        )
        let store = TimerFeatureFactory.makeStore(dependencies: dependencies)
        let enabledState = ModuleEnablementState()
        return FunctionCardRuntimeRegistration(
            card: TimerFeatureFactory.makeRegistration(store: store, dependencies: dependencies),
            handleCommand: { invocation in
                await TimerCommandHandler(
                    store: store,
                    enabledState: enabledState,
                    setEnabled: { try context.hostActions.setCardEnabled(.timer, $0) }
                ).handle(invocation.arguments)
            },
            enablementChanged: { enabled in enabledState.enabled = enabled },
            temporalContextChanged: { await store.handleTemporalEvent(reason: .clockOrTimeZoneRecovery) }
        )
    }
}

@MainActor
final class TimerModulePreferences {
    private enum Key {
        static let refreshHour = "timerRefreshHour"
        static let refreshMinute = "timerRefreshMinute"
        static let statisticsMode = "timerStatisticsMode"
        static let temporaryTasksEnabled = "timerTemporaryTasksEnabled"
    }

    private let store: FeaturePreferenceStore

    init(store: FeaturePreferenceStore) {
        self.store = store
        store.register(defaults: [
            Key.refreshHour: 0,
            Key.refreshMinute: 0,
            Key.statisticsMode: "progress",
            Key.temporaryTasksEnabled: false,
        ])
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

    var statisticsModeRawValue: String {
        get { store.string(forKey: Key.statisticsMode) ?? "progress" }
        set { store.set(newValue, forKey: Key.statisticsMode) }
    }

    var temporaryTasksEnabled: Bool {
        get { store.bool(forKey: Key.temporaryTasksEnabled) }
        set { store.set(newValue, forKey: Key.temporaryTasksEnabled) }
    }
}

private final class UnavailableTimerRepository: TimerRepository, Sendable {
    private let error: StartupPersistenceError

    init(error: StartupPersistenceError) {
        self.error = error
    }

    func loadOrBootstrapCurrentDay(resolvedToday: BusinessDay) async throws -> TimerDayState { throw error }
    func advanceDay(_ transition: TimerDayTransition) async throws -> TimerDayState { throw error }
    func updateCurrentBusinessDay(_ day: BusinessDay) async throws { throw error }
    func loadTemplates() async throws -> [TimerTemplate] { throw error }
    func saveTemplate(_ template: TimerTemplate) async throws { throw error }
    func deleteTemplate(id: UUID) async throws { throw error }
    func loadOrCreateDay(_ day: BusinessDay) async throws -> TimerDayState { throw error }
    func saveDay(_ state: TimerDayState) async throws { throw error }
    func beginSession(_ session: TimerSession) async throws { throw error }
    func commitStart(state: TimerDayState, session: TimerSession) async throws { throw error }
    func completeSession(_ completion: TimerSessionCompletion) async throws { throw error }
    func interruptSession(_ interruption: TimerSessionInterruption) async throws { throw error }
    func commitCompletion(state: TimerDayState, completion: TimerSessionCompletion) async throws { throw error }
    func loadSnapshots(from startMilliseconds: Int64, to endMilliseconds: Int64) async throws -> [TimerDailySnapshot] { throw error }
}
