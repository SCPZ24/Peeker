import AppKit
import SwiftUI
import PeekerCore
import PeekerProtocol
import FunctionCardKit

struct SettingsRootView: View {
    @Environment(\.colorScheme) private var systemColorScheme
    let runtime: AppRuntime
    @State private var selection: SettingsDestination? = .general

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(
                    SettingsNavigation.destinations(
                        registrations: runtime.registry.registrations
                    ),
                    id: \.self
                ) { destination in
                    HStack(spacing: 8) {
                        destinationIcon(destination)
                            .frame(width: 16, height: 16)
                        Text(title(for: destination))
                    }
                    .tag(destination)
                }
            }
            .listStyle(.sidebar)
            .navigationTitle(L10n.text("Peeker 设置"))
        } detail: {
            settingsPage
                .navigationTitle(title(for: resolvedSelection))
                .frame(minWidth: 560, minHeight: 420)
        }
        .environment(\.nativePresentationColorScheme, systemColorScheme)
        .environment(\.locale, runtime.language.locale)
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
        switch resolvedSelection {
        case .general:
            GeneralSettingsView(store: runtime.settingsStore)
        case .cards:
            CardSettingsView(registry: runtime.registry)
        case let .feature(id):
            runtime.registry.registrations.first(where: { $0.id == id })?.makeSettingsView()
        case .about:
            AboutSettingsView(store: runtime.settingsStore)
        }
    }

    private var resolvedSelection: SettingsDestination {
        SettingsNavigation.resolve(
            selection: selection ?? .general,
            registrations: runtime.registry.registrations
        )
    }

    private func title(for destination: SettingsDestination) -> String {
        switch destination {
        case .general: L10n.text("通用")
        case .cards: L10n.text("功能卡")
        case let .feature(id):
            runtime.registry.registrations.first(where: { $0.id == id })?.name ?? L10n.text("功能卡")
        case .about: L10n.text("关于")
        }
    }

    @ViewBuilder
    private func destinationIcon(_ destination: SettingsDestination) -> some View {
        switch destination {
        case .general:
            Image(systemName: "gearshape")
        case .cards:
            Image(systemName: "square.grid.2x2")
        case let .feature(id):
            if let card = runtime.registry.registrations.first(where: { $0.id == id }) {
                FunctionCardIconView(
                    descriptor: card.settingsIconDescriptor,
                    manifest: card.iconManifest,
                    accessibilityLabel: card.name
                )
            } else {
                Image(systemName: "square")
            }
        case .about:
            Image(systemName: "info.circle")
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
            Picker(L10n.text("Language"), selection: Binding(
                get: { AppLanguageContext.shared.selection },
                set: { store.setLanguage($0) }
            )) {
                ForEach(AppLanguage.allCases, id: \.self) { language in
                    Text(language == .system ? L10n.text("Follow System") : language.nativeName)
                        .tag(language)
                }
            }
            Section(L10n.text("显示器")) {
                Picker(L10n.text("灵动岛所在屏幕"), selection: screenBinding) {
                    ForEach(store.availableScreens) { screen in
                        Text(screen.isBuiltIn ? L10n.text("%1$@（内建）", String(describing: screen.name)) : screen.name)
                            .tag(Optional(screen.id))
                    }
                }
            }
            Section(L10n.text("交互")) {
                LabeledContent(L10n.text("悬停展开延迟")) {
                    HStack(spacing: 12) {
                        Slider(value: hoverExpansionDelayBinding, in: 0...2, step: 0.1)
                            .frame(width: 220)
                        Text(hoverExpansionDelayDescription)
                            .foregroundStyle(.secondary)
                            .frame(width: 72, alignment: .trailing)
                    }
                }
            }
            Section(L10n.text("启动")) {
                Toggle(L10n.text("登录时启动"), isOn: launchBinding)
                if store.launchStatus == .requiresApproval {
                    Text(L10n.text("需要在“系统设置 → 通用 → 登录项”中批准 Peeker。"))
                        .font(.caption).foregroundStyle(.orange)
                }
                if let error = store.launchError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
            Section(L10n.text("应用操作")) {
                Button(L10n.text("退出 Peeker"), role: .destructive) { NSApp.terminate(nil) }
            }
        }
        .formStyle(.grouped)
    }

    private var screenBinding: Binding<String?> {
        Binding(get: { store.selectedScreenID }, set: { store.selectScreen($0) })
    }

    private var hoverExpansionDelayBinding: Binding<Double> {
        Binding(
            get: { store.hoverExpansionDelaySeconds },
            set: { store.setHoverExpansionDelay($0) }
        )
    }

    private var hoverExpansionDelayDescription: String {
        store.hoverExpansionDelaySeconds == 0
            ? L10n.text("立即展开")
            : String(format: L10n.text("%.1f 秒"), store.hoverExpansionDelaySeconds)
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
            Section(L10n.text("启用与排序")) {
                List {
                    ForEach(registry.enabledCards) { card in
                        CardSettingsRow(
                            name: card.name,
                            iconDescriptor: card.iconDescriptor,
                            iconManifest: card.iconManifest,
                            isEnabled: enabledBinding(card.id)
                        )
                    }
                    .onMove(perform: registry.moveEnabled)

                    ForEach(registry.registrations.filter { !registry.enabledIDs.contains($0.id) }) { card in
                        CardSettingsRow(
                            name: card.name,
                            iconDescriptor: card.iconDescriptor,
                            iconManifest: card.iconManifest,
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
                errorMessage = L10n.text("至少需要启用一张功能卡。")
            }
        }
    }
}

private struct CardSettingsRow: View {
    let name: String
    let iconDescriptor: FunctionCardIconDescriptor
    let iconManifest: FunctionCardIconManifest?
    @Binding var isEnabled: Bool

    var body: some View {
        HStack(spacing: 8) {
            FunctionCardIconView(descriptor: iconDescriptor, manifest: iconManifest)
                .frame(width: 18, height: 18, alignment: .center)
                .accessibilityHidden(true)
            Text(name)
            Spacer()
            Toggle(L10n.text("启用"), isOn: $isEnabled)
                .labelsHidden()
                .accessibilityLabel(L10n.text("%1$@ 启用", String(describing: name)))
        }
    }
}

private struct AboutSettingsView: View {
    @Bindable var store: SettingsStore

    var body: some View {
        Form {
            Section("Peeker") {
                LabeledContent(L10n.text("版本"), value: version)
                if let startupError = store.startupError {
                    Label(startupError, systemImage: "externaldrive.badge.exclamationmark")
                        .foregroundStyle(.red)
                }
                Button(L10n.text("检查更新")) { Task { await store.checkForUpdates() } }
                    .disabled(store.updateState == .checking)
                updateStatus
            }
        }
        .formStyle(.grouped)
    }

    private var version: String {
        let bundleVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? PeekerContract.appVersion
        return "v\(bundleVersion)"
    }

    @ViewBuilder
    private var updateStatus: some View {
        switch store.updateState {
        case .idle:
            EmptyView()
        case .checking:
            ProgressView(L10n.text("正在检查 GitHub Releases…"))
        case let .current(message):
            Label(message.resolve(), systemImage: "checkmark.circle").foregroundStyle(.green)
        case let .available(release):
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.text("发现新版本 %1$@", String(describing: release.version))).font(.headline)
                if !release.notes.isEmpty { Text(release.notes).lineLimit(5) }
                Text("brew upgrade --cask peeker").font(.system(.body, design: .monospaced)).textSelection(.enabled)
                Link(L10n.text("打开发布页面"), destination: release.pageURL)
            }
        case let .failed(message):
            Text(message.resolve()).foregroundStyle(.red)
        }
    }
}
