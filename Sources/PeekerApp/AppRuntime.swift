import AppKit
import SwiftUI
import PeekerCore
import PeekerIPC
import PeekerProtocol
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
    private(set) var ipcServer: PeekerIPCServer!
    private let eventHub: TemporalEventHub
    private let runtimeRegistrations: [FunctionCardRuntimeRegistration]
    private let commandRouter: FunctionCardCommandRouter
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
            preferences: FeaturePreferenceStore(),
            hostActions: hostActionsBridge.actions
        )
        runtimeRegistrations = catalog.makeRuntimeRegistrations(context: context)
        do {
            commandRouter = try FunctionCardCommandRouter(registrations: runtimeRegistrations)
        } catch {
            preconditionFailure("Built-in command router is invalid: \(error)")
        }
        let cards = runtimeRegistrations.map(\.card)
        let cardPreferences = preferences.upgradedCards(registrations: cards)
        let promptCenter = PromptCenter()
        registry = CardRegistry(
            registrations: cards,
            enabledIDs: cardPreferences.enabledIDs,
            recentID: cardPreferences.recentID,
            lastOpenedAt: cardPreferences.lastOpenedAt,
            onChange: { [preferences] enabled, recent in
                preferences.saveCards(enabled: enabled, recent: recent)
            },
            onEnablementChange: { [runtimeRegistrations, promptCenter] id, enabled in
                if !enabled { promptCenter.clear(sourceID: id) }
                if let runtime = runtimeRegistrations.first(where: { $0.card.id == id }) {
                    Task { await runtime.enablementChanged(enabled) }
                }
            },
            onOpened: { [preferences] id, date in
                preferences.markCardOpened(id, at: date)
            }
        )
        islandCoordinator = IslandCoordinator(
            registry: registry,
            promptCenter: promptCenter,
            hoverExpansionDelaySeconds: preferences.hoverExpansionDelaySeconds
        )
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
        settingsStore.didSetHoverExpansionDelay = { [weak islandCoordinator] seconds in
            islandCoordinator?.setHoverExpansionDelay(seconds)
        }
        ipcServer = PeekerIPCServer { request in
            await AppRuntime.shared.handleIPC(request)
        }
    }

    func start() {
        panelController.show()
        do {
            try ipcServer.start()
        } catch {
            settingsStore.reportRuntimeError("CLI 服务启动失败：\(error.localizedDescription)")
        }
        Task {
            for runtime in runtimeRegistrations {
                await runtime.enablementChanged(registry.enabledIDs.contains(runtime.card.id))
            }
            await settingsStore.load()
            if !preferences.hasAttemptedDefaultLaunchRegistration {
                preferences.hasAttemptedDefaultLaunchRegistration = true
                try? await launchAtLogin.setEnabled(true)
                await settingsStore.refreshLaunchStatus()
            }
        }
    }

    func handleSleep() {
        Task { await eventHub.sleep() }
    }

    func handleWake() {
        Task { await eventHub.wake() }
    }

    func handleClockOrTimeZoneChange() {
        Task {
            await eventHub.clockOrTimeZoneChanged()
            for runtime in runtimeRegistrations { await runtime.temporalContextChanged() }
        }
    }

    func stop() {
        ipcServer.stop()
    }

    private func handleIPC(_ request: IPCRequest) async -> PeekerEnvelope {
        switch request {
        case .handshake:
            return .failure(PeekerError(code: "invalid_usage", message: "Handshake already completed"))
        case .status:
            return .success(.object([
                "running": .bool(true),
                "appVersion": .string(PeekerContract.appVersion),
                "protocolVersion": .number(Double(PeekerContract.protocolVersion)),
                "pid": .number(Double(ProcessInfo.processInfo.processIdentifier)),
            ]))
        case let .command(invocation):
            return await commandRouter.handle(invocation)
        }
    }

    func registerSettingsWindow(_ window: NSWindow) {
        settingsWindowPositioner.register(window)
    }

    func openSettings() {
        settingsPresentationRouter.requestOpen()
    }
}
