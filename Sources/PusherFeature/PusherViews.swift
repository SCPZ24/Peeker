import SwiftUI
import PeekerCore
import FunctionCardKit

public struct PusherFeatureDependencies {
    public let repository: any PusherRepository
    public let clock: any Clock
    public let resolver: BusinessDayResolver
    public let eventHub: TemporalEventHub
    public let carryIncomplete: Bool
    public let refreshTime: RefreshTime
    public let setPopoverPresented: @MainActor (Bool) -> Void
    public let setDragging: @MainActor (Bool) -> Void
    public let setEditingText: @MainActor (Bool) -> Void
    public let onRefreshTimeChanged: @MainActor (RefreshTime) -> Void
    public let onCarryIncompleteChanged: @MainActor (Bool) -> Void

    public init(
        repository: any PusherRepository,
        clock: any Clock,
        resolver: BusinessDayResolver,
        eventHub: TemporalEventHub,
        carryIncomplete: Bool = true,
        refreshTime: RefreshTime = .midnight,
        setPopoverPresented: @escaping @MainActor (Bool) -> Void,
        setDragging: @escaping @MainActor (Bool) -> Void,
        setEditingText: @escaping @MainActor (Bool) -> Void,
        onRefreshTimeChanged: @escaping @MainActor (RefreshTime) -> Void = { _ in },
        onCarryIncompleteChanged: @escaping @MainActor (Bool) -> Void = { _ in }
    ) {
        self.repository = repository
        self.clock = clock
        self.resolver = resolver
        self.eventHub = eventHub
        self.carryIncomplete = carryIncomplete
        self.refreshTime = refreshTime
        self.setPopoverPresented = setPopoverPresented
        self.setDragging = setDragging
        self.setEditingText = setEditingText
        self.onRefreshTimeChanged = onRefreshTimeChanged
        self.onCarryIncompleteChanged = onCarryIncompleteChanged
    }
}

@MainActor
public enum PusherFeatureFactory {
    public static func make(dependencies: PusherFeatureDependencies) throws -> FunctionCardRegistration {
        let store = PusherStore(
            repository: dependencies.repository,
            clock: dependencies.clock,
            resolver: dependencies.resolver,
            eventHub: dependencies.eventHub,
            carryIncomplete: dependencies.carryIncomplete,
            refreshTime: dependencies.refreshTime,
            onRefreshTimeChanged: dependencies.onRefreshTimeChanged,
            onCarryIncompleteChanged: dependencies.onCarryIncompleteChanged
        )
        Task { await store.load() }
        return FunctionCardRegistration(
            id: .pusher,
            name: "Pusher",
            systemImage: "rectangle.3.group.fill",
            defaultOrder: 1,
            metrics: FunctionCardMetrics(
                compactWidth: 340,
                compactHeight: 32,
                compactLeadingWidth: 128,
                compactTrailingWidth: 184,
                expandedWidth: 960,
                expandedHeight: 520
            ),
            makeCompactLeadingView: { AnyView(PusherCompactLeadingView(store: store)) },
            makeCompactTrailingView: { AnyView(PusherCompactTrailingView(store: store)) },
            makeExpandedView: {
                AnyView(
                    PusherExpandedView(
                        store: store,
                        setPopoverPresented: dependencies.setPopoverPresented,
                        setDragging: dependencies.setDragging,
                        setEditingText: dependencies.setEditingText
                    )
                )
            },
            makeSettingsView: { AnyView(PusherSettingsView(store: store)) }
        )
    }
}

private struct PusherCompactLeadingView: View {
    @Bindable var store: PusherStore

    var body: some View {
        let summary = store.board?.compactSummary ?? .zero
        HStack(spacing: 6) {
            Label("\(summary.planned)", systemImage: "circle.dashed")
                .foregroundStyle(.orange)
            Label("\(summary.done)", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        }
        .monospacedDigit()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Planned \(summary.planned)，Done \(summary.done)")
    }
}

private struct PusherCompactTrailingView: View {
    @Bindable var store: PusherStore

    var body: some View {
        let summary = store.board?.compactSummary ?? .zero
        HStack(spacing: 6) {
            Label("\(summary.processing)", systemImage: "arrow.forward.circle.fill")
                .foregroundStyle(.blue)
            PusherCompactUrgencyCount(count: summary.urgentProcessing, color: .red)
            PusherCompactUrgencyCount(count: summary.progressProcessing, color: .blue)
            PusherCompactUrgencyCount(count: summary.planningProcessing, color: .pink)
        }
        .monospacedDigit()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Processing \(summary.processing)，紧急 \(summary.urgentProcessing)，推进 \(summary.progressProcessing)，规划 \(summary.planningProcessing)"
        )
    }
}

private struct PusherCompactUrgencyCount: View {
    let count: Int
    let color: Color

    var body: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
            Text("\(count)")
        }
        .foregroundStyle(color)
    }
}

private enum PusherPopover: Identifiable {
    case create
    case edit(PusherTask)
    case calendar

    var id: String {
        switch self {
        case .create: "create"
        case let .edit(task): "edit-\(task.id.uuidString)"
        case .calendar: "calendar"
        }
    }
}

private struct PusherExpandedView: View {
    @Bindable var store: PusherStore
    let setPopoverPresented: @MainActor (Bool) -> Void
    let setDragging: @MainActor (Bool) -> Void
    let setEditingText: @MainActor (Bool) -> Void
    @State private var popover: PusherPopover?

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                PusherColumn(
                    title: "Planned",
                    status: .planned,
                    tasks: store.board?.tasks(in: .planned) ?? [],
                    store: store,
                    edit: { popover = .edit($0) },
                    setDragging: setDragging
                )
                PusherColumn(
                    title: "Processing",
                    status: .processing,
                    tasks: store.board?.tasks(in: .processing) ?? [],
                    store: store,
                    edit: { popover = .edit($0) },
                    setDragging: setDragging
                )
                PusherColumn(
                    title: "Done",
                    status: .done,
                    tasks: store.board?.tasks(in: .done) ?? [],
                    store: store,
                    edit: { popover = .edit($0) },
                    setDragging: setDragging
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(spacing: 12) {
                Button {
                    popover = .create
                } label: {
                    Label("新增", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    popover = .calendar
                } label: {
                    Label("日历", systemImage: "calendar")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .frame(width: 140)
        }
        .overlay(alignment: .bottomLeading) {
            if let error = store.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red).lineLimit(2)
            }
        }
        .onChange(of: popover?.id) { _, newValue in
            setPopoverPresented(newValue != nil)
        }
        .popover(item: $popover, arrowEdge: .bottom) { item in
            Group {
                switch item {
                case .create:
                    PusherEditor(
                        title: "新增任务",
                        task: nil,
                        setEditingText: setEditingText,
                        save: { title, urgency, repeats in
                            if await store.create(title: title, urgency: urgency, repeatsDaily: repeats) {
                                popover = nil
                            }
                        }
                    )
                case let .edit(task):
                    PusherEditor(
                        title: "编辑任务",
                        task: task,
                        setEditingText: setEditingText,
                        save: { title, urgency, repeats in
                            if await store.update(
                                taskID: task.id,
                                title: title,
                                urgency: urgency,
                                repeatsDaily: repeats
                            ) { popover = nil }
                        },
                        delete: {
                            if await store.delete(taskID: task.id) { popover = nil }
                        }
                    )
                case .calendar:
                    PusherCalendarView(store: store)
                }
            }
            .pusherPopoverAppearance()
        }
    }
}

private struct PusherColumn: View {
    let title: String
    let status: PusherStatus
    let tasks: [PusherTask]
    @Bindable var store: PusherStore
    let edit: (PusherTask) -> Void
    let setDragging: @MainActor (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Text("\(tasks.count)").foregroundStyle(.secondary).monospacedDigit()
            }
            if tasks.isEmpty {
                Text("拖到这里")
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                ScrollView {
                    LazyVStack(spacing: 7) {
                        ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                            PusherTaskCard(task: task, edit: { edit(task) })
                                .draggable(task.id.uuidString) {
                                    PusherTaskCard(task: task, edit: {})
                                        .frame(width: 180)
                                        .onAppear { setDragging(true) }
                                        .onDisappear { setDragging(false) }
                                }
                                .dropDestination(for: String.self) { values, _ in
                                    guard let raw = values.first, let id = UUID(uuidString: raw) else { return false }
                                    Task { _ = await store.move(taskID: id, to: status, at: index) }
                                    setDragging(false)
                                    return true
                                }
                        }
                    }
                }
            }
        }
        .padding(10)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
        .dropDestination(for: String.self) { values, _ in
            guard let raw = values.first, let id = UUID(uuidString: raw) else { return false }
            Task { _ = await store.move(taskID: id, to: status, at: tasks.count) }
            setDragging(false)
            return true
        }
    }
}

private struct PusherTaskCard: View {
    let task: PusherTask
    let edit: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(task.title).lineLimit(2)
            Spacer(minLength: 4)
            if hovering {
                Button("编辑", systemImage: "pencil", action: edit)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
            }
        }
        .padding(9)
        .background(color.opacity(0.16), in: RoundedRectangle(cornerRadius: 10))
        .onHover { hovering = $0 }
    }

    private var color: Color {
        switch task.urgency {
        case .urgent: .red
        case .progress: .blue
        case .planning: .green
        }
    }
}

private struct PusherEditor: View {
    let title: String
    let task: PusherTask?
    let setEditingText: @MainActor (Bool) -> Void
    let save: (String, PusherUrgency, Bool) async -> Void
    let delete: (() async -> Void)?
    @State private var name: String
    @State private var urgency: PusherUrgency
    @State private var repeatsDaily: Bool
    @State private var confirmsDelete = false
    @Environment(\.dismiss) private var dismiss

    init(
        title: String,
        task: PusherTask?,
        setEditingText: @escaping @MainActor (Bool) -> Void,
        save: @escaping (String, PusherUrgency, Bool) async -> Void,
        delete: (() async -> Void)? = nil
    ) {
        self.title = title
        self.task = task
        self.setEditingText = setEditingText
        self.save = save
        self.delete = delete
        _name = State(initialValue: task?.title ?? "")
        _urgency = State(initialValue: task?.urgency ?? .planning)
        _repeatsDaily = State(initialValue: task?.repeatsDaily ?? false)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.headline)
                .foregroundStyle(Color.secondary)
            TextField(
                "任务名称",
                text: $name,
                prompt: Text("任务名称").foregroundStyle(Color.secondary)
            )
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .foregroundStyle(Color.primary)
                .accessibilityLabel("任务名称")
                .onAppear { setEditingText(true) }
                .onDisappear { setEditingText(false) }
            Picker("急迫度", selection: $urgency) {
                Text("紧急").tag(PusherUrgency.urgent)
                Text("推进").tag(PusherUrgency.progress)
                Text("规划").tag(PusherUrgency.planning)
            }
            .foregroundStyle(Color.secondary)
            Toggle("每日刷新", isOn: $repeatsDaily)
                .foregroundStyle(Color.secondary)
            HStack {
                if delete != nil {
                    Button("删除", role: .destructive) { confirmsDelete = true }
                }
                Spacer()
                Button("取消") { dismiss() }
                Button("确认") {
                    Task { await save(name, urgency, repeatsDaily) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(18)
        .frame(width: 340)
        .confirmationDialog("确认删除这个任务？", isPresented: $confirmsDelete) {
            Button("删除", role: .destructive) {
                if let delete { Task { await delete() } }
            }
        }
    }
}

private struct PusherCalendarView: View {
    @Bindable var store: PusherStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("完成日历").font(.headline)
            if store.snapshots.isEmpty {
                ContentUnavailableView("暂无历史", systemImage: "calendar")
            } else {
                ForEach(Array(store.snapshots.enumerated()), id: \.offset) { _, snapshot in
                    HStack {
                        Text(Date(millisecondsSince1970: snapshot.businessDayID.startAtMilliseconds), style: .date)
                        Spacer()
                        Text("完成 \(snapshot.doneCount)")
                    }
                }
            }
        }
        .padding(18)
        .frame(width: 320, height: 260)
        .foregroundStyle(Color.primary)
    }
}

private struct PusherPopoverAppearance: ViewModifier {
    func body(content: Content) -> some View {
        content
            .preferredColorScheme(.light)
            .environment(\.colorScheme, .light)
            .foregroundStyle(Color.primary)
            .tint(.accentColor)
    }
}

private extension View {
    func pusherPopoverAppearance() -> some View {
        modifier(PusherPopoverAppearance())
    }
}

private struct PusherSettingsView: View {
    @Bindable var store: PusherStore

    var body: some View {
        Form {
            Toggle("顺延单次未完成任务", isOn: carryBinding)
            DatePicker("业务日刷新时间", selection: refreshBinding, displayedComponents: .hourAndMinute)
            Text("每日任务始终在新业务日重建，不受顺延开关影响。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }

    private var refreshBinding: Binding<Date> {
        Binding {
            Calendar.current.date(from: DateComponents(hour: store.refreshTime.hour, minute: store.refreshTime.minute)) ?? .now
        } set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            guard let hour = parts.hour, let minute = parts.minute,
                  let value = try? RefreshTime(hour: hour, minute: minute) else { return }
            Task { await store.updateRefreshTime(value) }
        }
    }

    private var carryBinding: Binding<Bool> {
        Binding(
            get: { store.carryIncomplete },
            set: { store.updateCarryIncomplete($0) }
        )
    }
}
