import AppKit
import Foundation
import Observation
import PeekerCore
import MacPlatform

@MainActor
@Observable
final class SettingsStore {
    var availableScreens: [ScreenDescriptor] = []
    var selectedScreenID: String?
    var launchStatus: LaunchAtLoginStatus = .disabled
    var launchError: String?
    var updateState: UpdateState = .idle
    let startupError: String?
    var didSelectScreen: ((String?) -> Void)?

    private let preferences: AppPreferences
    private let screens: ScreenTopologyService
    private let launchAtLogin: LaunchAtLoginManager
    private let updateChecker: GitHubReleaseChecker

    init(
        preferences: AppPreferences,
        screens: ScreenTopologyService,
        launchAtLogin: LaunchAtLoginManager,
        updateChecker: GitHubReleaseChecker,
        startupError: String?
    ) {
        self.preferences = preferences
        self.screens = screens
        self.launchAtLogin = launchAtLogin
        self.updateChecker = updateChecker
        self.startupError = startupError
        selectedScreenID = preferences.targetScreenID
    }

    func load() async {
        availableScreens = await screens.availableScreens()
        if selectedScreenID == nil {
            if let builtIn = availableScreens.first(where: \.isBuiltIn)?.id {
                selectedScreenID = builtIn
            } else {
                selectedScreenID = await screens.currentMainScreenID()
            }
            preferences.targetScreenID = selectedScreenID
            didSelectScreen?(selectedScreenID)
        }
        await refreshLaunchStatus()
    }

    func selectScreen(_ id: String?) {
        selectedScreenID = id
        preferences.targetScreenID = id
        didSelectScreen?(id)
    }

    func refreshLaunchStatus() async {
        launchStatus = await launchAtLogin.status()
    }

    func setLaunchAtLogin(_ enabled: Bool) async {
        do {
            try await launchAtLogin.setEnabled(enabled)
            launchError = nil
        } catch {
            launchError = error.localizedDescription
        }
        await refreshLaunchStatus()
    }

    func checkForUpdates() async {
        updateState = .checking
        do {
            guard let release = try await updateChecker.latestRelease() else {
                updateState = .current("没有可用的公开版本。")
                return
            }
            let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.2"
            if let localVersion = SemanticVersion(current),
               let remoteVersion = SemanticVersion(release.version),
               localVersion < remoteVersion {
                updateState = .available(release)
            } else {
                updateState = .current("当前版本 \(current) 已是最新版。")
            }
        } catch {
            updateState = .failed("检查更新失败：\(error.localizedDescription)")
        }
    }

    enum UpdateState: Equatable {
        case idle
        case checking
        case current(String)
        case available(AppRelease)
        case failed(String)
    }
}
