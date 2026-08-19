import AppKit
import FunctionCardKit
import SwiftUI

@MainActor
public enum SchedulerFeatureFactory {
    public static let metrics = FunctionCardMetrics(
        compactWidth: 220, compactHeight: 8, compactLeadingWidth: 0, compactTrailingWidth: 0,
        expandedWidth: 1120, expandedHeight: 700
    )

    public static func make(store: SchedulerStore) -> FunctionCardRegistration {
        Task { await store.load() }
        return FunctionCardRegistration(
            id: .scheduler, name: "Scheduler", systemImage: "calendar",
            defaultOrder: 2, introducedConfigurationVersion: 2, metrics: metrics,
            makeExpandedView: { AnyView(SchedulerWeekView(store: store)) },
            makeSettingsView: { AnyView(SchedulerSettingsView(store: store)) }
        )
    }
}

private struct SchedulerWeekView: View {
    @Bindable var store: SchedulerStore
    @State private var draft: SchedulerEvent?
    private let hourHeight: CGFloat = 52

    var body: some View {
        VStack(spacing: 8) {
            header
            allDayArea
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    ZStack(alignment: .topLeading) {
                        timeGrid
                        timedEvents
                    }
                    .frame(height: hourHeight * 24)
                }
                .onAppear { proxy.scrollTo(initialHour, anchor: .top) }
            }
        }
        .popover(item: $draft) { event in
            SchedulerEventEditor(
                event: event,
                onCancel: { draft = nil },
                onSave: { updated in
                    Task {
                        if store.events.contains(where: { $0.id == updated.id }) {
                            _ = try? await store.update(updated, occurrenceKey: updated.recurrence.map { _ in SchedulerRecurrenceExpander.originalKey(updated.time) }, scope: updated.recurrence == nil ? nil : .all)
                        } else {
                            _ = try? await store.create(updated)
                        }
                        draft = nil
                    }
                },
                onDelete: store.events.contains(where: { $0.id == event.id }) ? {
                    Task {
                        _ = try? await store.delete(
                            id: event.id,
                            occurrenceKey: event.recurrence.map { _ in SchedulerRecurrenceExpander.originalKey(event.time) },
                            scope: event.recurrence == nil ? nil : .all
                        )
                        draft = nil
                    }
                } : nil
            )
        }
        .overlay {
            if store.isLoading { ProgressView() }
            else if let error = store.errorMessage {
                ContentUnavailableView("Scheduler 无法载入", systemImage: "exclamationmark.triangle", description: Text(error))
            }
        }
    }

    private var header: some View {
        HStack {
            Button { store.showWeek(containing: store.visibleFrom.addingTimeInterval(-86_400)) } label: { Image(systemName: "chevron.left") }
            Button("今天") { store.showWeek(containing: Date()) }
            Button { store.showWeek(containing: store.visibleTo.addingTimeInterval(86_400)) } label: { Image(systemName: "chevron.right") }
            Spacer()
            Text("\(store.visibleFrom.formatted(date: .abbreviated, time: .omitted)) – \(store.visibleTo.addingTimeInterval(-1).formatted(date: .abbreviated, time: .omitted))")
                .font(.headline)
            Spacer()
        }
        .buttonStyle(.borderless)
    }

    private var allDayArea: some View {
        HStack(spacing: 1) {
            Text("全天").font(.caption).frame(width: 42)
            ForEach(0..<7, id: \.self) { day in
                VStack(alignment: .leading, spacing: 3) {
                    Text(store.visibleFrom.addingTimeInterval(Double(day * 86_400)).formatted(.dateTime.weekday(.abbreviated).day()))
                        .font(.caption.weight(.semibold))
                    ForEach(allDayOccurrences(day: day).prefix(3)) { occurrence in
                        Text(occurrence.title).font(.caption2).lineLimit(1)
                            .padding(.horizontal, 4).padding(.vertical, 2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(hex: occurrence.colorHex).opacity(0.7), in: RoundedRectangle(cornerRadius: 4))
                    }
                    Spacer(minLength: 0)
                }
                .padding(4).frame(maxWidth: .infinity, minHeight: 62, alignment: .topLeading)
                .background(Color.white.opacity(0.04))
                .contentShape(Rectangle())
                .onTapGesture { createAllDay(day: day) }
            }
        }
    }

    private var timeGrid: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                ForEach(0..<24, id: \.self) { hour in
                    Text(String(format: "%02d:00", hour)).font(.caption2).foregroundStyle(.secondary)
                        .frame(width: 42, height: hourHeight, alignment: .top)
                        .id(hour)
                }
            }
            ForEach(0..<7, id: \.self) { day in
                VStack(spacing: 0) {
                    ForEach(0..<24, id: \.self) { hour in
                        Rectangle().fill(Color.clear).frame(height: hourHeight)
                            .overlay(alignment: .top) { Divider().opacity(0.25) }
                            .contentShape(Rectangle())
                            .gesture(SpatialTapGesture().onEnded { value in
                                let quarter = min(3, max(0, Int(value.location.y / (hourHeight / 4))))
                                createTimed(day: day, minute: hour * 60 + quarter * 15)
                            })
                    }
                }
                .frame(maxWidth: .infinity).overlay(alignment: .leading) { Divider().opacity(0.25) }
            }
        }
    }

    private var timedEvents: some View {
        GeometryReader { geometry in
            let gridWidth = max(0, geometry.size.width - 42)
            let dayWidth = gridWidth / 7
            ForEach(timedSegments()) { segment in
                Button { open(segment.occurrence) } label: {
                    Text(segment.occurrence.title)
                        .font(.caption).lineLimit(2).padding(4)
                }
                .buttonStyle(.plain)
                    .frame(width: max(12, dayWidth - 4), height: max(18, segment.durationMinutes / 60 * hourHeight), alignment: .topLeading)
                    .background(Color(hex: segment.occurrence.colorHex).opacity(0.82), in: RoundedRectangle(cornerRadius: 5))
                    .offset(x: 42 + CGFloat(segment.day) * dayWidth + 2, y: segment.startMinute / 60 * hourHeight)
                    .accessibilityLabel(segment.occurrence.title)
            }
            if store.visibleFrom <= Date(), Date() < store.visibleTo {
                let components = Calendar.current.dateComponents([.weekday, .hour, .minute], from: Date())
                let day = ((components.weekday ?? 2) + 5) % 7
                Rectangle().fill(.red).frame(width: dayWidth, height: 1)
                    .offset(x: 42 + CGFloat(day) * dayWidth, y: CGFloat((components.hour ?? 0) * 60 + (components.minute ?? 0)) / 60 * hourHeight)
            }
        }
    }

    private var initialHour: Int {
        store.visibleFrom <= Date() && Date() < store.visibleTo ? max(0, Calendar.current.component(.hour, from: Date()) - 1) : 8
    }

    private func allDayOccurrences(day: Int) -> [SchedulerOccurrence] {
        let date = Calendar.current.date(byAdding: .day, value: day, to: store.visibleFrom)!
        return store.occurrences.filter {
            guard case let .allDay(start, end) = $0.time, let s=start.date(in: .current), let e=end.date(in: .current) else { return false }
            return s < date.addingTimeInterval(86_400) && e > date
        }
    }

    private func timedSegments() -> [SchedulerTimedSegment] {
        store.occurrences.flatMap { SchedulerWeekLayout.segments(for: $0, weekStart: store.visibleFrom, calendar: .current) }
    }

    private func open(_ occurrence: SchedulerOccurrence) {
        draft = store.events.first(where: { $0.id == occurrence.eventID })
    }

    private func createTimed(day: Int, minute: Int) {
        let dayStart = Calendar.current.date(byAdding: .day, value: day, to: store.visibleFrom)!
        let start = Calendar.current.date(byAdding: .minute, value: minute, to: dayStart)!
        draft = try? SchedulerEvent(
            title: "新日程",
            time: .timed(
                startMilliseconds: Int64(start.timeIntervalSince1970 * 1000),
                endMilliseconds: Int64(start.addingTimeInterval(1_800).timeIntervalSince1970 * 1000),
                timeZoneID: TimeZone.current.identifier
            )
        )
    }

    private func createAllDay(day: Int) {
        let date = Calendar.current.date(byAdding: .day, value: day, to: store.visibleFrom)!
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        guard let start = try? SchedulerLocalDate(year: components.year!, month: components.month!, day: components.day!),
              let end = start.adding(days: 1, in: .current) else { return }
        draft = try? SchedulerEvent(title: "新日程", time: .allDay(start: start, endExclusive: end))
    }
}

public struct SchedulerTimedSegment: Identifiable, Equatable {
    public let occurrence: SchedulerOccurrence
    public let day: Int
    public let startMinute: CGFloat
    public let durationMinutes: CGFloat
    public var id: String { "\(occurrence.id):\(day):\(startMinute)" }
}

public enum SchedulerWeekLayout {
    public static func segments(for occurrence: SchedulerOccurrence, weekStart: Date, calendar: Calendar) -> [SchedulerTimedSegment] {
        guard case let .timed(startMS, endMS, _) = occurrence.time else { return [] }
        let start=Date(timeIntervalSince1970: Double(startMS)/1000), end=Date(timeIntervalSince1970: Double(endMS)/1000)
        var output:[SchedulerTimedSegment]=[]
        for day in 0..<7 {
            let dayStart=calendar.date(byAdding: .day, value: day, to: weekStart)!, dayEnd=calendar.date(byAdding: .day, value: 1, to: dayStart)!
            let visibleStart=max(start,dayStart), visibleEnd=min(end,dayEnd)
            guard visibleEnd > visibleStart else { continue }
            let startMinute=CGFloat(visibleStart.timeIntervalSince(dayStart)/60)
            output.append(.init(occurrence: occurrence, day: day, startMinute: startMinute, durationMinutes: CGFloat(visibleEnd.timeIntervalSince(visibleStart)/60)))
        }
        return output
    }
}

private struct SchedulerEventEditor: View {
    let original: SchedulerEvent
    let onCancel: () -> Void
    let onSave: (SchedulerEvent) -> Void
    let onDelete: (() -> Void)?
    @State private var title: String
    @State private var notes: String
    @State private var location: String
    @State private var color: String
    @State private var allDay: Bool
    @State private var start: Date
    @State private var end: Date
    @State private var frequency: String
    @State private var interval: Int
    @State private var error: String?

    init(event: SchedulerEvent, onCancel: @escaping () -> Void, onSave: @escaping (SchedulerEvent) -> Void, onDelete: (() -> Void)?) {
        original=event; self.onCancel=onCancel; self.onSave=onSave; self.onDelete=onDelete
        _title=State(initialValue:event.title); _notes=State(initialValue:event.notes ?? ""); _location=State(initialValue:event.location ?? "")
        _color=State(initialValue:event.colorHex); _frequency=State(initialValue:event.recurrence?.frequency.rawValue ?? "none")
        _interval=State(initialValue:event.recurrence?.interval ?? 1)
        switch event.time {
        case let .timed(start,end,_):
            _allDay=State(initialValue:false); _start=State(initialValue:Date(timeIntervalSince1970:Double(start)/1000)); _end=State(initialValue:Date(timeIntervalSince1970:Double(end)/1000))
        case let .allDay(start,end):
            _allDay=State(initialValue:true); _start=State(initialValue:start.date(in:.current) ?? Date()); _end=State(initialValue:end.date(in:.current) ?? Date().addingTimeInterval(86_400))
        }
    }

    var body: some View {
        Form {
            if original.sourceID != nil { Text("导入日程的本地修改会在下次来源刷新时被覆盖。 ").font(.caption).foregroundStyle(.orange) }
            TextField("标题",text:$title)
            Toggle("全天",isOn:$allDay)
            DatePicker("开始",selection:$start,displayedComponents:allDay ? [.date] : [.date,.hourAndMinute])
            DatePicker("结束",selection:$end,displayedComponents:allDay ? [.date] : [.date,.hourAndMinute])
            TextField("备注",text:$notes,axis:.vertical)
            TextField("地点",text:$location)
            TextField("颜色 (#RRGGBB)",text:$color)
            Picker("重复",selection:$frequency) {
                Text("无").tag("none")
                ForEach(SchedulerFrequency.allCases,id:\.rawValue) { Text($0.rawValue).tag($0.rawValue) }
            }
            if frequency != "none" { Stepper("间隔：\(interval)",value:$interval,in:1...365) }
            if let error { Text(error).foregroundStyle(.red).font(.caption) }
            HStack {
                if let onDelete { Button("删除",role:.destructive,action:onDelete) }
                Spacer()
                Button("取消",action:onCancel)
                Button("保存",action:save).keyboardShortcut(.defaultAction)
            }
        }
        .padding(16).frame(width:420)
    }

    private func save() {
        do {
            let time:SchedulerEventTime
            if allDay {
                let c=Calendar.current
                let s=c.dateComponents([.year,.month,.day],from:start), e=c.dateComponents([.year,.month,.day],from:end)
                let sd=try SchedulerLocalDate(year:s.year!,month:s.month!,day:s.day!), ed=try SchedulerLocalDate(year:e.year!,month:e.month!,day:e.day!)
                time = .allDay(start:sd,endExclusive:ed)
            } else {
                time = .timed(startMilliseconds:Int64(start.timeIntervalSince1970*1000),endMilliseconds:Int64(end.timeIntervalSince1970*1000),timeZoneID:TimeZone.current.identifier)
            }
            let recurrence = frequency == "none" ? nil : try SchedulerRecurrence(frequency:SchedulerFrequency(rawValue:frequency)!,interval:interval)
            let value=try SchedulerEvent(
                id:original.id,sourceID:original.sourceID,sourceUID:original.sourceUID,sourceSegmentKey:original.sourceSegmentKey,
                title:title,notes:notes.isEmpty ? nil : notes,location:location.isEmpty ? nil : location,colorHex:color,
                time:time,recurrence:recurrence,createdAtMilliseconds:original.createdAtMilliseconds,
                updatedAtMilliseconds:Int64(Date().timeIntervalSince1970*1000)
            )
            onSave(value)
        } catch { self.error=error.localizedDescription }
    }
}

private struct SchedulerSettingsView: View {
    @Bindable var store: SchedulerStore

    var body: some View {
        Form {
            Picker("提前提醒", selection: Binding(
                get: { store.reminderMinutes ?? 0 },
                set: { value in Task { try? await store.setReminder(minutes: value == 0 ? nil : value) } }
            )) {
                Text("关闭").tag(0)
                ForEach(1...60, id: \.self) { Text("\($0) 分钟").tag($0) }
            }
            Section("ICS 来源") {
                Button("导入 ICS…") { importICS() }
                ForEach(store.sources) { source in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(source.displayName)
                            Text(source.canonicalPath).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Button("刷新") { Task { _ = try? await store.importICS(fileURL: URL(fileURLWithPath: source.canonicalPath), sourceID: source.id) } }
                        Button("移除", role: .destructive) { Task { _ = try? await store.removeSource(id: source.id) } }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func importICS() {
        let panel=NSOpenPanel(); panel.allowedContentTypes=[]; panel.allowsMultipleSelection=false; panel.canChooseDirectories=false
        guard panel.runModal() == .OK, let url=panel.url else { return }
        Task { _ = try? await store.importICS(fileURL: url) }
    }
}

private extension Color {
    init(hex: String) {
        let value=Int(hex.dropFirst(), radix: 16) ?? 0
        self.init(red: Double((value >> 16) & 255)/255, green: Double((value >> 8) & 255)/255, blue: Double(value & 255)/255)
    }
}
