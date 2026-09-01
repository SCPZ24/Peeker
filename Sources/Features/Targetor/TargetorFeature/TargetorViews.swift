import Foundation
import SwiftUI
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
        expandedWidth: 840, expandedHeight: 340
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
    public static let hoverScale: CGFloat = 1.025
    public static let rearOffset: CGFloat = -7
    public static let rearRotation: Double = -2.5
    public static let hoverAnimationResponse: TimeInterval = 0.28
    public static let hoverAnimationDamping: Double = 0.82
}

enum TargetorInteractionPresentation {
    static func checkinPromptIcon(currentCount: Int, maxCount: Int) -> String {
        switch TargetorCheckinState.resolve(
            count: min(currentCount + 1, maxCount),
            maxCount: maxCount
        ) {
        case .notStarted, .started: "chevrons-up"
        case .progressing: "rocket"
        case .completed: "badge-check"
        }
    }
}

enum TargetorSidePanelMode: Equatable {
    case feedback(TargetorFeedback)
    case dragging(UUID)
    case target(UUID)
    case summary

    static func resolve(
        feedback: TargetorFeedback?,
        activeEnvelope: TargetorDragEnvelope?,
        hoveredTargetID: UUID?
    ) -> TargetorSidePanelMode {
        if let feedback { return .feedback(feedback) }
        if let activeEnvelope { return .dragging(activeEnvelope.targetID) }
        if let hoveredTargetID { return .target(hoveredTargetID) }
        return .summary
    }
}

private struct TargetorCalendarRequest: Hashable {
    let targetID: UUID
    let revision: Int
}

private struct TargetorExpandedView: View {
    @Bindable var store: TargetorStore
    let manifest: FunctionCardIconManifest?
    let setDragging: @MainActor (Bool) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expansionNonce = UUID()
    @State private var hoveredTargetID: UUID?
    @State private var activeDragEnvelope: TargetorDragEnvelope?
    @State private var dragLayoutModel = TargetorDragLayoutModel()
    @State private var expansionHold = TargetorExpansionHoldController()
    @State private var summaryCells: [TargetorCalendarCell] = []
    @State private var targetCalendar: TargetorTargetCalendarSnapshot?
    @State private var calendarRevision = 0
    @State private var calendarErrorMessage: String?

    var body: some View {
        TargetorAppKitDropContainer(
            layoutModel: dragLayoutModel,
            expansionNonce: expansionNonce,
            targets: store.targets,
            isEnabled: !store.isLoading
                && !expansionHold.isCheckinPending
                && store.feedback == nil,
            performDrop: performDrop,
            dragEnded: finishDragging
        ) {
            HStack(spacing: 14) {
                targetGrid
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                TargetorSidePanel(
                    mode: sidePanelMode,
                    targets: store.targets,
                    manifest: manifest,
                    summaryCells: summaryCells,
                    targetCalendar: targetCalendar,
                    calendarErrorMessage: calendarErrorMessage,
                    isDropTargeted: dragLayoutModel.targetedEnvelope != nil,
                    reduceMotion: reduceMotion
                )
                .frame(width: 190, height: 190)
                .frame(width: 190)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .onGeometryChange(for: CGRect.self) { proxy in
                    proxy.frame(in: .named(TargetorDragLayoutModel.coordinateSpaceName))
                } action: { frame in
                    dragLayoutModel.updateDropFrame(frame)
                }
            }
            .coordinateSpace(name: TargetorDragLayoutModel.coordinateSpaceName)
            .onDragSessionUpdated(handleDragSession)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottomLeading) {
            if let errorMessage = store.errorMessage {
                Text(errorMessage)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.72), in: Capsule())
            }
        }
        .onAppear {
            expansionNonce = UUID()
            dragLayoutModel.clearTargetedEnvelope()
            expansionHold.attach(publish: setDragging)
            expansionHold.feedbackChanged(isVisible: store.feedback != nil)
        }
        .onDisappear {
            finishDragging()
            expansionHold.detach()
        }
        .task { await reloadSummaryCalendar() }
        .task(id: calendarRequest) {
            await reloadTargetCalendar(for: calendarRequest)
        }
        .onChange(of: store.targets) { _, _ in
            calendarRevision += 1
            Task { await reloadSummaryCalendar() }
        }
        .onChange(of: store.feedback?.token) { _, _ in
            expansionHold.feedbackChanged(isVisible: store.feedback != nil)
        }
    }

    @ViewBuilder
    private var targetGrid: some View {
        if store.targets.isEmpty {
            ContentUnavailableView(
                "还没有长期目标",
                systemImage: "scope",
                description: Text("请在 Targetor 设置中创建推进项。")
            )
        } else {
            ScrollView {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3),
                    spacing: 10
                ) {
                    ForEach(store.targets) { state in
                        TargetorCardDragSource(
                            state: state,
                            manifest: manifest,
                            hovered: hoveredTargetID == state.id,
                            reduceMotion: reduceMotion,
                            expansionNonce: expansionNonce,
                            beginDragging: beginDragging,
                            finishDragging: finishDragging
                        )
                        .onHover { hovering in
                            withAnimation(hoverAnimation) {
                                if hovering {
                                    if hoveredTargetID != state.id {
                                        targetCalendar = nil
                                        calendarErrorMessage = nil
                                    }
                                    hoveredTargetID = state.id
                                } else if hoveredTargetID == state.id {
                                    hoveredTargetID = nil
                                    targetCalendar = nil
                                    calendarErrorMessage = nil
                                }
                            }
                        }
                    }
                }
                .padding(4)
            }
        }
    }

    private var sidePanelMode: TargetorSidePanelMode {
        TargetorSidePanelMode.resolve(
            feedback: store.feedback,
            activeEnvelope: dragLayoutModel.targetedEnvelope ?? activeDragEnvelope,
            hoveredTargetID: hoveredTargetID
        )
    }

    private var calendarRequest: TargetorCalendarRequest? {
        hoveredTargetID.map {
            TargetorCalendarRequest(
                targetID: $0,
                revision: calendarRevision
            )
        }
    }

    private var hoverAnimation: Animation? {
        reduceMotion ? nil : .interactiveSpring(
            response: TargetorAnimationTokens.hoverAnimationResponse,
            dampingFraction: TargetorAnimationTokens.hoverAnimationDamping
        )
    }

    private func handleDragSession(_ session: DragSession) {
        switch session.phase {
        case .initial, .active:
            expansionHold.dragBegan()
        case .ended, .dataTransferCompleted:
            finishDragging()
        @unknown default:
            finishDragging()
        }
    }

    private func beginDragging(_ envelope: TargetorDragEnvelope) {
        guard activeDragEnvelope != envelope else { return }
        activeDragEnvelope = envelope
        expansionHold.dragBegan()
    }

    private func performDrop(_ envelope: TargetorDragEnvelope) -> Bool {
        guard !expansionHold.isCheckinPending, store.feedback == nil else { return false }
        expansionHold.dropAccepted()
        Task {
            let succeeded = await store.checkinFromUI(
                targetID: envelope.targetID,
                expectedPeriodID: envelope.periodID
            )
            expansionHold.checkinCompleted(
                feedbackVisible: succeeded && store.feedback != nil
            )
        }
        return true
    }

    private func finishDragging() {
        activeDragEnvelope = nil
        dragLayoutModel.clearTargetedEnvelope()
        expansionHold.dragEnded()
    }

    private func reloadSummaryCalendar() async {
        guard let cells = try? await store.summaryCalendar(), !Task.isCancelled else { return }
        summaryCells = cells
    }

    private func reloadTargetCalendar(for request: TargetorCalendarRequest?) async {
        guard let request else {
            targetCalendar = nil
            calendarErrorMessage = nil
            return
        }
        do {
            let snapshot = try await store.targetCalendar(targetID: request.targetID)
            guard !Task.isCancelled, calendarRequest == request else { return }
            targetCalendar = snapshot
            calendarErrorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            guard calendarRequest == request else { return }
            targetCalendar = nil
            calendarErrorMessage = "日历无法载入"
        }
    }
}

private struct TargetorCardDragSource: View {
    let state: TargetorTargetState
    let manifest: FunctionCardIconManifest?
    let hovered: Bool
    let reduceMotion: Bool
    let expansionNonce: UUID
    let beginDragging: (TargetorDragEnvelope) -> Void
    let finishDragging: () -> Void

    var body: some View {
        if let period = state.currentPeriod, period.state != .completed {
            TargetorCard(
                state: state,
                manifest: manifest,
                hovered: hovered,
                reduceMotion: reduceMotion
            )
            .draggable(envelope(periodID: period.id).rawValue) {
                TargetorCard(
                    state: state,
                    manifest: manifest,
                    hovered: false,
                    reduceMotion: true
                )
                .frame(width: 190)
            }
            .dragConfiguration(copyOnlyDragConfiguration)
            .onDragSessionUpdated { session in
                switch session.phase {
                case .initial, .active:
                    beginDragging(envelope(periodID: period.id))
                case .ended, .dataTransferCompleted:
                    finishDragging()
                @unknown default:
                    finishDragging()
                }
            }
        } else {
            TargetorCard(
                state: state,
                manifest: manifest,
                hovered: hovered,
                reduceMotion: reduceMotion
            )
        }
    }

    private var copyOnlyDragConfiguration: DragConfiguration {
        DragConfiguration(
            operationsWithinApp: .init(
                allowCopy: true,
                allowMove: false,
                allowDelete: false
            ),
            operationsOutsideApp: .init(allowCopy: false)
        )
    }

    private func envelope(periodID: UUID) -> TargetorDragEnvelope {
        TargetorDragEnvelope(
            expansionNonce: expansionNonce,
            targetID: state.id,
            periodID: periodID
        )
    }
}

private enum TargetorCardLayout {
    static let rearLayerInset: CGFloat = 3
    static let frontLayerInset: CGFloat = 5
}

private struct TargetorCard: View {
    let state: TargetorTargetState
    let manifest: FunctionCardIconManifest?
    let hovered: Bool
    let reduceMotion: Bool

    var body: some View {
        let period = state.currentPeriod
        let checkinState = period?.state ?? .notStarted
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(.white.opacity(0.22))
                .padding(TargetorCardLayout.rearLayerInset)
                .offset(x: hovered && !reduceMotion ? TargetorAnimationTokens.rearOffset : 0)
                .rotationEffect(.degrees(hovered && !reduceMotion ? TargetorAnimationTokens.rearRotation : 0))
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    FunctionCardIconView(
                        descriptor: .bundleSVG(
                            featureID: .targetor,
                            manifestResourceName: state.target.iconName
                        ),
                        manifest: manifest,
                        accessibilityLabel: state.target.iconName
                    )
                    .frame(width: 58, height: 58)
                    .frame(width: 68)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(state.target.title)
                            .font(.headline)
                            .lineLimit(1)
                        Text("本周期 \(period?.count ?? 0)/\(period?.maxCountSnapshot ?? state.target.maxCount)")
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let description = state.target.description {
                    Text(description)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .accessibilityLabel(description)
                }

                Spacer(minLength: 2)
                ProgressView(value: period?.ratio ?? 0)
                    .tint(.white)
            }
            .padding(11)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        .white.opacity(borderOpacity(checkinState)),
                        lineWidth: 1.5
                    )
            }
            .scaleEffect(hovered && !reduceMotion ? TargetorAnimationTokens.hoverScale : 1)
            .padding(TargetorCardLayout.frontLayerInset)
        }
        .frame(height: 138)
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .animation(
            reduceMotion ? nil : .interactiveSpring(
                response: TargetorAnimationTokens.hoverAnimationResponse,
                dampingFraction: TargetorAnimationTokens.hoverAnimationDamping
            ),
            value: hovered
        )
    }

    private func borderOpacity(_ state: TargetorCheckinState) -> Double {
        switch state {
        case .notStarted: 0
        case .started: 0.35
        case .progressing: 0.65
        case .completed: 1
        }
    }
}

private struct TargetorSidePanel: View {
    let mode: TargetorSidePanelMode
    let targets: [TargetorTargetState]
    let manifest: FunctionCardIconManifest?
    let summaryCells: [TargetorCalendarCell]
    let targetCalendar: TargetorTargetCalendarSnapshot?
    let calendarErrorMessage: String?
    let isDropTargeted: Bool
    let reduceMotion: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(.white.opacity(0.08))
            if case let .feedback(feedback) = mode {
                TargetorFeedbackEffect(feedback: feedback, reduceMotion: reduceMotion)
                    .transition(.identity)
            }
            panelContent
                .padding(10)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    .white.opacity(isDropTargeted ? 0.85 : 0.15),
                    lineWidth: isDropTargeted ? 2 : 1
                )
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: mode)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: isDropTargeted)
    }

    @ViewBuilder
    private var panelContent: some View {
        switch mode {
        case let .feedback(feedback):
            feedbackView(feedback.state)
                .transition(.opacity)
        case let .dragging(targetID):
            if let target = targets.first(where: { $0.id == targetID }) {
                checkinView(target)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else {
                Text("目标已不可用").font(.caption).foregroundStyle(.secondary)
            }
        case let .target(targetID):
            targetCalendarView(targetID: targetID)
                .transition(.opacity)
        case .summary:
            summaryCalendarView
                .transition(.opacity)
        }
    }

    private var summaryCalendarView: some View {
        VStack(spacing: 8) {
            Text("最近九周")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            LazyVGrid(
                columns: Array(repeating: GridItem(.fixed(12), spacing: 3), count: 9),
                spacing: 3
            ) {
                ForEach(summaryCells) { cell in
                    calendarCell(cell, size: 12, hue: nil)
                }
            }
        }
    }

    @ViewBuilder
    private func targetCalendarView(targetID: UUID) -> some View {
        if let calendarErrorMessage {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                Text(calendarErrorMessage).font(.caption)
            }
            .foregroundStyle(.secondary)
        } else if let target = targets.first(where: { $0.id == targetID }),
                  let targetCalendar,
                  targetCalendar.targetID == targetID {
            VStack(spacing: 5) {
                Text(target.target.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Text(calendarTitle(targetCalendar))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                switch targetCalendar.granularity {
                case .month:
                    monthGrid(snapshot: targetCalendar)
                case .year:
                    yearGrid(snapshot: targetCalendar)
                }
            }
        } else {
            ProgressView().controlSize(.small)
        }
    }

    private func monthGrid(snapshot: TargetorTargetCalendarSnapshot) -> some View {
        VStack(spacing: 3) {
            LazyVGrid(
                columns: Array(repeating: GridItem(.fixed(13), spacing: 4), count: 7),
                spacing: 0
            ) {
                ForEach(mondayFirstWeekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.system(size: 7, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .frame(width: 13)
                }
            }
            LazyVGrid(
                columns: Array(repeating: GridItem(.fixed(13), spacing: 4), count: 7),
                spacing: 3
            ) {
                ForEach(0..<snapshot.leadingEmptyCellCount, id: \.self) { _ in
                    Color.clear.frame(width: 13, height: 13)
                }
                ForEach(snapshot.cells) { cell in
                    calendarCell(cell, size: 13, hue: targetHue(for: cell))
                }
            }
        }
    }

    private func yearGrid(snapshot: TargetorTargetCalendarSnapshot) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 7) {
            ForEach(snapshot.cells) { cell in
                VStack(spacing: 2) {
                    Text(cell.date.formatted(.dateTime.month(.abbreviated)))
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.secondary)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(calendarColor(cell.level, hue: targetHue(for: cell)))
                        .frame(height: 13)
                }
                .help(cell.date.formatted(date: .abbreviated, time: .omitted))
            }
        }
    }

    private func checkinView(_ state: TargetorTargetState) -> some View {
        let period = state.currentPeriod
        let count = period?.count ?? 0
        let maxCount = period?.maxCountSnapshot ?? state.target.maxCount
        let promptIcon = TargetorInteractionPresentation.checkinPromptIcon(
            currentCount: count,
            maxCount: maxCount
        )
        return VStack(spacing: 9) {
            FunctionCardIconView(
                descriptor: .bundleSVG(featureID: .targetor, manifestResourceName: promptIcon),
                manifest: manifest,
                accessibilityLabel: "打卡提示"
            )
            .frame(width: 48, height: 48)
            .scaleEffect(isDropTargeted && !reduceMotion ? 1.08 : 1)
            Text(state.target.title)
                .font(.headline)
                .lineLimit(1)
            Text("\(count)/\(maxCount)")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
            Text(isDropTargeted ? "松开以打卡" : "拖到右侧以打卡")
                .font(.caption)
                .foregroundStyle(isDropTargeted ? .primary : .secondary)
        }
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
            )
            .frame(width: 52, height: 52)
            Text("打卡成功").font(.headline)
        }
    }

    private func calendarCell(
        _ cell: TargetorCalendarCell,
        size: CGFloat,
        hue: TargetorCalendarHue?
    ) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(calendarColor(cell.level, hue: hue))
            .frame(width: size, height: size)
            .help(cell.date.formatted(date: .abbreviated, time: .omitted))
    }

    private func targetHue(for cell: TargetorCalendarCell) -> TargetorCalendarHue? {
        guard cell.periodFrequency == .weekly, let sequence = cell.periodSequence else { return nil }
        return .weekly(sequence: sequence)
    }

    private func calendarTitle(_ snapshot: TargetorTargetCalendarSnapshot) -> String {
        switch snapshot.granularity {
        case .month:
            snapshot.anchor.formatted(.dateTime.year().month(.abbreviated))
        case .year:
            snapshot.anchor.formatted(.dateTime.year())
        }
    }

    private var mondayFirstWeekdaySymbols: [String] {
        let symbols = Calendar.current.veryShortStandaloneWeekdaySymbols
        return Array(symbols.dropFirst()) + Array(symbols.prefix(1))
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

private func calendarColor(
    _ level: TargetorCompletionLevel,
    hue: TargetorCalendarHue?
) -> Color {
    guard level != .empty else { return .white.opacity(0.08) }
    let color: Color = switch hue {
    case .orange: .orange
    case .yellow: .yellow
    case .green: .green
    case .blue: .blue
    case .cyan: .cyan
    case nil: .blue
    }
    let opacity: Double = switch level {
    case .empty: 0.08
    case .one: 0.28
    case .two: 0.48
    case .three: 0.72
    case .four: 1
    }
    return color.opacity(opacity)
}
