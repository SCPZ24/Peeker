import AppKit
import Foundation
import Observation
import OSLog
import SwiftUI

struct PusherDragSessionSnapshot {
    let rawValue: String?
    let isLocal: Bool
    let itemCount: Int
    let sourceOperationMask: NSDragOperation
    let location: CGPoint
    let draggedCardSize: CGSize?
}

struct PusherResolvedDropTarget: Equatable {
    let taskID: UUID
    let status: PusherStatus
    let insertionIndex: Int
    let landingFrame: CGRect
}

enum PusherDropRejectionReason: String, Equatable {
    case externalSource
    case multipleItems
    case moveUnsupported
    case malformedPayload
    case staleSession
    case staleBusinessDay
    case missingTask
    case outsideColumn
}

enum PusherDropEvaluation: Equatable {
    case accepted(PusherResolvedDropTarget)
    case rejected(PusherDropRejectionReason)
}

enum PusherDropSessionPolicy {
    static func evaluate(
        _ snapshot: PusherDragSessionSnapshot,
        sessionNonce: UUID,
        board: PusherBoard,
        columns: [PusherDropColumnGeometry]
    ) -> PusherDropEvaluation {
        guard snapshot.isLocal else { return .rejected(.externalSource) }
        guard snapshot.itemCount == 1 else { return .rejected(.multipleItems) }
        guard snapshot.sourceOperationMask.contains(.move) else {
            return .rejected(.moveUnsupported)
        }
        guard let rawValue = snapshot.rawValue,
              let envelope = PusherDragEnvelope(rawValue: rawValue) else {
            return .rejected(.malformedPayload)
        }
        guard envelope.sessionNonce == sessionNonce else { return .rejected(.staleSession) }
        guard envelope.businessDayStart == board.businessDay.id.startAtMilliseconds else {
            return .rejected(.staleBusinessDay)
        }
        guard let task = board.allTasks.first(where: { $0.id == envelope.taskID }) else {
            return .rejected(.missingTask)
        }
        guard let target = PusherDropGeometry.target(
            location: snapshot.location,
            columns: columns,
            draggedCardSize: snapshot.draggedCardSize
                ?? sourceCardSize(task: task, board: board, columns: columns)
        ) else { return .rejected(.outsideColumn) }
        return .accepted(
            PusherResolvedDropTarget(
                taskID: task.id,
                status: target.status,
                insertionIndex: target.insertionIndex,
                landingFrame: target.landingFrame
            )
        )
    }

    static func target(
        for snapshot: PusherDragSessionSnapshot,
        sessionNonce: UUID,
        board: PusherBoard,
        columns: [PusherDropColumnGeometry]
    ) -> PusherResolvedDropTarget? {
        guard case let .accepted(target) = evaluate(
            snapshot,
            sessionNonce: sessionNonce,
            board: board,
            columns: columns
        ) else { return nil }
        return target
    }

    private static func sourceCardSize(
        task: PusherTask,
        board: PusherBoard,
        columns: [PusherDropColumnGeometry]
    ) -> CGSize? {
        guard let index = board.tasks(in: task.status).firstIndex(where: { $0.id == task.id }),
              let row = columns.first(where: { $0.status == task.status })?
                .rows.first(where: { $0.taskIndex == index }) else { return nil }
        return row.frame.size
    }
}

@MainActor
@Observable
final class PusherDragLayoutModel {
    nonisolated static let coordinateSpaceName = "pusher-appkit-drop-container"

    private(set) var columns: [PusherDropColumnGeometry] = []
    private(set) var activeTarget: PusherResolvedDropTarget?

    func updateColumn(_ column: PusherDropColumnGeometry) {
        var byStatus = Dictionary(uniqueKeysWithValues: columns.map { ($0.status, $0) })
        byStatus[column.status] = column
        columns = PusherStatus.allCases.compactMap { byStatus[$0] }
    }

    func setActiveTarget(_ target: PusherResolvedDropTarget?) {
        guard activeTarget != target else { return }
        activeTarget = target
    }

    func clearActiveTarget() {
        setActiveTarget(nil)
    }
}

struct PusherAppKitDropContainer<Content: View>: NSViewRepresentable {
    let content: Content
    let layoutModel: PusherDragLayoutModel
    let sessionNonce: UUID
    let board: PusherBoard?
    let isEnabled: Bool
    let performDrop: @MainActor (PusherResolvedDropTarget) -> Bool

    init(
        layoutModel: PusherDragLayoutModel,
        sessionNonce: UUID,
        board: PusherBoard?,
        isEnabled: Bool,
        performDrop: @escaping @MainActor (PusherResolvedDropTarget) -> Bool,
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
        self.layoutModel = layoutModel
        self.sessionNonce = sessionNonce
        self.board = board
        self.isEnabled = isEnabled
        self.performDrop = performDrop
    }

    func makeNSView(context: Context) -> PusherDropContainerView {
        PusherDropContainerView(rootView: hostedContent)
    }

    func updateNSView(_ nsView: PusherDropContainerView, context: Context) {
        nsView.hostingView.rootView = hostedContent
        nsView.layoutModel = layoutModel
        nsView.sessionNonce = sessionNonce
        nsView.board = board
        nsView.isDropEnabled = isEnabled
        nsView.performDrop = performDrop
    }

    static func dismantleNSView(_ nsView: PusherDropContainerView, coordinator: ()) {
        nsView.unregisterDraggedTypes()
        nsView.layoutModel?.clearActiveTarget()
        nsView.performDrop = nil
    }

    private var hostedContent: AnyView {
        AnyView(
            content
                .environment(\.colorScheme, .dark)
                .foregroundStyle(.white)
        )
    }
}

@MainActor
final class PusherDropContainerView: NSView {
    private static let logger = Logger(
        subsystem: "com.scpz24.Peeker",
        category: "pusher-drag"
    )

    let hostingView: NSHostingView<AnyView>
    weak var layoutModel: PusherDragLayoutModel?
    var sessionNonce = UUID()
    var board: PusherBoard?
    var isDropEnabled = false
    var performDrop: (@MainActor (PusherResolvedDropTarget) -> Bool)?
    private var lastRejectionReason: PusherDropRejectionReason?

    override var isFlipped: Bool { true }

    init(rootView: AnyView) {
        hostingView = NSHostingView(rootView: rootView)
        super.init(frame: .zero)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        registerForDraggedTypes([.string])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        updateTarget(for: sender)
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        updateTarget(for: sender)
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        layoutModel?.clearActiveTarget()
        lastRejectionReason = nil
        Self.logger.debug("drop target exited")
    }

    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard resolveTarget(for: sender) != nil else { return false }
        sender.animatesToDestination = true
        sender.numberOfValidItemsForDrop = 1
        return true
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard let target = resolveTarget(for: sender),
              performDrop?(target) == true else {
            sender.animatesToDestination = false
            layoutModel?.clearActiveTarget()
            Self.logger.debug("drop rejected during perform")
            return false
        }

        sender.animatesToDestination = true
        sender.numberOfValidItemsForDrop = 1
        sender.enumerateDraggingItems(
            options: [],
            for: self,
            classes: [NSString.self],
            searchOptions: [:]
        ) { item, _, _ in
            item.draggingFrame = target.landingFrame
        }
        layoutModel?.clearActiveTarget()
        lastRejectionReason = nil
        Self.logger.debug(
            "drop accepted status=\(target.status.rawValue, privacy: .public) slot=\(target.insertionIndex, privacy: .public)"
        )
        return true
    }

    override func concludeDragOperation(_ sender: (any NSDraggingInfo)?) {
        layoutModel?.clearActiveTarget()
        lastRejectionReason = nil
    }

    override func draggingEnded(_ sender: any NSDraggingInfo) {
        layoutModel?.clearActiveTarget()
    }

    override func wantsPeriodicDraggingUpdates() -> Bool { true }

    private func updateTarget(for sender: any NSDraggingInfo) -> NSDragOperation {
        switch evaluateTarget(for: sender) {
        case let .accepted(target):
            lastRejectionReason = nil
            sender.numberOfValidItemsForDrop = 1
            layoutModel?.setActiveTarget(target)
            return .move
        case let .rejected(reason):
            layoutModel?.clearActiveTarget()
            if lastRejectionReason != reason {
                Self.logger.debug("drop rejected reason=\(reason.rawValue, privacy: .public)")
                lastRejectionReason = reason
            }
            return []
        }
    }

    private func resolveTarget(for sender: any NSDraggingInfo) -> PusherResolvedDropTarget? {
        guard case let .accepted(target) = evaluateTarget(for: sender) else { return nil }
        return target
    }

    private func evaluateTarget(for sender: any NSDraggingInfo) -> PusherDropEvaluation {
        guard isDropEnabled,
              let board,
              let layoutModel else { return .rejected(.outsideColumn) }
        let localLocation = convert(sender.draggingLocation, from: nil)
        let snapshot = PusherDragSessionSnapshot(
            rawValue: sender.draggingPasteboard.string(forType: .string),
            isLocal: sender.draggingSource != nil,
            itemCount: sender.draggingPasteboard.pasteboardItems?.count ?? 0,
            sourceOperationMask: sender.draggingSourceOperationMask,
            location: localLocation,
            draggedCardSize: nil
        )
        return PusherDropSessionPolicy.evaluate(
            snapshot,
            sessionNonce: sessionNonce,
            board: board,
            columns: layoutModel.columns
        )
    }
}
