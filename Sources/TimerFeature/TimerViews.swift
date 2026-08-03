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
            metrics: FunctionCardMetrics(
                compactWidth: 340,
                compactHeight: 38,
                expandedWidth: 760,
                expandedHeight: 420
            ),
            makeCompactView: { AnyView(TimerCompactView(store: store)) },
            makeExpandedView: { AnyView(TimerExpandedView(store: store)) },
            makeSettingsView: { AnyView(TimerSettingsView(store: store)) }
        )
    }
}

private struct TimerCompactView: View {
    @Bindable var store: TimerStore

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            if let task = store.dayState?.summaryTask {
                HStack(spacing: 8) {
                    Circle().fill(Color(hex: task.colorHex)).frame(width: 8, height: 8)
                    Text(task.name).lineLimit(1)
                    Spacer(minLength: 6)
                    if task.status == .completed {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Text(formatDuration(store.remainingSeconds(for: task, at: context.date)))
                            .monospacedDigit()
                    }
                }
            } else {
                Label("Timer 尚未配置", systemImage: "timer")
                    .foregroundStyle(.secondary)
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
                    ContentUnavailableView(
                        "还没有计时目标",
                        systemImage: "timer",
                        description: Text("请在 Timer 设置中添加每日目标。")
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider().overlay(.white.opacity(0.2))

            VStack(spacing: 14) {
                if store.statisticsMode == .progress, let ratio = store.dayState?.completionRatio {
                    Gauge(value: ratio) {
                        Text("今日完成度")
                    } currentValueLabel: {
                        Text(ratio, format: .percent.precision(.fractionLength(0)))
                    }
                    .gaugeStyle(.accessoryCircularCapacity)
                    .scaleEffect(1.8)
                    .frame(height: 150)
                } else if store.statisticsMode == .progress {
                    Text("添加目标后显示完成度")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                } else {
                    TimerHeatmap(snapshots: store.snapshots)
                }
                Spacer()
                Text("按真实时间累计")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 165)
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
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(hex: task.colorHex))
                    .frame(width: 6, height: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text(task.name).font(.headline).lineLimit(1)
                    Text(task.status == .completed ? "已完成" : formatDuration(store.remainingSeconds(for: task, at: context.date)))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(task.status == .completed ? .green : .secondary)
                }
                Spacer()
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
    @State private var minutes = 30
    @State private var colorHex = "#4F9DFF"
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

                HStack {
                    TextField("目标名称", text: $name)
                    Stepper("\(minutes) 分钟", value: $minutes, in: 1...1_439)
                    Button("添加") {
                        let submitted = name
                        name = ""
                        Task {
                            await store.createTemplate(
                                name: submitted,
                                targetSeconds: Int64(minutes * 60),
                                colorHex: colorHex
                            )
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
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
    @State private var seconds: Int
    @State private var colorHex: String
    @Environment(\.dismiss) private var dismiss

    init(template: TimerTemplate, save: @escaping (TimerTemplate) async -> Void) {
        self.template = template
        self.save = save
        _name = State(initialValue: template.name)
        _seconds = State(initialValue: Int(template.targetSeconds))
        _colorHex = State(initialValue: template.colorHex)
    }

    var body: some View {
        Form {
            TextField("名称", text: $name)
            Stepper("目标 \(formatDuration(Int64(seconds)))", value: $seconds, in: 1...86_399)
            TextField("颜色（#RRGGBB）", text: $colorHex)
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("保存") {
                    var updated = template
                    updated.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    updated.targetSeconds = Int64(seconds)
                    updated.colorHex = colorHex
                    updated.updatedAtMilliseconds = Date().millisecondsSince1970
                    Task { await save(updated) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(18)
        .frame(width: 380)
    }
}

private struct TimerHeatmap: View {
    let snapshots: [TimerDailySnapshot]
    private let columns = Array(repeating: GridItem(.fixed(18), spacing: 4), count: 7)

    var body: some View {
        VStack(spacing: 8) {
            Text("近期完成度").font(.caption).foregroundStyle(.secondary)
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Array(snapshots.suffix(35).enumerated()), id: \.offset) { _, snapshot in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.green.opacity(max(0.08, snapshot.completionRatio ?? 0)))
                        .frame(width: 18, height: 18)
                        .help(Date(millisecondsSince1970: snapshot.businessDayID.startAtMilliseconds).formatted(date: .abbreviated, time: .omitted))
                }
            }
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
