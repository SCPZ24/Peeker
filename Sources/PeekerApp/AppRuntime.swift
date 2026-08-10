import AppKit
import SwiftUI
import PeekerCore
import FunctionCardKit
import PersistenceCore
import MacPlatform
import FeatureRuntimeKit

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
    private let settingsWindowPositioner = SettingsWindowPositioner()
    private lazy var settingsPresentationRouter = SettingsPresentationRouter(
        willOpen: {
            NSApp.activate(ignoringOtherApps: true)
        },
        didOpen: { [weak self] in
            DispatchQueue.main.async {
                self?.settingsWindowPositioner.repositionAndBringForward()
            }
        }
    )

    private init() {
        preferences = AppPreferences()
        screens = ScreenTopologyService()
        launchAtLogin = LaunchAtLoginManager()
        updateChecker = GitHubReleaseChecker()

        let catalog: FunctionCardModuleCatalog
        do {
            catalog = try FunctionCardModuleCatalog(modules: BuiltInFeatureModules.all)
        } catch {
            preconditionFailure("Built-in feature catalog is invalid: \(error)")
        }

        let persistence: Result<AppDatabase, StartupPersistenceError>
        let startupError: String?
        do {
            let database = try AppDatabase(
                path: AppDatabase.defaultURL().path,
                featureMigrations: catalog.databaseMigrations
            )
            persistence = .success(database)
            startupError = nil
        } catch {
            let message = "无法打开 Peeker.sqlite：\(error.localizedDescription)。Peeker 不会主动删除业务数据；请检查文件权限或迁移错误后重试。"
            persistence = .failure(StartupPersistenceError(message: message))
            startupError = message
        }

        let clock = SystemClock()
        let scheduler = DispatchTemporalScheduler()
        eventHub = TemporalEventHub(clock: clock, scheduler: scheduler)
        let hostActionsBridge = FunctionCardHostActionsBridge()
        let context = FunctionCardModuleContext(
            persistence: persistence,
            clock: clock,
            resolver: BusinessDayResolver(),
            eventHub: eventHub,
            audio: SystemAudioNotifier(),
            preferences: FeaturePreferenceStore(),
            hostActions: hostActionsBridge.actions
        )
        let cards = catalog.makeRegistrations(context: context)
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
        hostActionsBridge.attach(to: islandCoordinator)

        let islandDisplayContext = IslandDisplayContext()
        settingsStore = SettingsStore(
            preferences: preferences,
            screens: screens,
            launchAtLogin: launchAtLogin,
            updateChecker: updateChecker,
            startupError: startupError
        )

        let rootView = AnyView(
            IslandHostView(
                coordinator: islandCoordinator,
                displayContext: islandDisplayContext,
                settingsRouter: settingsPresentationRouter
            )
        )
        panelController = IslandPanelController(
            coordinator: islandCoordinator,
            displayContext: islandDisplayContext,
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

    func registerSettingsWindow(_ window: NSWindow) {
        settingsWindowPositioner.register(window)
    }

    func openSettings() {
        settingsPresentationRouter.requestOpen()
    }
}
