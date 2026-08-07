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
    static let metrics = FunctionCardMetrics(
        compactWidth: 340,
        compactHeight: 32,
        compactLeadingWidth: 128,
        compactTrailingWidth: 184,
        expandedWidth: 960,
        expandedHeight: 520 * 5 / 7
    )

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
            metrics: metrics,
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
            ForEach(summary.processingStatusCounts) { status in
                PusherCompactUrgencyCount(
                    count: status.count,
                    color: compactColor(for: status.urgency)
                )
            }
        }
        .monospacedDigit()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "紧急 \(summary.urgentProcessing)，推进 \(summary.progressProcessing)，规划 \(summary.planningProcessing)"
        )
    }

    private func compactColor(for urgency: PusherUrgency) -> Color {
        switch urgency {
        case .urgent: .red
        case .progress: .blue
        case .planning: .yellow
        }
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
    @State private var dragSessionNonce = UUID()
    @State private var dragLayoutModel = PusherDragLayoutModel()

    var body: some View {
        HStack(spacing: 12) {
            PusherAppKitDropContainer(
                layoutModel: dragLayoutModel,
                sessionNonce: dragSessionNonce,
                board: store.board,
                isEnabled: !store.isMovePending,
                performDrop: performDrop
            ) {
                HStack(spacing: 10) {
                    PusherColumn(
                        title: "Planned",
                        status: .planned,
                        tasks: store.board?.tasks(in: .planned) ?? [],
                        store: store,
                        dragSessionNonce: dragSessionNonce,
                        dragLayoutModel: dragLayoutModel,
                        edit: { popover = .edit($0) }
                    )
                    PusherColumn(
                        title: "Processing",
                        status: .processing,
                        tasks: store.board?.tasks(in: .processing) ?? [],
                        store: store,
                        dragSessionNonce: dragSessionNonce,
                        dragLayoutModel: dragLayoutModel,
                        edit: { popover = .edit($0) }
                    )
                    PusherColumn(
                        title: "Done",
                        status: .done,
                        tasks: store.board?.tasks(in: .done) ?? [],
                        store: store,
                        dragSessionNonce: dragSessionNonce,
                        dragLayoutModel: dragLayoutModel,
                        edit: { popover = .edit($0) }
                    )
                }
                .coordinateSpace(name: PusherDragLayoutModel.coordinateSpaceName)
                .onDragSessionUpdated(handleDragSession)
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
                .disabled(store.isMovePending)

                Button {
                    popover = .calendar
                } label: {
                    Label("日历", systemImage: "calendar")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(store.isMovePending)
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
        .onDisappear {
            dragLayoutModel.clearActiveTarget()
            setDragging(false)
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

    private func handleDragSession(_ session: DragSession) {
        switch session.phase {
        case .initial, .active:
            setDragging(true)
        case .ended, .dataTransferCompleted:
            dragLayoutModel.clearActiveTarget()
            setDragging(false)
        @unknown default:
            dragLayoutModel.clearActiveTarget()
            setDragging(false)
        }
    }

    private func performDrop(_ target: PusherResolvedDropTarget) -> Bool {
        var preparation = PusherMovePreparation.rejected
        withAnimation(.easeInOut(duration: 0.12)) {
            preparation = store.beginMove(
                taskID: target.taskID,
                to: target.status,
                insertionIndex: target.insertionIndex
            )
        }
        switch preparation {
        case .rejected:
            return false
        case .unchanged:
            return true
        case let .started(transaction):
            Task { await store.persistMove(transaction) }
            return true
        }
    }
}

private struct PusherColumn: View {
    let title: String
    let status: PusherStatus
    let tasks: [PusherTask]
    @Bindable var store: PusherStore
    let dragSessionNonce: UUID
    let dragLayoutModel: PusherDragLayoutModel
    let edit: (PusherTask) -> Void
    @State private var taskFrames: [UUID: CGRect] = [:]
    @State private var columnFrame = CGRect.zero

    private var coordinateSpaceName: String { "pusher-column-\(status.rawValue)" }

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
                        ForEach(Array(tasks.enumerated()), id: \.element.id) { _, task in
                            PusherTaskCard(task: task, edit: { edit(task) })
                                .background {
                                    GeometryReader { geometry in
                                        Color.clear.preference(
                                            key: PusherTaskFramePreferenceKey.self,
                                            value: [
                                                task.id: geometry.frame(
                                                    in: .named(coordinateSpaceName)
                                                )
                                            ]
                                        )
                                    }
                                }
                                .allowsHitTesting(!store.isMovePending)
                                .draggable(
                                    PusherDragEnvelope(
                                        sessionNonce: dragSessionNonce,
                                        businessDayStart: task.businessDayID.startAtMilliseconds,
                                        taskID: task.id
                                    ).rawValue
                                ) {
                                    PusherTaskCard(task: task, edit: {})
                                        .frame(width: 180)
                                }
                                .dragConfiguration(moveOnlyDragConfiguration)
                        }
                    }
                }
            }
        }
        .padding(10)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
        .coordinateSpace(name: coordinateSpaceName)
        .onPreferenceChange(PusherTaskFramePreferenceKey.self) { frames in
            taskFrames = frames
            publishGeometry()
        }
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .named(PusherDragLayoutModel.coordinateSpaceName))
        } action: { frame in
            columnFrame = frame
            publishGeometry()
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(isDropTargeted ? Color.blue : .clear, lineWidth: 2)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .topLeading) {
            if let target = activeDropTarget {
                Rectangle()
                    .fill(Color.blue)
                    .frame(width: max(0, columnFrame.width - 20), height: 2)
                    .offset(
                        x: 10,
                        y: max(0, target.landingFrame.minY - columnFrame.minY)
                    )
                    .allowsHitTesting(false)
            }
        }
        .accessibilityValue(accessibilityDropValue)
    }

    private var activeDropTarget: PusherResolvedDropTarget? {
        guard dragLayoutModel.activeTarget?.status == status else { return nil }
        return dragLayoutModel.activeTarget
    }

    private var moveOnlyDragConfiguration: DragConfiguration {
        DragConfiguration(
            operationsWithinApp: .init(
                allowCopy: false,
                allowMove: true,
                allowDelete: false
            ),
            operationsOutsideApp: .init(allowCopy: false)
        )
    }

    private var isDropTargeted: Bool { activeDropTarget != nil }

    private var accessibilityDropValue: String {
        guard let activeDropTarget else { return "" }
        return "将移动到 \(title)，第 \(activeDropTarget.insertionIndex + 1) 个位置"
    }

    private func publishGeometry() {
        guard !columnFrame.isEmpty else { return }
        let rows = tasks.enumerated().compactMap { index, task -> PusherDropRow? in
            guard let frame = taskFrames[task.id] else { return nil }
            return PusherDropRow(taskIndex: index, frame: frame)
        }
        dragLayoutModel.updateColumn(
            PusherDropColumnGeometry(
                status: status,
                frame: columnFrame,
                rows: rows,
                taskCount: tasks.count
            )
        )
    }
}

private struct PusherTaskFramePreferenceKey: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
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
    @State private var displayedMonth = Date.now
    private var calendar: Calendar { .autoupdatingCurrent }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text("完成日历").font(.headline)
                Spacer()
                Button { moveMonth(-1) } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.plain)
                Text(displayedMonth.formatted(.dateTime.year().month(.wide)))
                    .font(.subheadline.weight(.semibold))
                    .frame(minWidth: 96)
                Button { moveMonth(1) } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(.plain)
            }

            HStack(spacing: 4) {
                ForEach(Array(rotatedWeekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            let currentStart = store.board?.businessDay.start ?? Date.now
            let grid = CalendarMonthGrid(
                displaying: displayedMonth,
                currentBusinessDayStart: currentStart,
                calendar: calendar
            )
            VStack(spacing: 5) {
                ForEach(Array(grid.weeks.enumerated()), id: \.offset) { _, week in
                    HStack(spacing: 4) {
                        ForEach(week) { day in
                            PusherCalendarDayCell(
                                day: day,
                                value: value(for: day),
                                accessibilityText: accessibilityText(for: day)
                            )
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(width: 360, height: 320)
        .foregroundStyle(Color.primary)
        .task(id: monthTaskID) {
            await store.loadSnapshots(for: displayedMonth)
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

    private func value(for day: CalendarMonthDay) -> PusherCalendarValue? {
        if day.isCurrentBusinessDay, let summary = store.board?.summary {
            return PusherCalendarValue(
                doneCount: summary.done,
                totalCount: summary.planned + summary.processing + summary.done
            )
        }
        guard !day.isFutureBusinessDay,
              let snapshot = store.snapshots.first(where: {
                  calendar.isDate(
                      Date(millisecondsSince1970: $0.businessDayID.startAtMilliseconds),
                      inSameDayAs: day.date
                  )
              }) else { return nil }
        return PusherCalendarValue(doneCount: snapshot.doneCount, totalCount: snapshot.totalCount)
    }

    private func accessibilityText(for day: CalendarMonthDay) -> String {
        let dateText = day.date.formatted(.dateTime.month().day().locale(Locale(identifier: "zh_CN")))
        if day.isFutureBusinessDay { return "\(dateText)，未来日期" }
        guard let value = value(for: day) else { return "\(dateText)，无记录" }
        return "\(dateText)，完成 \(value.doneCount) 项，共 \(value.totalCount) 项"
    }
}

private struct PusherCalendarValue {
    let doneCount: Int
    let totalCount: Int
}

private struct PusherCalendarDayCell: View {
    let day: CalendarMonthDay
    let value: PusherCalendarValue?
    let accessibilityText: String

    var body: some View {
        VStack(spacing: 3) {
            Text(day.date.formatted(.dateTime.day()))
                .font(.caption2.weight(day.isCurrentBusinessDay ? .bold : .regular).monospacedDigit())
            Text(valueText)
                .font(.system(size: 9, weight: .semibold).monospacedDigit())
                .foregroundStyle(value == nil ? Color.secondary : Color.primary)
        }
        .frame(maxWidth: .infinity, minHeight: 30)
        .padding(.vertical, 3)
        .background(backgroundColor, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(day.isCurrentBusinessDay ? Color.accentColor : Color.clear, lineWidth: 1.5)
        }
        .opacity(day.isInDisplayedMonth ? 1 : 0.32)
        .help(accessibilityText)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var valueText: String {
        guard let value else { return day.isFutureBusinessDay ? " " : "—" }
        return "\(value.doneCount)/\(value.totalCount)"
    }

    private var backgroundColor: Color {
        guard let value else { return Color.gray.opacity(0.08) }
        guard let opacity = PusherCalendarMetrics.greenOpacity(
            doneCount: value.doneCount,
            totalCount: value.totalCount
        ), opacity > 0 else {
            return Color.gray.opacity(0.12)
        }
        return Color.green.opacity(opacity)
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
