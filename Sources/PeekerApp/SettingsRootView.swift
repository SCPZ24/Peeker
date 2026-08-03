import AppKit
import SwiftUI
import PeekerCore
import FunctionCardKit

private enum SettingsPage: String, CaseIterable, Identifiable {
    case general = "通用"
    case cards = "功能卡"
    case timer = "Timer"
    case pusher = "Pusher"
    case about = "关于"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .cards: "square.grid.2x2"
        case .timer: "timer"
        case .pusher: "rectangle.3.group"
        case .about: "info.circle"
        }
    }
}

struct SettingsRootView: View {
    let runtime: AppRuntime
    @State private var selection: SettingsPage? = .general

    var body: some View {
        NavigationSplitView {
            List(SettingsPage.allCases, selection: $selection) { page in
                Label(page.rawValue, systemImage: page.systemImage).tag(page)
            }
            .listStyle(.sidebar)
            .navigationTitle("Peeker 设置")
        } detail: {
            settingsPage
                .navigationTitle(selection?.rawValue ?? "Peeker")
                .frame(minWidth: 560, minHeight: 420)
        }
        .frame(width: 760, height: 520)
        .background {
            SettingsWindowAccessor { window in
                runtime.registerSettingsWindow(window)
            }
        }
        .task { await runtime.settingsStore.load() }
    }

    @ViewBuilder
    private var settingsPage: some View {
        switch selection ?? .general {
        case .general:
            GeneralSettingsView(store: runtime.settingsStore)
        case .cards:
            CardSettingsView(registry: runtime.registry)
        case .timer:
            runtime.registry.registrations.first(where: { $0.id == .timer })?.makeSettingsView()
        case .pusher:
            runtime.registry.registrations.first(where: { $0.id == .pusher })?.makeSettingsView()
        case .about:
            AboutSettingsView(store: runtime.settingsStore)
        }
    }
}

private struct SettingsWindowAccessor: NSViewRepresentable {
    let onWindowAvailable: @MainActor (NSWindow) -> Void

    func makeNSView(context: Context) -> WindowReportingView {
        WindowReportingView(onWindowAvailable: onWindowAvailable)
    }

    func updateNSView(_ nsView: WindowReportingView, context: Context) {
        nsView.onWindowAvailable = onWindowAvailable
    }
}

private final class WindowReportingView: NSView {
    var onWindowAvailable: @MainActor (NSWindow) -> Void

    init(onWindowAvailable: @escaping @MainActor (NSWindow) -> Void) {
        self.onWindowAvailable = onWindowAvailable
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window else { return }
            self.onWindowAvailable(window)
        }
    }
}

private struct GeneralSettingsView: View {
    @Bindable var store: SettingsStore

    var body: some View {
        Form {
            Section("显示器") {
                Picker("灵动岛所在屏幕", selection: screenBinding) {
                    ForEach(store.availableScreens) { screen in
                        Text(screen.isBuiltIn ? "\(screen.name)（内建）" : screen.name)
                            .tag(Optional(screen.id))
                    }
                }
            }
            Section("启动") {
                Toggle("登录时启动", isOn: launchBinding)
                if store.launchStatus == .requiresApproval {
                    Text("需要在“系统设置 → 通用 → 登录项”中批准 Peeker。")
                        .font(.caption).foregroundStyle(.orange)
                }
                if let error = store.launchError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var screenBinding: Binding<String?> {
        Binding(get: { store.selectedScreenID }, set: { store.selectScreen($0) })
    }

    private var launchBinding: Binding<Bool> {
        Binding(
            get: { store.launchStatus == .enabled },
            set: { value in Task { await store.setLaunchAtLogin(value) } }
        )
    }
}

private struct CardSettingsView: View {
    @Bindable var registry: CardRegistry
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("启用与排序") {
                List {
                    ForEach(registry.enabledCards) { card in
                        CardSettingsRow(
                            name: card.name,
                            systemImage: card.systemImage,
                            isEnabled: enabledBinding(card.id)
                        )
                    }
                    .onMove(perform: registry.moveEnabled)

                    ForEach(registry.registrations.filter { !registry.enabledIDs.contains($0.id) }) { card in
                        CardSettingsRow(
                            name: card.name,
                            systemImage: card.systemImage,
                            isEnabled: enabledBinding(card.id)
                        )
                    }
                }
                .frame(minHeight: 220)
                if let errorMessage {
                    Text(errorMessage).font(.caption).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func enabledBinding(_ id: FeatureID) -> Binding<Bool> {
        Binding {
            registry.enabledIDs.contains(id)
        } set: { enabled in
            do {
                try registry.setEnabled(id, enabled: enabled)
                errorMessage = nil
            } catch {
                errorMessage = "至少需要启用一张功能卡。"
            }
        }
    }
}

private struct CardSettingsRow: View {
    let name: String
    let systemImage: String
    @Binding var isEnabled: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .frame(width: 18, alignment: .center)
                .accessibilityHidden(true)
            Text(name)
            Spacer()
            Toggle("启用", isOn: $isEnabled)
                .labelsHidden()
                .accessibilityLabel("\(name) 启用")
        }
    }
}

private struct AboutSettingsView: View {
    @Bindable var store: SettingsStore

    var body: some View {
        Form {
            Section("Peeker") {
                LabeledContent("版本", value: version)
                if let startupError = store.startupError {
                    Label(startupError, systemImage: "externaldrive.badge.exclamationmark")
                        .foregroundStyle(.red)
                }
                Button("检查更新") { Task { await store.checkForUpdates() } }
                    .disabled(store.updateState == .checking)
                updateStatus
            }
            Section {
                Button("退出 Peeker", role: .destructive) { NSApp.terminate(nil) }
            }
        }
        .formStyle(.grouped)
    }

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    @ViewBuilder
    private var updateStatus: some View {
        switch store.updateState {
        case .idle:
            EmptyView()
        case .checking:
            ProgressView("正在检查 GitHub Releases…")
        case let .current(message):
            Label(message, systemImage: "checkmark.circle").foregroundStyle(.green)
        case let .available(release):
            VStack(alignment: .leading, spacing: 8) {
                Text("发现新版本 \(release.version)").font(.headline)
                if !release.notes.isEmpty { Text(release.notes).lineLimit(5) }
                Text("brew upgrade --cask peeker").font(.system(.body, design: .monospaced)).textSelection(.enabled)
                Link("打开发布页面", destination: release.pageURL)
            }
        case let .failed(message):
            Text(message).foregroundStyle(.red)
        }
    }
}
