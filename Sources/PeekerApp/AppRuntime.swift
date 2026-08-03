import AppKit
import SwiftUI
import PeekerCore
import FunctionCardKit
import TimerFeature
import PusherFeature
import PersistenceCore
import TimerGRDBAdapter
import PusherGRDBAdapter
import MacPlatform

@MainActor
final class AppRuntime {
    static let shared = AppRuntime()

    let preferences: AppPreferences
    let screens: ScreenTopologyService
    let launchAtLogin: LaunchAtLoginManager
    let updateChecker: GitHubReleaseChecker
    let registry: CardRegistry
    let islandCoordinator: IslandCoordinator
    let settingsStore: SettingsStore
    private(set) var panelController: IslandPanelController!
    private let eventHub: TemporalEventHub

    private init() {
        preferences = AppPreferences()
        screens = ScreenTopologyService()
        launchAtLogin = LaunchAtLoginManager()
        updateChecker = GitHubReleaseChecker()

        let timerRepository: any TimerRepository
        let pusherRepository: any PusherRepository
        let startupError: String?
        do {
            let database = try AppDatabase(path: AppDatabase.defaultURL().path)
            timerRepository = TimerGRDBRepository(database: database)
            pusherRepository = PusherGRDBRepository(database: database)
            startupError = nil
        } catch {
            let message = "无法打开 Peeker.sqlite：\(error.localizedDescription)。原数据库未被修改，请检查文件权限或迁移错误后重试。"
            let unavailable = StartupPersistenceError(message: message)
            timerRepository = UnavailableTimerRepository(error: unavailable)
            pusherRepository = UnavailablePusherRepository(error: unavailable)
            startupError = message
        }

        let clock = SystemClock()
        let scheduler = DispatchTemporalScheduler()
        eventHub = TemporalEventHub(clock: clock, scheduler: scheduler)
        let resolver = BusinessDayResolver()
        let coordinatorBox = WeakCoordinatorBox()

        do {
            let timerCard = try TimerFeatureFactory.make(
                dependencies: TimerFeatureDependencies(
                    repository: timerRepository,
                    clock: clock,
                    resolver: resolver,
                    eventHub: eventHub,
                    audio: SystemAudioNotifier(),
                    refreshTime: preferences.timerRefreshTime,
                    statisticsMode: TimerStatisticsMode(rawValue: preferences.timerStatisticsModeRawValue) ?? .progress,
                    onRefreshTimeChanged: { [preferences] value in
                        preferences.saveTimerRefreshTime(value)
                    },
                    onStatisticsModeChanged: { [preferences] value in
                        preferences.timerStatisticsModeRawValue = value.rawValue
                    }
                )
            )
            let pusherCard = try PusherFeatureFactory.make(
                dependencies: PusherFeatureDependencies(
                    repository: pusherRepository,
                    clock: clock,
                    resolver: resolver,
                    eventHub: eventHub,
                    carryIncomplete: preferences.pusherCarryIncomplete,
                    refreshTime: preferences.pusherRefreshTime,
                    setPopoverPresented: { coordinatorBox.value?.setPopoverPresented($0) },
                    setDragging: { coordinatorBox.value?.setDragging($0) },
                    setEditingText: { coordinatorBox.value?.setEditingText($0) },
                    onRefreshTimeChanged: { [preferences] value in
                        preferences.savePusherRefreshTime(value)
                    },
                    onCarryIncompleteChanged: { [preferences] value in
                        preferences.pusherCarryIncomplete = value
                    }
                )
            )

            let cards = [timerCard, pusherCard]
            let configuredEnabled = Set(preferences.enabledCardIDs)
            let orderedEnabled = preferences.cardOrder.filter(configuredEnabled.contains)
            registry = CardRegistry(
                registrations: cards,
                enabledIDs: orderedEnabled,
                recentID: preferences.recentCardID,
                onChange: { [preferences] enabled, recent in
                    preferences.saveCards(enabled: enabled, recent: recent)
                }
            )
            islandCoordinator = IslandCoordinator(registry: registry)
            coordinatorBox.value = islandCoordinator
            settingsStore = SettingsStore(
                preferences: preferences,
                screens: screens,
                launchAtLogin: launchAtLogin,
                updateChecker: updateChecker,
                startupError: startupError
            )

            let rootView = AnyView(
                IslandRootView(coordinator: islandCoordinator) {
                    AppRuntime.shared.openSettings()
                }
            )
            panelController = IslandPanelController(
                coordinator: islandCoordinator,
                rootView: rootView,
                screens: screens,
                targetScreenID: preferences.targetScreenID,
                didFallbackScreen: { [preferences] id in
                    preferences.targetScreenID = id
                }
            )
            settingsStore.didSelectScreen = { [weak panelController] id in
                panelController?.setTargetScreenID(id)
            }
        } catch {
            preconditionFailure("Built-in feature factories must remain non-failing: \(error)")
        }
    }

    func start() {
        panelController.show()
        Task {
            await settingsStore.load()
            if !preferences.hasAttemptedDefaultLaunchRegistration {
                preferences.hasAttemptedDefaultLaunchRegistration = true
                try? await launchAtLogin.setEnabled(true)
                await settingsStore.refreshLaunchStatus()
            }
        }
    }

    func handleWake() {
        Task { await eventHub.wake() }
    }

    func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor
private final class WeakCoordinatorBox {
    weak var value: IslandCoordinator?
}
