import AppKit
import FunctionCardKit
import PeekerCore
import SwiftUI

@MainActor
public enum SchedulerFeatureFactory {
    public static let metrics = FunctionCardMetrics(
        compactWidth: 220, compactHeight: 8, compactLeadingWidth: 0, compactTrailingWidth: 0,
        expandedWidth: 1120, expandedHeight: 700
    )

    public static func make(
        store: SchedulerStore,
        setPopoverPresented: @escaping @MainActor (Bool) -> Void = { _ in }
    ) -> FunctionCardRegistration {
        Task { await store.load() }
        return FunctionCardRegistration(
            id: .scheduler, name: "Scheduler", systemImage: "calendar",
            defaultOrder: 2, introducedConfigurationVersion: 2, metrics: metrics,
            makeExpandedView: {
                AnyView(SchedulerWeekView(
                    store: store,
                    setPopoverPresented: setPopoverPresented
                ))
            },
            makeSettingsView: { AnyView(SchedulerSettingsView(store: store)) }
        )
    }
}

private struct SchedulerWeekView: View {
    @Bindable var store: SchedulerStore
    let setPopoverPresented: @MainActor (Bool) -> Void
    @Environment(\.nativePresentationColorScheme) private var nativeColorScheme
    @Environment(\.isVisualActivityEnabled) private var isVisible
    @State private var draft: SchedulerEvent?
    @State private var editorForm: SchedulerEditorDraft?
    @State private var editorAnchor = "new"
    @State private var needsRefresh = false
    @State private var editingExisting = false
    @State private var pendingDiscardAction: (() -> Void)?
    @State private var occurrenceKey: String?
    @State private var mutationScope: SchedulerMutationScope?
    @State private var scopeOccurrence: SchedulerOccurrence?
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var moreDay: Int?
    @State private var dayList: Int?
    @State private var placements: [SchedulerEventPlacement] = []
    private let hourHeight: CGFloat = 52
    private var calendar: Calendar { .current }

    var body: some View {
        VStack(spacing: 8) {
            header
            dayTitles
            allDayArea
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    ZStack(alignment: .topLeading) {
                        timeGrid
                        timedEvents
                        currentTimeLine
                    }
                    .frame(height: hourHeight * 24)
                }
                .onAppear { proxy.scrollTo(initialHour, anchor: .top) }
            }
        }
        .onAppear { updatePlacements() }
        .onChange(of: store.occurrences) { _, _ in updatePlacements() }
        .onChange(of: store.visibleFrom) { _, _ in updatePlacements() }
        .onChange(of: draft?.id) { _, value in setPopoverPresented(value != nil) }
        .onDisappear { setPopoverPresented(false) }
        .confirmationDialog(L10n.text("选择重复日程的操作范围"), isPresented: Binding(
            get: { scopeOccurrence != nil }, set: { if !$0 { scopeOccurrence = nil } }
        ), titleVisibility: .visible) {
            if let occurrence = scopeOccurrence {
                Button(L10n.text("仅本次")) { open(occurrence, scope: .this) }
                Button(L10n.text("本次及之后")) { open(occurrence, scope: .future) }
                Button(L10n.text("整个系列（清除例外记录）")) { open(occurrence, scope: .all) }
            }
            Button(L10n.text("取消"), role: .cancel) { scopeOccurrence = nil }
        }
        .confirmationDialog(L10n.text("放弃未保存的更改？"), isPresented: Binding(
            get: { pendingDiscardAction != nil }, set: { if !$0 { pendingDiscardAction = nil } }
        ), titleVisibility: .visible) {
            Button(L10n.text("放弃更改"), role: .destructive) {
                let action = pendingDiscardAction
                pendingDiscardAction = nil
                action?()
            }
            Button(L10n.text("取消"), role: .cancel) { pendingDiscardAction = nil }
        }
        .overlay {
            if store.isLoading { ProgressView() }
        }
        .overlay(alignment: .bottom) {
            if let error = store.localizedErrorMessage {
                Text(error).font(.callout).foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder private var editorContent: some View {
        if let event = draft, let editorForm {
            SchedulerEventEditor(
                form: editorForm,
                errorMessage: editingExisting && !store.events.contains(where: { $0.id == event.id }) && !needsRefresh ? L10n.text("日程已被删除；可复制保留输入。") : errorMessage,
                isSaving: isSaving,
                canSave: !needsRefresh && (!editingExisting || store.events.contains(where: { $0.id == event.id })),
                onCancel: { afterDiscarding { draft = nil; self.editorForm = nil } },
                onSave: { updated in
                    guard !isSaving else { return }
                    isSaving = true
                    Task {
                        defer { isSaving = false }
                        do {
                            if editingExisting {
                                _ = try await store.update(updated, occurrenceKey: occurrenceKey, scope: mutationScope)
                            } else {
                                _ = try await store.create(updated)
                            }
                            draft = nil
                            self.editorForm = nil
                        } catch {
                            needsRefresh = error is SchedulerPostCommitRefreshError
                            errorMessage = needsRefresh ? L10n.text("更改已保存，请刷新视图；不要重复提交。") : L10n.text("保存失败：%1$@", String(describing: error.localizedDescription))
                        }
                    }
                },
                onDelete: store.events.contains(where: { $0.id == event.id }) ? {
                    guard !isSaving else { return }
                    isSaving = true
                    Task {
                        defer { isSaving = false }
                        do {
                            _ = try await store.delete(id: event.id, occurrenceKey: occurrenceKey, scope: mutationScope)
                            draft = nil
                            self.editorForm = nil
                        } catch {
                            needsRefresh = error is SchedulerPostCommitRefreshError
                            errorMessage = needsRefresh ? L10n.text("更改已保存，请刷新视图；不要重复提交。") : L10n.text("删除失败：%1$@", String(describing: error.localizedDescription))
                        }
                    }
                } : nil
            )
            .environment(\.colorScheme, nativeColorScheme)
            .foregroundStyle(.primary)
            if needsRefresh {
                Button(L10n.text("刷新")) {
                    Task {
                        do {
                            try await store.refreshAfterCommit()
                            needsRefresh = false; draft = nil; self.editorForm = nil
                        } catch { errorMessage = error.localizedDescription }
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack {
            Button { shiftWeek(-1) } label: { Image(systemName: "chevron.left") }
            Button(L10n.text("今天")) { navigateToWeek(Date()) }
            Button { shiftWeek(1) } label: { Image(systemName: "chevron.right") }
            Spacer()
            Text(store.visibleFrom.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, locale: AppLanguageContext.shared.locale)))
                .font(.headline)
            Spacer()
            Button(L10n.text("新建"), systemImage: "plus") { createTimed(day: 0, minute: 9 * 60) }
                .popover(isPresented: editorBinding("new")) { editorContent }
        }
        .buttonStyle(.borderless)
    }

    private var dayTitles: some View {
        HStack(spacing: 1) {
            Color.clear.frame(width: 42, height: 22)
            ForEach(0..<7, id: \.self) { day in
                Button { dayList = day } label: {
                Text(date(day).formatted(.dateTime.weekday(.abbreviated).day().locale(AppLanguageContext.shared.locale)))
                    .font(.system(size: 12, weight: calendar.isDateInToday(date(day)) ? .semibold : .regular))
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .popover(isPresented: Binding(get: { dayList == day }, set: { if !$0 { dayList = nil } })) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(store.occurrences.filter { occurrence in
                                allDayOccurrences(day: day).contains(where: { $0.id == occurrence.id }) || placements.contains(where: { $0.segment.day == day && $0.segment.occurrence.id == occurrence.id })
                            }) { occurrence in
                                Button(occurrence.title) { dayList = nil; editorAnchor = "new"; select(occurrence) }
                            }
                        }.padding()
                    }.frame(width: 300, height: 260)
                    .environment(\.colorScheme, nativeColorScheme)
                }
            }
        }
        .frame(height: 24)
    }

    private var allDayArea: some View {
        let rowCount = min(2, (0..<7).map { allDayOccurrences(day: $0).count }.max() ?? 0)
        return HStack(alignment: .top, spacing: 1) {
            Text(L10n.text("全天")).font(.system(size: 11)).frame(width: 42)
            ForEach(0..<7, id: \.self) { day in
                let events = allDayOccurrences(day: day)
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(events.prefix(SchedulerAllDayLayout.visibleCount(events.count))) { occurrence in
                        eventButton(occurrence, anchor: "\(occurrence.id):\(day)")
                            .frame(height: 21)
                    }
                    if events.count > 2 {
                        Button("+\(events.count - 1)") { moreDay = day }
                            .frame(height: 21)
                            .buttonStyle(.plain)
                            .popover(isPresented: Binding(
                                get: { moreDay == day }, set: { if !$0 { moreDay = nil } }
                            )) {
                                ScrollView {
                                    VStack(alignment: .leading, spacing: 8) {
                                        ForEach(events) { occurrence in
                                            Button(occurrence.title) { moreDay = nil; editorAnchor = "new"; select(occurrence) }
                                                .buttonStyle(.borderless)
                                        }
                                    }.padding()
                                }.frame(width: 280, height: min(320, CGFloat(events.count * 32)))
                                .environment(\.colorScheme, nativeColorScheme)
                            }
                    }
                }
                .frame(maxWidth: .infinity, minHeight: CGFloat(max(1, rowCount) * 24), alignment: .topLeading)
                .background {
                    Color.clear.contentShape(Rectangle()).onTapGesture(count: 2) { createAllDay(day: day) }
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var timeGrid: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                ForEach(0..<24, id: \.self) { hour in
                    Text(String(format: "%02d:00", hour)).font(.system(size: 11)).foregroundStyle(.secondary)
                        .frame(width: 42, height: hourHeight, alignment: .top).id(hour)
                }
            }
            ForEach(0..<7, id: \.self) { day in
                VStack(spacing: 0) {
                    ForEach(0..<24, id: \.self) { hour in
                        Color.clear.frame(height: hourHeight)
                            .overlay(alignment: .top) { Divider().opacity(0.2).allowsHitTesting(false) }
                            .contentShape(Rectangle())
                            .gesture(SpatialTapGesture(count: 2).onEnded { value in
                                let quarter = min(3, max(0, Int(value.location.y / (hourHeight / 4))))
                                createTimed(day: day, minute: hour * 60 + quarter * 15)
                            })
                    }
                }.frame(maxWidth: .infinity)
            }
        }
    }

    private var timedEvents: some View {
        GeometryReader { geometry in
            let dayWidth = max(0, geometry.size.width - 42) / 7
            ForEach(placements) { placement in
                let segment = placement.segment
                eventButton(segment.occurrence, anchor: segment.id)
                    .frame(width: max(1, dayWidth / CGFloat(placement.columnCount) - 3),
                           height: min(max(22, segment.durationMinutes / 60 * hourHeight), (1440 - segment.startMinute) / 60 * hourHeight))
                    .offset(x: 42 + CGFloat(segment.day) * dayWidth + CGFloat(placement.column) * dayWidth / CGFloat(placement.columnCount) + 1,
                            y: segment.startMinute / 60 * hourHeight)
            }
        }
    }

    private func eventButton(_ occurrence: SchedulerOccurrence, anchor: String) -> some View {
        Button { editorAnchor = anchor; select(occurrence) } label: {
            Text(occurrence.title)
                .font(.system(size: 12)).lineLimit(2)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Color(hex: occurrence.colorHex).opacity(0.18), in: RoundedRectangle(cornerRadius: 4))
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1).fill(Color(hex: occurrence.colorHex)).frame(width: 2)
                        .allowsHitTesting(false)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: editorBinding(anchor)) { editorContent }
        .help(occurrence.title)
    }

    @ViewBuilder private var currentTimeLine: some View {
        if isVisible, store.visibleFrom <= Date(), Date() < store.visibleTo {
            TimelineView(.periodic(from: calendar.dateInterval(of: .minute, for: Date())!.end, by: 60)) { context in
                GeometryReader { geometry in
                    let dayWidth = max(0, geometry.size.width - 42) / 7
                    let day = calendar.dateComponents([.day], from: store.visibleFrom, to: calendar.startOfDay(for: context.date)).day ?? 0
                    let minute = calendar.component(.hour, from: context.date) * 60 + calendar.component(.minute, from: context.date)
                    Rectangle().fill(.red).frame(width: dayWidth, height: 1)
                        .offset(x: 42 + CGFloat(day) * dayWidth, y: CGFloat(minute) / 60 * hourHeight)
                }
            }.allowsHitTesting(false)
        }
    }

    private func updatePlacements() {
        let segments = store.occurrences.flatMap {
            SchedulerWeekLayout.segments(for: $0, weekStart: store.visibleFrom, calendar: calendar)
        }
        placements = SchedulerWeekLayout.placements(segments, minimumMinutes: 22 / hourHeight * 60)
    }

    private func afterDiscarding(_ action: @escaping () -> Void) {
        if editorForm?.hasChanges == true { pendingDiscardAction = action }
        else { action() }
    }

    private func navigateToWeek(_ date: Date) {
        afterDiscarding {
            draft = nil; editorForm = nil
            store.showWeek(containing: date)
        }
    }

    private func editorBinding(_ anchor: String) -> Binding<Bool> {
        Binding(get: { draft != nil && editorAnchor == anchor }, set: { if !$0 { draft = nil } })
    }

    private var initialHour: Int { calendar.isDate(Date(), equalTo: store.visibleFrom, toGranularity: .weekOfYear) ? max(0, calendar.component(.hour, from: Date()) - 1) : 8 }
    private func date(_ day: Int) -> Date { calendar.date(byAdding: .day, value: day, to: store.visibleFrom)! }
    private func shiftWeek(_ offset: Int) { navigateToWeek( calendar.date(byAdding: .weekOfYear, value: offset, to: store.visibleFrom)!) }
    private func allDayOccurrences(day: Int) -> [SchedulerOccurrence] {
        let start = date(day), end = date(day + 1)
        return store.occurrences.filter {
            guard case let .allDay(first, last) = $0.time, let first = first.date(in: calendar.timeZone), let last = last.date(in: calendar.timeZone) else { return false }
            return first < end && last > start
        }
    }
    private func select(_ occurrence: SchedulerOccurrence) {
        if occurrence.recurring { scopeOccurrence = occurrence }
        else { open(occurrence, scope: nil) }
    }
    private func open(_ occurrence: SchedulerOccurrence, scope: SchedulerMutationScope?) {
        if editorForm?.original.id == occurrence.eventID && occurrenceKey == (occurrence.recurring ? occurrence.originalKey : nil) && mutationScope == scope {
            finishOpen(occurrence, scope: scope)
        } else {
            afterDiscarding { finishOpen(occurrence, scope: scope) }
        }
    }

    private func finishOpen(_ occurrence: SchedulerOccurrence, scope: SchedulerMutationScope?) {
        editingExisting = true
        guard var event = store.events.first(where: { $0.id == occurrence.eventID }) else { return }
        if scope != .all {
            event.time = occurrence.time; event.title = occurrence.title
            event.notes = occurrence.notes; event.location = occurrence.location; event.colorHex = occurrence.colorHex
        }
        if editorForm?.original.id != event.id || occurrenceKey != (occurrence.recurring ? occurrence.originalKey : nil) || mutationScope != scope {
            editorForm = SchedulerEditorDraft(event: event, allowsRecurrenceEditing: scope != .this)
        }
        occurrenceKey = occurrence.recurring ? occurrence.originalKey : nil
        mutationScope = scope; errorMessage = nil; scopeOccurrence = nil; needsRefresh = false; draft = event
    }
    private func createTimed(day: Int, minute: Int) {
        afterDiscarding { createTimedDraft(day: day, minute: minute) }
    }

    private func createTimedDraft(day: Int, minute: Int) {
        editingExisting = false
        var components = calendar.dateComponents([.year, .month, .day], from: date(day))
        components.hour = minute / 60; components.minute = minute % 60
        guard let start = calendar.date(from: components), calendar.component(.hour, from: start) == minute / 60 else { return }
        editorAnchor = "new"
        occurrenceKey = nil; mutationScope = nil; errorMessage = nil
        draft = try? SchedulerEvent(title: L10n.text("新日程"), colorHex: PeekerPresetColor.lakeBlue.rawValue,
            time: .timed(startMilliseconds: Int64(start.timeIntervalSince1970 * 1000), endMilliseconds: Int64(start.addingTimeInterval(1800).timeIntervalSince1970 * 1000), timeZoneID: TimeZone.current.identifier))
        if let draft { editorForm = SchedulerEditorDraft(event: draft, allowsRecurrenceEditing: true) }
    }
    private func createAllDay(day: Int) {
        afterDiscarding { createAllDayDraft(day: day) }
    }

    private func createAllDayDraft(day: Int) {
        editingExisting = false
        let parts = calendar.dateComponents([.year, .month, .day], from: date(day))
        guard let start = try? SchedulerLocalDate(year: parts.year!, month: parts.month!, day: parts.day!),
              let end = start.adding(days: 1, in: calendar.timeZone) else { return }
        editorAnchor = "new"
        occurrenceKey = nil; mutationScope = nil; errorMessage = nil
        draft = try? SchedulerEvent(title: L10n.text("新日程"), colorHex: PeekerPresetColor.lakeBlue.rawValue, time: .allDay(start: start, endExclusive: end))
        if let draft { editorForm = SchedulerEditorDraft(event: draft, allowsRecurrenceEditing: true) }
    }
}

private struct SchedulerEventEditor: View {
    @Bindable var form: SchedulerEditorDraft
    let errorMessage: String?
    let isSaving: Bool
    let canSave: Bool
    let onCancel: () -> Void
    let onSave: (SchedulerEvent) -> Void
    let onDelete: (() -> Void)?

    var body: some View {
        Form {
            if form.original.sourceID != nil {
                Text(L10n.text("导入日程的本地修改会在下次来源刷新时被覆盖。"))
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            TextField(
                L10n.text("标题"),
                text: $form.title,
                prompt: Text(L10n.text("标题")).foregroundStyle(.secondary)
            )
            .foregroundStyle(.primary)
            Toggle(L10n.text("全天"), isOn: $form.timeDraft.allDay)
                .foregroundStyle(.primary)
            SchedulerDateTimeInputRow(
                title: L10n.text("开始"),
                draft: $form.timeDraft.start,
                includesTime: !form.timeDraft.allDay
            )
            SchedulerDateTimeInputRow(
                title: L10n.text("结束"),
                draft: $form.timeDraft.end,
                includesTime: !form.timeDraft.allDay
            )
            TextField(
                L10n.text("备注"),
                text: $form.notes,
                prompt: Text(L10n.text("备注")).foregroundStyle(.secondary),
                axis: .vertical
            )
            .foregroundStyle(.primary)
            TextField(
                L10n.text("地点"),
                text: $form.location,
                prompt: Text(L10n.text("地点")).foregroundStyle(.secondary)
            )
            .foregroundStyle(.primary)
            SchedulerPresetColorPicker(colorHex: $form.color)
            Picker(L10n.text("重复"), selection: $form.frequency) {
                Text(L10n.text("无")).tag("none")
                ForEach(SchedulerFrequency.allCases, id: \.rawValue) {
                    Text(L10n.text($0.rawValue)).tag($0.rawValue)
                }
            }
            .foregroundStyle(.primary)
            .disabled(!form.allowsRecurrenceEditing)
            if form.frequency != "none" {
                Stepper(L10n.text("间隔：%1$@", String(describing: form.interval)), value: $form.interval, in: 1...365)
                    .foregroundStyle(.primary)
            }
            if form.timeDraft.resolvedTime() == nil {
                Text(L10n.text("请输入真实有效的日期和时间，并确保结束晚于开始。"))
                    .foregroundStyle(.red)
                    .font(.caption)
            }
            if let errorMessage { Text(errorMessage).foregroundStyle(.red).textSelection(.enabled) }
            HStack {
                if let onDelete { Button(L10n.text("删除"), role: .destructive, action: onDelete) }
                Spacer()
                Button(L10n.text("取消"), action: onCancel)
                Button(L10n.text("保存"), action: save)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(form.updatedEvent == nil || isSaving || !canSave)
            }
        }
        .foregroundStyle(.primary)

        .disabled(isSaving)
        .padding(16)
        .frame(width: 420)
    }

    private func save() {
        guard let updatedEvent = form.updatedEvent else { return }
        onSave(updatedEvent)
    }
}

private struct SchedulerDateTimeInputRow: View {
    let title: String
    @Binding var draft: SchedulerTimeInputDraft
    let includesTime: Bool

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                SchedulerTimeComponentField(
                    unit: L10n.text("月"),
                    placeholder: "MM",
                    value: $draft.month
                )
                SchedulerTimeComponentField(
                    unit: L10n.text("日"),
                    placeholder: "DD",
                    value: $draft.day
                )
                if includesTime {
                    SchedulerTimeComponentField(
                        unit: L10n.text("时"),
                        placeholder: "HH",
                        value: $draft.hour
                    )
                    SchedulerTimeComponentField(
                        unit: L10n.text("分"),
                        placeholder: "mm",
                        value: $draft.minute
                    )
                }
            }
        }
        .foregroundStyle(.primary)

    }
}

private struct SchedulerTimeComponentField: View {
    let unit: String
    let placeholder: String
    @Binding var value: String

    var body: some View {
        VStack(spacing: 2) {
            TextField(
                unit,
                text: $value,
                prompt: Text(placeholder).foregroundStyle(.secondary)
            )
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.center)
            .font(.body.monospacedDigit())
            .foregroundStyle(.primary)

            .frame(width: 46)
            .accessibilityLabel(unit)

            Text(unit)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

private struct SchedulerPresetColorPicker: View {
    @Binding var colorHex: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.text("颜色"))
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                if !isPresetColor {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color(hex: colorHex))
                            .frame(width: 18, height: 18)
                        Text(L10n.text("当前颜色"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.trailing, 4)
                }

                ForEach(PeekerPresetColor.allCases) { preset in
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
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .help(L10n.text(preset.localizedName))
                    .accessibilityLabel(L10n.text(preset.localizedName))
                    .accessibilityValue(isSelected ? L10n.text("已选择") : L10n.text("未选择"))
                }
            }
        }
    }

    private var isPresetColor: Bool {
        PeekerPresetColor.allCases.contains {
            colorHex.caseInsensitiveCompare($0.rawValue) == .orderedSame
        }
    }
}

private struct SchedulerSettingsView: View {
    @Bindable var store: SchedulerStore
    @State private var failure: LocalizedMessage?

    var body: some View {
        Form {
            Picker(L10n.text("提前提醒"), selection: Binding(
                get: { store.reminderMinutes ?? 0 },
                set: { value in perform { try await store.setReminder(minutes: value == 0 ? nil : value) } }
            )) {
                Text(L10n.text("关闭")).tag(0)
                ForEach(1...60, id: \.self) { Text(L10n.text("minute_count", $0)).tag($0) }
            }
            Section(L10n.text("ICS 来源")) {
                Button(L10n.text("导入 ICS…")) { importICS() }
                ForEach(store.sources) { source in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(source.displayName)
                            Text(source.canonicalPath).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Button(L10n.text("刷新")) { perform { _ = try await store.importICS(fileURL: URL(fileURLWithPath: source.canonicalPath), sourceID: source.id) } }
                        Button(L10n.text("移除"), role: .destructive) { perform { _ = try await store.removeSource(id: source.id) } }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .safeAreaInset(edge: .bottom) {
            if let failure { Text(failure.resolve()).foregroundStyle(.red).textSelection(.enabled).padding() }
        }
    }

    private func perform(_ operation: @escaping () async throws -> Void) {
        Task {
            do { try await operation(); failure = nil }
            catch { failure = L10n.message("操作失败：%1$@", error.localizedDescription) }
        }
    }

    private func importICS() {
        let panel=NSOpenPanel(); panel.allowedContentTypes=[]; panel.allowsMultipleSelection=false; panel.canChooseDirectories=false
        guard panel.runModal() == .OK, let url=panel.url else { return }
        perform { _ = try await store.importICS(fileURL: url) }
    }
}

private extension Color {
    init(hex: String) {
        let value=Int(hex.dropFirst(), radix: 16) ?? 0
        self.init(red: Double((value >> 16) & 255)/255, green: Double((value >> 8) & 255)/255, blue: Double(value & 255)/255)
    }
}
