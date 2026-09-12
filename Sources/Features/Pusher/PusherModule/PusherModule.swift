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
        makeRuntimeRegistration(context: context).card
    }

    public func makeRuntimeRegistration(
        context: FunctionCardModuleContext
    ) -> FunctionCardRuntimeRegistration {
        let repository: any PusherRepository
        switch context.persistence {
        case let .success(database):
            repository = PusherGRDBRepository(database: database)
        case let .failure(error):
            repository = UnavailablePusherRepository(error: error)
        }

        let preferences = PusherModulePreferences(store: context.preferences)
        let dependencies = PusherFeatureDependencies(
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
            onCarryIncompleteChanged: { preferences.carryIncomplete = $0 },
            onMutationEvent: { event in
                let message: LocalizedMessage
                let style: FunctionCardPromptStyle
                switch event {
                case let .created(task):
                    style = .standard; message = L10n.message("已新建：%1$@", task.title)
                case let .deleted(task):
                    style = .standard; message = L10n.message("已删除：%1$@", task.title)
                case let .moved(task, from, to):
                    style = to == .done && from != .done ? .success : .standard
                    message = L10n.message(style == .success ? "已完成：%1$@" : "已移动：%1$@", task.title)
                }
                context.hostActions.publishPrompt(FunctionCardPrompt(
                    token: UUID().uuidString,
                    sourceID: .pusher,
                    systemImage: "rectangle.3.group.fill",
                    moduleName: "Pusher",
                    summary: message.resolve(),
                    message: message,
                    style: style
                ))
            }
        )
        let store = PusherFeatureFactory.makeStore(dependencies: dependencies)
        let enabledState = PusherEnablementState()
        return FunctionCardRuntimeRegistration(
            card: PusherFeatureFactory.makeRegistration(store: store, dependencies: dependencies),
            handleCommand: { invocation in
                await PusherCommandHandler(
                    store: store,
                    enabledState: enabledState,
                    setEnabled: { try context.hostActions.setCardEnabled(.pusher, $0) }
                ).handle(invocation.arguments)
            },
            enablementChanged: { enabled in enabledState.enabled = enabled },
            temporalContextChanged: { await store.handleWake() }
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
