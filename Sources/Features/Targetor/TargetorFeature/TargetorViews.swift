import Foundation
import SwiftUI
import UniformTypeIdentifiers
import FunctionCardKit
import PeekerCore

public struct TargetorFeatureDependencies {
    public let repository: any TargetorRepository
    public let clock: any Clock
    public let eventHub: TemporalEventHub
    public let refreshTime: RefreshTime
    public let iconManifest: FunctionCardIconManifest?
    public let setDragging: @MainActor (Bool) -> Void
    public let onRefreshTimeChanged: @MainActor (RefreshTime) -> Void
    public let publishPrompt: @MainActor (TargetorCheckinResult) -> Void

    public init(
        repository: any TargetorRepository,
        clock: any Clock,
        eventHub: TemporalEventHub,
        refreshTime: RefreshTime,
        iconManifest: FunctionCardIconManifest?,
        setDragging: @escaping @MainActor (Bool) -> Void,
        onRefreshTimeChanged: @escaping @MainActor (RefreshTime) -> Void,
        publishPrompt: @escaping @MainActor (TargetorCheckinResult) -> Void
    ) {
        self.repository = repository
        self.clock = clock
        self.eventHub = eventHub
        self.refreshTime = refreshTime
        self.iconManifest = iconManifest
        self.setDragging = setDragging
        self.onRefreshTimeChanged = onRefreshTimeChanged
        self.publishPrompt = publishPrompt
    }
}

@MainActor
public enum TargetorFeatureFactory {
    public static let metrics = FunctionCardMetrics(
        compactWidth: 340, compactHeight: 32,
        compactLeadingWidth: 120, compactTrailingWidth: 120,
        expandedWidth: 960, expandedHeight: 480
    )

    public static func makeStore(dependencies: TargetorFeatureDependencies) -> TargetorStore {
        let manifest = dependencies.iconManifest
        return TargetorStore(
            repository: dependencies.repository,
            clock: dependencies.clock,
            eventHub: dependencies.eventHub,
            refreshTime: dependencies.refreshTime,
            isValidIcon: { manifest?.contains($0) == true },
            publishCheckin: dependencies.publishPrompt,
            onRefreshTimeChanged: dependencies.onRefreshTimeChanged
        )
    }

    public static func makeRegistration(
        store: TargetorStore,
        dependencies: TargetorFeatureDependencies
    ) -> FunctionCardRegistration {
        Task { await store.load() }
        return FunctionCardRegistration(
            id: .targetor,
            name: "Targetor",
            iconDescriptor: .bundleSVG(featureID: .targetor, manifestResourceName: "target"),
            iconManifest: dependencies.iconManifest,
            defaultOrder: 4,
            introducedConfigurationVersion: 4,
            metrics: metrics,
            makeExpandedView: {
                AnyView(TargetorExpandedView(
                    store: store,
                    manifest: dependencies.iconManifest,
                    setDragging: dependencies.setDragging
                ))
            },
            makeSettingsView: {
                AnyView(TargetorSettingsView(store: store, manifest: dependencies.iconManifest))
            }
        )
    }
}

public enum TargetorAnimationTokens {
    public static let feedbackDuration: TimeInterval = 1
    public static let hoverScale: CGFloat = 1.025
    public static let rearOffset: CGFloat = -7
    public static let rearRotation: Double = -2.5
}

private struct TargetorDragEnvelope: Codable {
    let nonce: UUID
    let targetID: UUID
    let periodID: UUID
}

private let targetorDragType = UTType(exportedAs: "com.scpz24.peeker.targetor-checkin")

private struct TargetorExpandedView: View {
    @Bindable var store: TargetorStore
    let manifest: FunctionCardIconManifest?
    let setDragging: @MainActor (Bool) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expansionNonce = UUID()
    @State private var hoveredTargetID: UUID?
    @State private var dropTargeted = false
    @State private var pendingTargetIDs = Set<UUID>()
    @State private var calendarCells: [TargetorCalendarCell] = []

    var body: some View {
        HStack(spacing: 14) {
            Group {
                if store.targets.isEmpty {
                    ContentUnavailableView(
                        "还没有长期目标",
                        systemImage: "scope",
                        description: Text("请在 Targetor 设置中创建推进项。")
                    )
                } else {
                    ScrollView {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                            ForEach(store.targets) { state in
                                TargetorCard(
                                    state: state, manifest: manifest,
                                    hovered: hoveredTargetID == state.id,
                                    reduceMotion: reduceMotion
                                )
                                .onHover { hoveredTargetID = $0 ? state.id : nil }
                                .onDrag {
                                    guard let period = state.currentPeriod,
                                          period.state != .completed,
                                          let data = try? JSONEncoder().encode(TargetorDragEnvelope(
                                            nonce: expansionNonce, targetID: state.id, periodID: period.id
                                          ))
                                    else { return NSItemProvider() }
                                    setDragging(true)
                                    let provider = NSItemProvider()
                                    provider.registerDataRepresentation(
                                        forTypeIdentifier: targetorDragType.identifier,
                                        visibility: .ownProcess
                                    ) { completion in completion(data, nil); return nil }
                                    return provider
                                }
                            }
                        }
                        .padding(4)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            TargetorSidePanel(
                store: store, manifest: manifest, cells: calendarCells,
                hoveredTargetID: hoveredTargetID, isDropTargeted: dropTargeted,
                reduceMotion: reduceMotion
            )
            .frame(width: 215)
            .frame(maxHeight: .infinity)
            .onDrop(of: [targetorDragType], isTargeted: $dropTargeted) { providers in
                guard let provider = providers.first else { setDragging(false); return false }
                provider.loadDataRepresentation(forTypeIdentifier: targetorDragType.identifier) { data, _ in
                    Task { @MainActor in
                        defer { setDragging(false) }
                        guard let data,
                              let envelope = try? JSONDecoder().decode(TargetorDragEnvelope.self, from: data),
                              envelope.nonce == expansionNonce,
                              pendingTargetIDs.insert(envelope.targetID).inserted
                        else { return }
                        defer { pendingTargetIDs.remove(envelope.targetID) }
                        _ = try? await store.checkin(
                            targetID: envelope.targetID,
                            expectedPeriodID: envelope.periodID
                        )
                        await reloadCalendar()
                    }
                }
                return true
            }
        }
        .onAppear { expansionNonce = UUID() }
        .task { await reloadCalendar() }
        .onChange(of: store.feedback?.token) { _, _ in Task { await reloadCalendar() } }
    }

    private func reloadCalendar() async {
        calendarCells = (try? await store.summaryCalendar()) ?? []
    }
}

private struct TargetorCard: View {
    let state: TargetorTargetState
    let manifest: FunctionCardIconManifest?
    let hovered: Bool
    let reduceMotion: Bool

    var body: some View {
        let period = state.currentPeriod
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(.white.opacity(0.22))
                .offset(x: hovered && !reduceMotion ? TargetorAnimationTokens.rearOffset : 0)
                .rotationEffect(.degrees(hovered && !reduceMotion ? TargetorAnimationTokens.rearRotation : 0))
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    FunctionCardIconView(
                        descriptor: .bundleSVG(featureID: .targetor, manifestResourceName: state.target.iconName),
                        manifest: manifest,
                        accessibilityLabel: state.target.iconName
                    )
                    .frame(width: 22, height: 22)
                    Spacer()
                    Text("\(period?.count ?? 0)/\(period?.maxCountSnapshot ?? state.target.maxCount)")
                        .monospacedDigit().font(.caption.bold())
                }
                Text(state.target.title).font(.headline).lineLimit(1)
                if let description = state.target.description {
                    Text(description).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        .accessibilityLabel(description)
                }
                ProgressView(value: period?.ratio ?? 0).tint(statusColor(period?.state ?? .notStarted))
            }
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(statusColor(period?.state ?? .notStarted).opacity(borderOpacity(period?.state ?? .notStarted)), lineWidth: 1.5)
            }
            .scaleEffect(hovered && !reduceMotion ? TargetorAnimationTokens.hoverScale : 1)
        }
        .frame(minHeight: 125)
        .contentShape(RoundedRectangle(cornerRadius: 14))
    }

    private func borderOpacity(_ state: TargetorCheckinState) -> Double {
        switch state { case .notStarted: 0; case .started: 0.35; case .progressing: 0.65; case .completed: 1 }
    }
}

private struct TargetorSidePanel: View {
    @Bindable var store: TargetorStore
    let manifest: FunctionCardIconManifest?
    let cells: [TargetorCalendarCell]
    let hoveredTargetID: UUID?
    let isDropTargeted: Bool
    let reduceMotion: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.08))
            if let feedback = store.feedback {
                feedbackView(feedback.state)
                    .transition(.opacity)
            } else if isDropTargeted {
                Label("松开以打卡", systemImage: "arrow.down.circle.fill")
                    .font(.headline)
            } else {
                VStack(spacing: 10) {
                    Text(hoveredTargetID == nil ? "最近九周" : "当前目标")
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(15), spacing: 5), count: 9), spacing: 5) {
                        ForEach(cells) { cell in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(calendarColor(cell.level))
                                .frame(width: 15, height: 15)
                                .help(cell.date.formatted(date: .abbreviated, time: .omitted))
                        }
                    }
                }
                .padding(12)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(.white.opacity(isDropTargeted ? 0.8 : 0.15), lineWidth: isDropTargeted ? 2 : 1)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: store.feedback?.token)
    }

    private func feedbackView(_ state: TargetorCheckinState) -> some View {
        let icon: String = switch state {
        case .notStarted, .started: "chevrons-up"
        case .progressing: "rocket"
        case .completed: "badge-check"
        }
        return VStack(spacing: 12) {
            FunctionCardIconView(
                descriptor: .bundleSVG(featureID: .targetor, manifestResourceName: icon),
                manifest: manifest,
                accessibilityLabel: "打卡成功"
            ).frame(width: 52, height: 52)
            Text("打卡成功").font(.headline)
        }
    }
}

private struct TargetorSettingsView: View {
    @Bindable var store: TargetorStore
    let manifest: FunctionCardIconManifest?
    @State private var editorTarget: TargetorTargetState?
    @State private var creating = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("周期") {
                DatePicker("全局刷新时刻", selection: refreshBinding, displayedComponents: .hourAndMinute)
            }
            Section("长期目标") {
                List {
                    ForEach(store.targets) { state in
                        HStack {
                            FunctionCardIconView(
                                descriptor: .bundleSVG(featureID: .targetor, manifestResourceName: state.target.iconName),
                                manifest: manifest
                            ).frame(width: 18, height: 18)
                            Text(state.target.title)
                            Spacer()
                            Button("编辑") { editorTarget = state }
                            Button("删除", role: .destructive) {
                                Task {
                                    do { _ = try await store.archive(targetID: state.id) }
                                    catch { errorMessage = error.localizedDescription }
                                }
                            }
                        }
                    }
                    .onMove { offsets, destination in
                        var ids = store.targets.map(\.id)
                        ids.move(fromOffsets: offsets, toOffset: destination)
                        Task { try? await store.reorder(targetIDs: ids) }
                    }
                }
                .frame(minHeight: 220)
                Button("新增目标", systemImage: "plus") { creating = true }
                if let errorMessage { Text(errorMessage).font(.caption).foregroundStyle(.red) }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $creating) {
            TargetorEditor(store: store, manifest: manifest, existing: nil) { creating = false }
        }
        .sheet(item: $editorTarget) { state in
            TargetorEditor(store: store, manifest: manifest, existing: state) { editorTarget = nil }
        }
    }

    private var refreshBinding: Binding<Date> {
        Binding {
            Calendar.current.date(from: DateComponents(hour: store.refreshTime.hour, minute: store.refreshTime.minute)) ?? Date()
        } set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            guard let value = try? RefreshTime(hour: parts.hour ?? 0, minute: parts.minute ?? 0) else { return }
            Task { try? await store.updateRefreshTime(value) }
        }
    }
}

private struct TargetorEditor: View {
    let store: TargetorStore
    let manifest: FunctionCardIconManifest?
    let existing: TargetorTargetState?
    let dismiss: () -> Void
    @State private var title: String
    @State private var description = ""
    @State private var icon = "target"
    @State private var frequency = TargetorFrequency.daily
    @State private var weekday = TargetorWeekday.mon
    @State private var monthDay = 1
    @State private var maxCount = 1
    @State private var query = ""
    @State private var errorMessage: String?

    init(store: TargetorStore, manifest: FunctionCardIconManifest?, existing: TargetorTargetState?, dismiss: @escaping () -> Void) {
        self.store = store; self.manifest = manifest; self.existing = existing; self.dismiss = dismiss
        _title = State(initialValue: existing?.target.title ?? "")
        _description = State(initialValue: existing?.target.description ?? "")
        _icon = State(initialValue: existing?.target.iconName ?? "target")
        _frequency = State(initialValue: existing?.target.periodRule.frequency ?? .daily)
        _weekday = State(initialValue: existing?.target.periodRule.weekday ?? .mon)
        _monthDay = State(initialValue: existing?.target.periodRule.monthDay ?? 1)
        _maxCount = State(initialValue: existing?.target.maxCount ?? 1)
    }

    var body: some View {
        VStack(spacing: 14) {
            Form {
                TextField("标题", text: $title)
                TextField("描述（可选）", text: $description)
                Picker("周期", selection: $frequency) {
                    ForEach(TargetorFrequency.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                if frequency == .weekly {
                    Picker("星期", selection: $weekday) {
                        ForEach(TargetorWeekday.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                }
                if frequency == .monthly { Stepper("月刷新日：\(monthDay)", value: $monthDay, in: 0...30) }
                Stepper("最大次数：\(maxCount)", value: $maxCount, in: 1...99)
                TextField("搜索图标", text: $query)
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8)) {
                        ForEach(Array((manifest?.search(query) ?? []).prefix(160)), id: \.name) { entry in
                            Button { icon = entry.name } label: {
                                FunctionCardIconView(
                                    descriptor: .bundleSVG(featureID: .targetor, manifestResourceName: entry.name),
                                    manifest: manifest, accessibilityLabel: entry.name
                                ).frame(width: 22, height: 22).padding(5)
                                    .background(icon == entry.name ? Color.accentColor.opacity(0.3) : .clear, in: RoundedRectangle(cornerRadius: 5))
                            }.buttonStyle(.plain).help(entry.name)
                        }
                    }
                }.frame(height: 120)
                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            }
            HStack {
                Button("取消", action: dismiss)
                Spacer()
                Button("保存") { Task { await save() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || manifest?.contains(icon) != true)
            }
        }
        .padding(20).frame(width: 560, height: 520)
    }

    private func save() async {
        do {
            let rule = try TargetorPeriodRule(
                frequency: frequency,
                weekday: frequency == .weekly ? weekday : nil,
                monthDay: frequency == .monthly ? monthDay : nil
            )
            if let existing {
                _ = try await store.update(
                    targetID: existing.id, title: title, description: description,
                    iconName: icon, periodRule: rule, maxCount: maxCount
                )
            } else {
                _ = try await store.create(
                    title: title, description: description, iconName: icon,
                    periodRule: rule, maxCount: maxCount
                )
            }
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}

private func statusColor(_ state: TargetorCheckinState) -> Color {
    switch state {
    case .notStarted: .secondary
    case .started: .blue.opacity(0.45)
    case .progressing: .blue.opacity(0.75)
    case .completed: .blue
    }
}

private func calendarColor(_ level: TargetorCompletionLevel) -> Color {
    switch level {
    case .empty: .white.opacity(0.08)
    case .one: .blue.opacity(0.25)
    case .two: .blue.opacity(0.45)
    case .three: .blue.opacity(0.7)
    case .four: .blue
    }
}
