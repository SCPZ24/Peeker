import SwiftUI
import PeekerCore
import FunctionCardKit

public struct TimerFeatureDependencies {
    public let repository: any TimerRepository
    public let clock: any Clock
    public let resolver: BusinessDayResolver
    public let eventHub: TemporalEventHub
    public let publishPrompt: @MainActor (FunctionCardPrompt) -> Void
    public let refreshTime: RefreshTime
    public let statisticsMode: TimerStatisticsMode
    public let temporaryTasksEnabled: Bool
    public let layoutState: FunctionCardLayoutState?
    public let setPopoverPresented: @MainActor @Sendable (Bool) -> Void
    public let setEditingText: @MainActor @Sendable (Bool) -> Void
    public let onRefreshTimeChanged: @MainActor (RefreshTime) -> Void
    public let onStatisticsModeChanged: @MainActor (TimerStatisticsMode) -> Void
    public let onTemporaryTasksEnabledChanged: @MainActor (Bool) -> Void

    public init(
        repository: any TimerRepository,
        clock: any Clock,
        resolver: BusinessDayResolver,
        eventHub: TemporalEventHub,
        publishPrompt: @escaping @MainActor (FunctionCardPrompt) -> Void = { _ in },
        refreshTime: RefreshTime = .midnight,
        statisticsMode: TimerStatisticsMode = .progress,
        temporaryTasksEnabled: Bool = false,
        layoutState: FunctionCardLayoutState? = nil,
        setPopoverPresented: @escaping @MainActor @Sendable (Bool) -> Void = { _ in },
        setEditingText: @escaping @MainActor @Sendable (Bool) -> Void = { _ in },
        onRefreshTimeChanged: @escaping @MainActor (RefreshTime) -> Void = { _ in },
        onStatisticsModeChanged: @escaping @MainActor (TimerStatisticsMode) -> Void = { _ in },
        onTemporaryTasksEnabledChanged: @escaping @MainActor (Bool) -> Void = { _ in }
    ) {
        self.repository = repository
        self.clock = clock
        self.resolver = resolver
        self.eventHub = eventHub
        self.publishPrompt = publishPrompt
        self.refreshTime = refreshTime
        self.statisticsMode = statisticsMode
        self.temporaryTasksEnabled = temporaryTasksEnabled
        self.layoutState = layoutState
        self.setPopoverPresented = setPopoverPresented
        self.setEditingText = setEditingText
        self.onRefreshTimeChanged = onRefreshTimeChanged
        self.onStatisticsModeChanged = onStatisticsModeChanged
        self.onTemporaryTasksEnabledChanged = onTemporaryTasksEnabledChanged
    }
}

@MainActor
public enum TimerFeatureFactory {
    static let metrics = FunctionCardMetrics(
        compactWidth: 340,
        compactHeight: 32,
        compactLeadingWidth: 208,
        compactTrailingWidth: 136,
        expandedWidth: 800,
        expandedHeight: 460 * 5 / 7
    )

    public static func make(dependencies: TimerFeatureDependencies) -> FunctionCardRegistration {
        let store = makeStore(dependencies: dependencies)
        return makeRegistration(store: store, dependencies: dependencies)
    }

    public static func makeStore(dependencies: TimerFeatureDependencies) -> TimerStore {
        TimerStore(
            repository: dependencies.repository,
            clock: dependencies.clock,
            resolver: dependencies.resolver,
            eventHub: dependencies.eventHub,
            onNaturalCompletion: { task in
                dependencies.publishPrompt(FunctionCardPrompt(
                    token: UUID().uuidString,
                    sourceID: .timer,
                    systemImage: "timer",
                    moduleName: "Timer",
                    summary: "✓ \(task.name)"
                ))
            },
            onTemporaryNaturalCompletion: { task in
                dependencies.publishPrompt(FunctionCardPrompt(
                    token: UUID().uuidString,
                    sourceID: .timer,
                    systemImage: "timer",
                    moduleName: "Timer",
                    summary: "✓ \(task.name)"
                ))
            },
            refreshTime: dependencies.refreshTime,
            statisticsMode: dependencies.statisticsMode,
            temporaryTasksEnabled: dependencies.temporaryTasksEnabled,
            onRefreshTimeChanged: dependencies.onRefreshTimeChanged,
            onStatisticsModeChanged: dependencies.onStatisticsModeChanged,
            onTemporaryTasksEnabledChanged: dependencies.onTemporaryTasksEnabledChanged
        )
    }

    public static func makeRegistration(
        store: TimerStore,
        dependencies: TimerFeatureDependencies? = nil
    ) -> FunctionCardRegistration {
        Task { await store.load() }
        return FunctionCardRegistration(
            id: .timer,
            name: "Timer",
            systemImage: "timer",
            defaultOrder: 0,
            metrics: metrics,
            layoutState: dependencies?.layoutState,
            isCompactEligible: { store.hasRunningTask },
            makeCompactLeadingView: { AnyView(TimerCompactLeadingView(store: store)) },
            makeCompactTrailingView: { AnyView(TimerCompactTrailingView(store: store)) },
            makeExpandedView: {
                if let dependencies {
                    return AnyView(TimerExpandedView(
                        store: store,
                        setPopoverPresented: dependencies.setPopoverPresented,
                        setEditingText: dependencies.setEditingText
                    ))
                }
                return AnyView(TimerExpandedView(store: store))
            },
            makeSettingsView: { AnyView(TimerSettingsView(store: store)) }
        )
    }
}

private struct TimerCompactLeadingView: View {
    @Bindable var store: TimerStore

    var body: some View {
        if let task = store.runningTask {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color(hex: task.colorHex))
                    .frame(width: 8, height: 8)
                    .fixedSize()
                    .layoutPriority(2)
                Text(task.name)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(TimerIslandAppearance.primaryText)
            }
        } else if let task = store.runningTemporaryTask {
            HStack(spacing: 8) {
                Circle().fill(Color(hex: task.colorHex)).frame(width: 8, height: 8)
                Text(task.name).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(TimerIslandAppearance.primaryText)
            }
        } else {
            Label("Timer", systemImage: "timer")
                .foregroundStyle(TimerIslandAppearance.secondaryText)
        }
    }
}

private struct TimerCompactTrailingView: View {
    @Bindable var store: TimerStore

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            if let task = store.runningTask {
                Text(formatDuration(store.remainingSeconds(for: task, at: context.date)))
                    .monospacedDigit()
                    .foregroundStyle(TimerIslandAppearance.secondaryText)
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(2)
            } else if let task = store.runningTemporaryTask {
                Text(formatDuration(store.remainingSeconds(for: task, at: context.date)))
                    .monospacedDigit()
                    .foregroundStyle(TimerIslandAppearance.secondaryText)
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(2)
            }
        }
    }
}

private struct TimerExpandedView: View {
    @Bindable var store: TimerStore
    let setPopoverPresented: @MainActor @Sendable (Bool) -> Void
    let setEditingText: @MainActor @Sendable (Bool) -> Void
    @State private var creatingTemporary = false

    init(
        store: TimerStore,
        setPopoverPresented: @escaping @MainActor @Sendable (Bool) -> Void = { _ in },
        setEditingText: @escaping @MainActor @Sendable (Bool) -> Void = { _ in }
    ) {
        self.store = store
        self.setPopoverPresented = setPopoverPresented
        self.setEditingText = setEditingText
    }

    var body: some View {
        HStack(spacing: 18) {
            Group {
                if let state = store.dayState,
                   !state.visibleTasks.isEmpty || !state.activeTemporaryTasks.isEmpty {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(state.visibleTasks) { task in
                                TimerTaskRow(store: store, task: task)
                            }
                            ForEach(state.activeTemporaryTasks) { task in
                                TimerTemporaryTaskRow(
                                    store: store, task: task,
                                    setPopoverPresented: setPopoverPresented,
                                    setEditingText: setEditingText
                                )
                            }
                        }
                    }
                } else {
                    ContentUnavailableView("还没有计时目标", systemImage: "timer")
                        .foregroundStyle(TimerIslandAppearance.primaryText)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider().overlay(.white.opacity(0.2))

            VStack(spacing: 8) {
                if store.temporaryTasksEnabled {
                    Button {
                        creatingTemporary = true
                        setPopoverPresented(true)
                    } label: {
                        Label("新增临时任务", systemImage: "plus.circle.fill")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .popover(isPresented: $creatingTemporary, arrowEdge: .bottom) {
                        TimerTemporaryEditor(store: store, task: nil, setEditingText: setEditingText) {
                            creatingTemporary = false
                            setPopoverPresented(false)
                        }
                    }
                    .frame(maxHeight: .infinity)
                }
                TimerStatisticsPanel(store: store)
                    .frame(maxHeight: .infinity)
            }
            .frame(width: 165)
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .onChange(of: creatingTemporary) { _, presented in
            if !presented { setPopoverPresented(false) }
        }
        .overlay(alignment: .bottomLeading) {
            if let error = store.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red).lineLimit(2)
            }
        }
    }
}

private struct TimerStatisticsPanel: View {
    @Bindable var store: TimerStore

    var body: some View {
        Group {
            if store.statisticsMode == .progress {
                if let state = store.dayState,
                   !state.visibleTasks.isEmpty || !state.activeTemporaryTasks.isEmpty {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let daily = state.visibleTasks.map { task in
                            TimerProgressSnapshot(
                                targetSeconds: task.targetSeconds,
                                remainingSeconds: store.remainingSeconds(for: task, at: context.date)
                            )
                        }
                        let temporary = state.activeTemporaryTasks.map { task in
                            TimerProgressSnapshot(
                                targetSeconds: task.targetSeconds,
                                remainingSeconds: store.remainingSeconds(for: task, at: context.date)
                            )
                        }
                        if let ratio = TimerProgressMetrics.totalRatio(daily + temporary) {
                            TimerCompletionRing(ratio: ratio)
                        }
                    }
                } else {
                    Text("添加目标后显示完成度")
                        .foregroundStyle(TimerIslandAppearance.secondaryText)
                        .multilineTextAlignment(.center)
                }
            } else {
                TimerActivityCalendar(store: store)
            }
        }
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
    }
}

private enum TimerTaskRowLayout {
    static let detailsWidth: CGFloat = 170
    static let auxiliaryControlWidth: CGFloat = 38
}

private struct TimerTemporaryTaskRow: View {
    @Bindable var store: TimerStore
    let task: TimerTemporaryTask
    let setPopoverPresented: @MainActor @Sendable (Bool) -> Void
    let setEditingText: @MainActor @Sendable (Bool) -> Void
    @State private var editing = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = store.remainingSeconds(for: task, at: context.date)
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(hex: task.colorHex))
                    .frame(width: 6, height: 34)
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(task.name)
                            .font(.headline)
                            .lineLimit(1)
                            .foregroundStyle(TimerIslandAppearance.primaryText)
                        Text(task.status == .completed ? "已完成" : formatDuration(remaining))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(
                                task.status == .completed
                                    ? Color.green
                                    : TimerIslandAppearance.secondaryText
                            )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Button("编辑", systemImage: "pencil") {
                        editing = true
                        setPopoverPresented(true)
                    }
                    .labelStyle(.iconOnly)
                    .frame(width: TimerTaskRowLayout.auxiliaryControlWidth)
                    .popover(isPresented: $editing, arrowEdge: .bottom) {
                        TimerTemporaryEditor(store: store, task: task, setEditingText: setEditingText) {
                            editing = false
                            setPopoverPresented(false)
                        }
                    }
                }
                .frame(width: TimerTaskRowLayout.detailsWidth)
                TimerTaskProgressBar(
                    ratio: TimerProgressSnapshot(targetSeconds: task.targetSeconds, remainingSeconds: remaining).ratio,
                    color: Color(hex: task.colorHex)
                )
                .frame(minWidth: 80, maxWidth: .infinity)
                .frame(height: 4)
                if task.status == .running {
                    Button("暂停", systemImage: "pause.fill") {
                        Task { try? await store.pause() }
                    }
                    .labelStyle(.iconOnly)
                } else if task.status == .completed {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                } else {
                    Button("开始", systemImage: "play.fill") {
                        Task { try? await store.startTemporaryTask(id: task.id) }
                    }
                    .labelStyle(.iconOnly)
                    .disabled(store.hasRunningTask)
                }
            }
            .padding(10).background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        }
        .onChange(of: editing) { _, value in if !value { setPopoverPresented(false) } }
    }
}

private struct TimerTemporaryEditor: View {
    let store: TimerStore
    let task: TimerTemporaryTask?
    let setEditingText: @MainActor @Sendable (Bool) -> Void
    let dismiss: () -> Void
    @State private var name: String
    @State private var duration: TimerDurationDraft
    @State private var colorHex: String
    @State private var expireOnRefresh: Bool
    @State private var errorMessage: String?
    @FocusState private var nameFocused: Bool

    init(
        store: TimerStore,
        task: TimerTemporaryTask?,
        setEditingText: @escaping @MainActor @Sendable (Bool) -> Void,
        dismiss: @escaping () -> Void
    ) {
        self.store = store; self.task = task; self.setEditingText = setEditingText; self.dismiss = dismiss
        _name = State(initialValue: task?.name ?? "")
        _duration = State(initialValue: task.map { TimerDurationDraft(targetSeconds: $0.targetSeconds) } ?? TimerDurationDraft())
        _colorHex = State(initialValue: task?.colorHex ?? PeekerPresetColor.lakeBlue.rawValue)
        _expireOnRefresh = State(initialValue: task?.expireOnRefresh ?? false)
    }

    var body: some View {
        Form {
            TextField("名称", text: $name)
                .focused($nameFocused)
                .onChange(of: nameFocused) { _, value in setEditingText(value) }
            TimerDurationInput(duration: $duration)
            TimerPresetColorPicker(colorHex: $colorHex)
            Toggle("随刷新消失", isOn: $expireOnRefresh)
            if let errorMessage { Text(errorMessage).font(.caption).foregroundStyle(.red) }
            HStack {
                if let task {
                    Button("删除", role: .destructive) {
                        Task { do { _ = try await store.deleteTemporaryTask(id: task.id); dismiss() }
                            catch { errorMessage = error.localizedDescription } }
                    }
                }
                Spacer()
                Button("取消", action: dismiss)
                Button("保存") { Task { await save() } }
                    .buttonStyle(.borderedProminent).disabled(!isValid)
            }
        }
        .padding(16)
        .frame(width: 420)
        .preferredColorScheme(.light)
        .environment(\.colorScheme, .light)
        .foregroundStyle(Color.primary)
        .tint(.accentColor)
        .onDisappear { setEditingText(false) }
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && duration.targetSeconds != nil
    }

    private func save() async {
        guard let target = duration.targetSeconds else { return }
        do {
            if let task {
                _ = try await store.updateTemporaryTask(
                    id: task.id, name: name, targetSeconds: target,
                    colorHex: colorHex, expireOnRefresh: expireOnRefresh
                )
            } else {
                _ = try await store.createTemporaryTask(
                    name: name, targetSeconds: target, colorHex: colorHex,
                    expireOnRefresh: expireOnRefresh
                )
            }
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}

private struct TimerTaskRow: View {
    @Bindable var store: TimerStore
    let task: TimerTaskInstance

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remainingSeconds = store.remainingSeconds(for: task, at: context.date)
            let progress = TimerProgressSnapshot(
                targetSeconds: task.targetSeconds,
                remainingSeconds: remainingSeconds
            )
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(hex: task.colorHex))
                    .frame(width: 6, height: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text(task.name)
                        .font(.headline)
                        .lineLimit(1)
                        .foregroundStyle(TimerIslandAppearance.primaryText)
                    Text(task.status == .completed ? "已完成" : formatDuration(remainingSeconds))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(
                            task.status == .completed
                                ? Color.green
                                : TimerIslandAppearance.secondaryText
                        )
                }
                .frame(width: TimerTaskRowLayout.detailsWidth, alignment: .leading)
                TimerTaskProgressBar(ratio: progress.ratio, color: Color(hex: task.colorHex))
                    .frame(minWidth: 80, maxWidth: .infinity)
                    .frame(height: 4)
                if task.status == .running {
                    Button("暂停", systemImage: "pause.fill") {
                        Task { try? await store.pause() }
                    }
                    .labelStyle(.iconOnly)
                } else if task.status == .completed {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                } else {
                    Button("开始", systemImage: "play.fill") {
                        Task { await store.start(taskID: task.id) }
                    }
                    .labelStyle(.iconOnly)
                    .disabled(store.dayState?.activeSession != nil)
                }
            }
            .padding(10)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

private struct TimerSettingsView: View {
    @Bindable var store: TimerStore
    @State private var name = ""
    @State private var duration = TimerDurationDraft()
    @State private var colorHex = TimerPresetColor.lakeBlue.rawValue
    @State private var editingTemplate: TimerTemplate?
    @State private var pendingDeleteID: UUID?

    var body: some View {
        Form {
            Section("业务日") {
                DatePicker(
                    "刷新时间",
                    selection: refreshBinding,
                    displayedComponents: .hourAndMinute
                )
                Picker("统计显示", selection: statisticsBinding) {
                    Text("今日完成度").tag(TimerStatisticsMode.progress)
                    Text("当月热力日历").tag(TimerStatisticsMode.heatmap)
                }
                Toggle("允许临时计时任务", isOn: Binding(
                    get: { store.temporaryTasksEnabled },
                    set: { store.setTemporaryTasksEnabled($0) }
                ))
            }
            Section("每日计时目标") {
                List {
                    ForEach(store.templates) { template in
                        HStack {
                            Circle().fill(Color(hex: template.colorHex)).frame(width: 10, height: 10)
                            Text(template.name)
                            Spacer()
                            Text(formatDuration(template.targetSeconds)).foregroundStyle(.secondary)
                            Button {
                                editingTemplate = template
                            } label: {
                                Image(systemName: "pencil")
                            }
                            .buttonStyle(.borderless)
                            Button(role: .destructive) {
                                pendingDeleteID = template.id
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    .onMove { offsets, destination in
                        Task { await store.reorderTemplates(fromOffsets: offsets, toOffset: destination) }
                    }
                }
                .frame(minHeight: 150)

                VStack(alignment: .leading, spacing: 12) {
                    TextField(
                        "目标名称",
                        text: $name,
                        prompt: Text("目标名称").foregroundStyle(.secondary)
                    )
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .foregroundStyle(.primary)

                    TimerDurationInput(duration: $duration)
                    TimerPresetColorPicker(colorHex: $colorHex)

                    HStack {
                        Spacer()
                        Button("添加") {
                            guard let targetSeconds = duration.targetSeconds else { return }
                            let submittedName = name
                            let submittedColorHex = colorHex
                            name = ""
                            duration = TimerDurationDraft()
                            colorHex = TimerPresetColor.lakeBlue.rawValue
                            Task {
                                await store.createTemplate(
                                    name: submittedName,
                                    targetSeconds: targetSeconds,
                                    colorHex: submittedColorHex
                                )
                            }
                        }
                        .disabled(!canAddTemplate)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .formStyle(.grouped)
        .sheet(item: $editingTemplate) { template in
            TimerTemplateEditor(template: template) { updated in
                await store.updateTemplate(updated)
                editingTemplate = nil
            }
        }
        .confirmationDialog("删除这个计时目标？历史会话仍会保留。", isPresented: deleteConfirmation) {
            Button("删除", role: .destructive) {
                guard let id = pendingDeleteID else { return }
                pendingDeleteID = nil
                Task { await store.deleteTemplate(id: id) }
            }
            Button("取消", role: .cancel) { pendingDeleteID = nil }
        }
    }

    private var canAddTemplate: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && duration.targetSeconds != nil
    }

    private var refreshBinding: Binding<Date> {
        Binding {
            Calendar.current.date(from: DateComponents(hour: store.refreshTime.hour, minute: store.refreshTime.minute)) ?? .now
        } set: { date in
            let components = Calendar.current.dateComponents([.hour, .minute], from: date)
            guard let hour = components.hour, let minute = components.minute,
                  let refresh = try? RefreshTime(hour: hour, minute: minute) else { return }
            Task { await store.updateRefreshTime(refresh) }
        }
    }

    private var statisticsBinding: Binding<TimerStatisticsMode> {
        Binding(
            get: { store.statisticsMode },
            set: { store.updateStatisticsMode($0) }
        )
    }

    private var deleteConfirmation: Binding<Bool> {
        Binding(
            get: { pendingDeleteID != nil },
            set: { if !$0 { pendingDeleteID = nil } }
        )
    }
}

private struct TimerTemplateEditor: View {
    let template: TimerTemplate
    let save: (TimerTemplate) async -> Void
    @State private var name: String
    @State private var duration: TimerDurationDraft
    @State private var colorHex: String
    @Environment(\.dismiss) private var dismiss

    init(template: TimerTemplate, save: @escaping (TimerTemplate) async -> Void) {
        self.template = template
        self.save = save
        _name = State(initialValue: template.name)
        _duration = State(initialValue: TimerDurationDraft(targetSeconds: template.targetSeconds))
        _colorHex = State(initialValue: template.colorHex)
    }

    var body: some View {
        Form {
            TextField(
                "名称",
                text: $name,
                prompt: Text("名称").foregroundStyle(.secondary)
            )
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            .foregroundStyle(.primary)
            TimerDurationInput(duration: $duration)
            TimerPresetColorPicker(colorHex: $colorHex)
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("保存") {
                    guard let updated = updatedTemplate else { return }
                    Task { await save(updated) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(updatedTemplate == nil)
            }
        }
        .padding(18)
        .frame(width: 440)
    }

    private var updatedTemplate: TimerTemplate? {
        guard let targetSeconds = duration.targetSeconds else { return nil }
        return try? TimerTemplate(
            id: template.id,
            name: name,
            targetSeconds: targetSeconds,
            colorHex: colorHex,
            position: template.position,
            updatedAtMilliseconds: Date().millisecondsSince1970
        )
    }
}

private struct TimerDurationInput: View {
    @Binding var duration: TimerDurationDraft

    var body: some View {
        HStack(spacing: 14) {
            TimerDurationField(
                title: "时",
                accessibilityName: "小时",
                value: $duration.hours,
                increment: { duration.adjust(.hours, by: 1) },
                decrement: { duration.adjust(.hours, by: -1) }
            )
            TimerDurationField(
                title: "分",
                accessibilityName: "分钟",
                value: $duration.minutes,
                increment: { duration.adjust(.minutes, by: 1) },
                decrement: { duration.adjust(.minutes, by: -1) }
            )
            TimerDurationField(
                title: "秒",
                accessibilityName: "秒钟",
                value: $duration.seconds,
                increment: { duration.adjust(.seconds, by: 1) },
                decrement: { duration.adjust(.seconds, by: -1) }
            )
            Spacer(minLength: 0)
        }
    }
}

private struct TimerDurationField: View {
    let title: String
    let accessibilityName: String
    @Binding var value: String
    let increment: () -> Void
    let decrement: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 4) {
                TextField("", text: $value)
                    .frame(width: 44)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .font(.body.monospacedDigit())
                    .foregroundStyle(.primary)
                    .accessibilityLabel(accessibilityName)
                Stepper {
                    EmptyView()
                } onIncrement: {
                    increment()
                } onDecrement: {
                    decrement()
                }
                .labelsHidden()
                .accessibilityLabel("调整\(accessibilityName)")
                .accessibilityValue(value)
            }
        }
    }
}

private struct TimerPresetColorPicker: View {
    @Binding var colorHex: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("颜色")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                if !isPresetColor {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color(hex: colorHex))
                            .frame(width: 18, height: 18)
                        Text("当前颜色")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.trailing, 4)
                }

                ForEach(TimerPresetColor.allCases) { preset in
                    let isSelected = colorHex.caseInsensitiveCompare(preset.rawValue) == .orderedSame
                    Button {
                        colorHex = preset.rawValue
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color(hex: preset.rawValue))
                            Circle()
                                .strokeBorder(
                                    isSelected ? Color.primary : Color.clear,
                                    lineWidth: 2
                                )
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .help(preset.localizedName)
                    .accessibilityLabel(preset.localizedName)
                    .accessibilityValue(isSelected ? "已选择" : "未选择")
                }
            }
        }
    }

    private var isPresetColor: Bool {
        TimerPresetColor.allCases.contains {
            colorHex.caseInsensitiveCompare($0.rawValue) == .orderedSame
        }
    }
}

private struct TimerActivityCalendar: View {
    @Bindable var store: TimerStore
    @State private var displayedMonth = Date.now
    private var calendar: Calendar { .autoupdatingCurrent }

    var body: some View {
        VStack(spacing: 5) {
            monthHeader
            weekdayHeader
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let currentStart = store.dayState?.businessDay.start ?? context.date
                let grid = CalendarMonthGrid(
                    displaying: displayedMonth,
                    currentBusinessDayStart: currentStart,
                    calendar: calendar
                )
                VStack(spacing: 4) {
                    ForEach(Array(grid.weeks.enumerated()), id: \.offset) { _, week in
                        HStack(spacing: 3) {
                            ForEach(week) { day in
                                TimerCalendarDayRing(
                                    day: day,
                                    state: state(for: day, at: context.date),
                                    accessibilityText: accessibilityText(for: day, at: context.date)
                                )
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .task(id: monthTaskID) {
            await store.loadSnapshots(for: displayedMonth)
        }
    }

    private var monthHeader: some View {
        HStack(spacing: 6) {
            Button { moveMonth(-1) } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
            Text(displayedMonth.formatted(.dateTime.year().month(.abbreviated)))
                .font(.caption.weight(.semibold))
                .foregroundStyle(TimerIslandAppearance.primaryText)
            Spacer(minLength: 0)
            Button { moveMonth(1) } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(TimerIslandAppearance.secondaryText)
    }

    private var weekdayHeader: some View {
        let symbols = rotatedWeekdaySymbols
        return HStack(spacing: 3) {
            ForEach(Array(symbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.system(size: 7, weight: .medium))
                    .foregroundStyle(TimerIslandAppearance.secondaryText)
                    .frame(width: 20)
            }
        }
    }

    private var rotatedWeekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let offset = max(0, min(symbols.count - 1, calendar.firstWeekday - 1))
        return Array(symbols[offset...]) + Array(symbols[..<offset])
    }

    private var monthTaskID: Int64 {
        calendar.dateInterval(of: .month, for: displayedMonth)?.start.millisecondsSince1970 ?? 0
    }

    private func moveMonth(_ offset: Int) {
        displayedMonth = calendar.date(byAdding: .month, value: offset, to: displayedMonth) ?? displayedMonth
    }

    private func state(for day: CalendarMonthDay, at now: Date) -> TimerCalendarRingState {
        if day.isFutureBusinessDay { return .future }
        if day.isCurrentBusinessDay {
            guard let state = store.dayState else { return .noTasks }
            let daily = state.visibleTasks.map {
                TimerProgressSnapshot(
                    targetSeconds: $0.targetSeconds,
                    remainingSeconds: store.remainingSeconds(for: $0, at: now)
                )
            }
            let temporary = state.activeTemporaryTasks.map {
                TimerProgressSnapshot(
                    targetSeconds: $0.targetSeconds,
                    remainingSeconds: store.remainingSeconds(for: $0, at: now)
                )
            }
            return .recorded(ratio: TimerProgressMetrics.totalRatio(daily + temporary))
        }
        guard let snapshot = snapshot(for: day.date) else { return .missing }
        return .recorded(ratio: snapshot.completionRatio)
    }

    private func snapshot(for date: Date) -> TimerDailySnapshot? {
        store.snapshots.first {
            calendar.isDate(
                Date(millisecondsSince1970: $0.businessDayID.startAtMilliseconds),
                inSameDayAs: date
            )
        }
    }

    private func accessibilityText(for day: CalendarMonthDay, at now: Date) -> String {
        let dateText = day.date.formatted(.dateTime.month().day().locale(Locale(identifier: "zh_CN")))
        switch state(for: day, at: now) {
        case .future:
            return "\(dateText)，未来日期"
        case .missing:
            return "\(dateText)，无记录"
        case .noTasks:
            return "\(dateText)，无任务"
        case let .progress(ratio, _):
            return "\(dateText)，完成度 \(Int((ratio * 100).rounded()))%"
        case .completed:
            return "\(dateText)，完成度 100%"
        }
    }
}

private struct TimerCalendarDayRing: View {
    let day: CalendarMonthDay
    let state: TimerCalendarRingState
    let accessibilityText: String

    var body: some View {
        VStack(spacing: 1) {
            ZStack {
                Circle()
                    .stroke(Color(hex: "#343437"), lineWidth: 2.5)
                progressStroke
                centerMark
            }
            .frame(width: 18, height: 18)
            Text(day.date.formatted(.dateTime.day()))
                .font(.system(size: 7, weight: day.isCurrentBusinessDay ? .bold : .regular).monospacedDigit())
                .foregroundStyle(day.isCurrentBusinessDay ? .white : TimerIslandAppearance.secondaryText)
        }
        .frame(width: 20)
        .opacity(day.isInDisplayedMonth ? 1 : 0)
        .allowsHitTesting(day.isInDisplayedMonth)
        .accessibilityHidden(!day.isInDisplayedMonth)
        .help(accessibilityText)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder
    private var progressStroke: some View {
        switch state {
        case let .progress(ratio, color) where ratio > 0:
            Circle()
                .trim(from: 0, to: ratio)
                .stroke(
                    color == .yellow ? Color(hex: "#FFD60A") : Color(hex: "#1685FF"),
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        case .completed:
            Circle()
                .stroke(Color(hex: "#1685FF"), lineWidth: 2.5)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var centerMark: some View {
        switch state {
        case .completed:
            Image(systemName: "checkmark")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(.white)
        case .noTasks:
            Capsule().fill(.secondary).frame(width: 5, height: 1)
        case .missing:
            Circle().fill(.secondary.opacity(0.65)).frame(width: 2, height: 2)
        default:
            EmptyView()
        }
    }
}

private func formatDuration(_ seconds: Int64) -> String {
    let clamped = max(0, seconds)
    let hours = clamped / 3_600
    let minutes = (clamped % 3_600) / 60
    let remainder = clamped % 60
    return hours > 0
        ? String(format: "%02lld:%02lld:%02lld", hours, minutes, remainder)
        : String(format: "%02lld:%02lld", minutes, remainder)
}

private extension Color {
    init(hex: String) {
        let value = UInt64(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0x4F9DFF
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
