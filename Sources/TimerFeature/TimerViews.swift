import SwiftUI
import PeekerCore
import FunctionCardKit

public struct TimerFeatureDependencies {
    public let repository: any TimerRepository
    public let clock: any Clock
    public let resolver: BusinessDayResolver
    public let eventHub: TemporalEventHub
    public let audio: any AudioNotifying
    public let refreshTime: RefreshTime
    public let statisticsMode: TimerStatisticsMode
    public let onRefreshTimeChanged: @MainActor (RefreshTime) -> Void
    public let onStatisticsModeChanged: @MainActor (TimerStatisticsMode) -> Void

    public init(
        repository: any TimerRepository,
        clock: any Clock,
        resolver: BusinessDayResolver,
        eventHub: TemporalEventHub,
        audio: any AudioNotifying,
        refreshTime: RefreshTime = .midnight,
        statisticsMode: TimerStatisticsMode = .progress,
        onRefreshTimeChanged: @escaping @MainActor (RefreshTime) -> Void = { _ in },
        onStatisticsModeChanged: @escaping @MainActor (TimerStatisticsMode) -> Void = { _ in }
    ) {
        self.repository = repository
        self.clock = clock
        self.resolver = resolver
        self.eventHub = eventHub
        self.audio = audio
        self.refreshTime = refreshTime
        self.statisticsMode = statisticsMode
        self.onRefreshTimeChanged = onRefreshTimeChanged
        self.onStatisticsModeChanged = onStatisticsModeChanged
    }
}

@MainActor
public enum TimerFeatureFactory {
    static let metrics = FunctionCardMetrics(
        compactWidth: 260,
        compactHeight: 32,
        compactLeadingWidth: 144,
        compactTrailingWidth: 72,
        expandedWidth: 800,
        expandedHeight: 460 * 5 / 7
    )

    public static func make(dependencies: TimerFeatureDependencies) throws -> FunctionCardRegistration {
        let store = TimerStore(
            repository: dependencies.repository,
            clock: dependencies.clock,
            resolver: dependencies.resolver,
            eventHub: dependencies.eventHub,
            audio: dependencies.audio,
            refreshTime: dependencies.refreshTime,
            statisticsMode: dependencies.statisticsMode,
            onRefreshTimeChanged: dependencies.onRefreshTimeChanged,
            onStatisticsModeChanged: dependencies.onStatisticsModeChanged
        )
        Task { await store.load() }
        return FunctionCardRegistration(
            id: .timer,
            name: "Timer",
            systemImage: "timer",
            defaultOrder: 0,
            metrics: metrics,
            makeCompactLeadingView: { AnyView(TimerCompactLeadingView(store: store)) },
            makeCompactTrailingView: { AnyView(TimerCompactTrailingView(store: store)) },
            makeExpandedView: { AnyView(TimerExpandedView(store: store)) },
            makeSettingsView: { AnyView(TimerSettingsView(store: store)) }
        )
    }
}

private struct TimerCompactLeadingView: View {
    @Bindable var store: TimerStore

    var body: some View {
        if let task = store.dayState?.summaryTask {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color(hex: task.colorHex))
                    .frame(width: 8, height: 8)
                Text(task.name)
                    .lineLimit(1)
                    .truncationMode(.tail)
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
            if let task = store.dayState?.summaryTask {
                let remainingSeconds = store.remainingSeconds(for: task, at: context.date)
                if task.status == .completed {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Text(formatDuration(remainingSeconds))
                        .monospacedDigit()
                        .foregroundStyle(TimerIslandAppearance.secondaryText)
                        .fixedSize(horizontal: true, vertical: false)
                }
            } else {
                Text("未配置")
                    .foregroundStyle(TimerIslandAppearance.secondaryText)
            }
        }
    }
}

private struct TimerExpandedView: View {
    @Bindable var store: TimerStore

    var body: some View {
        HStack(spacing: 18) {
            Group {
                if let state = store.dayState, !state.visibleTasks.isEmpty {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(state.visibleTasks) { task in
                                TimerTaskRow(store: store, task: task)
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

            Group {
                if store.statisticsMode == .progress {
                    if let tasks = store.dayState?.visibleTasks, !tasks.isEmpty {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            let snapshots = tasks.map { task in
                                TimerProgressSnapshot(
                                    targetSeconds: task.targetSeconds,
                                    remainingSeconds: store.remainingSeconds(for: task, at: context.date)
                                )
                            }
                            if let ratio = TimerProgressMetrics.totalRatio(snapshots) {
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
            .frame(width: 165)
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .overlay(alignment: .bottomLeading) {
            if let error = store.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red).lineLimit(2)
            }
        }
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
                .frame(width: 170, alignment: .leading)
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
            guard let tasks = store.dayState?.visibleTasks else { return .noTasks }
            let progress = tasks.map {
                TimerProgressSnapshot(
                    targetSeconds: $0.targetSeconds,
                    remainingSeconds: store.remainingSeconds(for: $0, at: now)
                )
            }
            return .recorded(ratio: TimerProgressMetrics.totalRatio(progress))
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
        .opacity(day.isInDisplayedMonth ? 1 : 0.28)
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
