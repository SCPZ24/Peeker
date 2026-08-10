import Foundation
import FeatureRuntimeKit
import FunctionCardKit
import MacPlatform
import PeekerCore
import PersistenceCore
import PusherFeature
import PusherGRDBAdapter

@MainActor
public struct PusherModule: FunctionCardModule {
    public init() {}

    public var id: FeatureID { .pusher }
    public var databaseMigrations: [AppDatabaseMigration] { PusherDatabaseMigrations.all }

    public func makeRegistration(
        context: FunctionCardModuleContext
    ) -> FunctionCardRegistration {
        let repository: any PusherRepository
        switch context.persistence {
        case let .success(database):
            repository = PusherGRDBRepository(database: database)
        case let .failure(error):
            repository = UnavailablePusherRepository(error: error)
        }

        let preferences = PusherModulePreferences(store: context.preferences)
        return PusherFeatureFactory.make(
            dependencies: PusherFeatureDependencies(
                repository: repository,
                clock: context.clock,
                resolver: context.resolver,
                eventHub: context.eventHub,
                carryIncomplete: preferences.carryIncomplete,
                refreshTime: preferences.refreshTime,
                setPopoverPresented: context.hostActions.setPopoverPresented,
                setDragging: context.hostActions.setDragging,
                setEditingText: context.hostActions.setEditingText,
                onRefreshTimeChanged: { preferences.saveRefreshTime($0) },
                onCarryIncompleteChanged: { preferences.carryIncomplete = $0 }
            )
        )
    }
}

@MainActor
final class PusherModulePreferences {
    private enum Key {
        static let refreshHour = "pusherRefreshHour"
        static let refreshMinute = "pusherRefreshMinute"
        static let carryIncomplete = "pusherCarryIncomplete"
    }

    private let store: FeaturePreferenceStore

    init(store: FeaturePreferenceStore) {
        self.store = store
        store.register(defaults: [
            Key.refreshHour: 0,
            Key.refreshMinute: 0,
            Key.carryIncomplete: true,
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

    var carryIncomplete: Bool {
        get { store.bool(forKey: Key.carryIncomplete) }
        set { store.set(newValue, forKey: Key.carryIncomplete) }
    }
}

private final class UnavailablePusherRepository: PusherRepository, Sendable {
    private let error: StartupPersistenceError

    init(error: StartupPersistenceError) {
        self.error = error
    }

    func loadOrBootstrapCurrentBoard(resolvedToday: BusinessDay) async throws -> PusherBoard { throw error }
    func advanceDay(_ settlement: PusherSettlement) async throws -> PusherBoard { throw error }
    func updateCurrentBusinessDay(_ day: BusinessDay) async throws { throw error }
    func loadOrCreateDay(_ day: BusinessDay) async throws -> PusherBoard { throw error }
    func saveBoard(_ board: PusherBoard) async throws { throw error }
    func insertTask(_ task: PusherTask, at index: Int) async throws { throw error }
    func updateTask(_ task: PusherTask) async throws { throw error }
    func deleteTask(id: UUID) async throws { throw error }
    func reorderTasks(businessDayID: BusinessDayID, orderedTasks: [PusherTask]) async throws { throw error }
    func loadSnapshots(from startMilliseconds: Int64, to endMilliseconds: Int64) async throws -> [PusherDailySnapshot] { throw error }
}
