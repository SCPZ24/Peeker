import AppKit
import Foundation
import Observation
import OSLog
import SwiftUI

struct TargetorDragEnvelope: Equatable, Sendable {
    private static let prefix = "peeker-targetor-checkin"
    private static let version = "v1"

    let expansionNonce: UUID
    let targetID: UUID
    let periodID: UUID

    var rawValue: String {
        [
            Self.prefix,
            Self.version,
            expansionNonce.uuidString,
            targetID.uuidString,
            periodID.uuidString,
        ].joined(separator: ":")
    }

    init(expansionNonce: UUID, targetID: UUID, periodID: UUID) {
        self.expansionNonce = expansionNonce
        self.targetID = targetID
        self.periodID = periodID
    }

    init?(rawValue: String) {
        let components = rawValue.split(separator: ":", omittingEmptySubsequences: false)
        guard components.count == 5,
              components[0] == Self.prefix,
              components[1] == Self.version,
              let expansionNonce = UUID(uuidString: String(components[2])),
              let targetID = UUID(uuidString: String(components[3])),
              let periodID = UUID(uuidString: String(components[4]))
        else { return nil }
        self.expansionNonce = expansionNonce
        self.targetID = targetID
        self.periodID = periodID
    }
}

struct TargetorDragSessionSnapshot {
    let rawValue: String?
    let isLocal: Bool
    let itemCount: Int
    let sourceOperationMask: NSDragOperation
    let location: CGPoint
}

enum TargetorDropRejectionReason: String, Equatable {
    case disabled
    case externalSource
    case multipleItems
    case copyUnsupported
    case malformedPayload
    case staleExpansion
    case missingTarget
    case stalePeriod
    case completedTarget
    case outsideDropArea
    case duplicateSession
}

enum TargetorDropEvaluation: Equatable {
    case accepted(TargetorDragEnvelope)
    case rejected(TargetorDropRejectionReason)
}

enum TargetorDropSessionPolicy {
    static func evaluate(
        _ snapshot: TargetorDragSessionSnapshot,
        expansionNonce: UUID,
        targets: [TargetorTargetState],
        dropFrame: CGRect
    ) -> TargetorDropEvaluation {
        guard snapshot.isLocal else { return .rejected(.externalSource) }
        guard snapshot.itemCount == 1 else { return .rejected(.multipleItems) }
        guard snapshot.sourceOperationMask.contains(.copy) else {
            return .rejected(.copyUnsupported)
        }
        guard let rawValue = snapshot.rawValue,
              let envelope = TargetorDragEnvelope(rawValue: rawValue)
        else { return .rejected(.malformedPayload) }
        guard envelope.expansionNonce == expansionNonce else {
            return .rejected(.staleExpansion)
        }
        guard let target = targets.first(where: { $0.id == envelope.targetID }),
              let period = target.currentPeriod
        else { return .rejected(.missingTarget) }
        guard period.id == envelope.periodID else { return .rejected(.stalePeriod) }
        guard period.state != .completed else { return .rejected(.completedTarget) }
        guard !dropFrame.isEmpty, dropFrame.contains(snapshot.location) else {
            return .rejected(.outsideDropArea)
        }
        return .accepted(envelope)
    }
}

struct TargetorDraggingSequenceGate {
    private var reservedSequenceNumbers = Set<Int>()

    mutating func reserve(_ sequenceNumber: Int) -> Bool {
        reservedSequenceNumbers.insert(sequenceNumber).inserted
    }

    mutating func release(_ sequenceNumber: Int) {
        reservedSequenceNumbers.remove(sequenceNumber)
    }

    mutating func reset() {
        reservedSequenceNumbers.removeAll()
    }
}

@MainActor
@Observable
final class TargetorDragLayoutModel {
    nonisolated static let coordinateSpaceName = "targetor-appkit-drop-container"

    private(set) var dropFrame = CGRect.zero
    private(set) var targetedEnvelope: TargetorDragEnvelope?

    func updateDropFrame(_ frame: CGRect) {
        guard dropFrame != frame else { return }
        dropFrame = frame
    }

    func setTargetedEnvelope(_ envelope: TargetorDragEnvelope) {
        guard targetedEnvelope != envelope else { return }
        targetedEnvelope = envelope
    }

    func clearTargetedEnvelope() {
        guard targetedEnvelope != nil else { return }
        targetedEnvelope = nil
    }
}

struct TargetorAppKitDropContainer<Content: View>: NSViewRepresentable {
    let content: Content
    let layoutModel: TargetorDragLayoutModel
    let expansionNonce: UUID
    let targets: [TargetorTargetState]
    let isEnabled: Bool
    let performDrop: @MainActor (TargetorDragEnvelope) -> Bool
    let dragEnded: @MainActor () -> Void

    init(
        layoutModel: TargetorDragLayoutModel,
        expansionNonce: UUID,
        targets: [TargetorTargetState],
        isEnabled: Bool,
        performDrop: @escaping @MainActor (TargetorDragEnvelope) -> Bool,
        dragEnded: @escaping @MainActor () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
        self.layoutModel = layoutModel
        self.expansionNonce = expansionNonce
        self.targets = targets
        self.isEnabled = isEnabled
        self.performDrop = performDrop
        self.dragEnded = dragEnded
    }

    func makeNSView(context: Context) -> TargetorDropContainerView {
        TargetorDropContainerView(rootView: hostedContent)
    }

    func updateNSView(_ nsView: TargetorDropContainerView, context: Context) {
        nsView.hostingView.rootView = hostedContent
        nsView.layoutModel = layoutModel
        nsView.updateExpansionNonce(expansionNonce)
        nsView.targets = targets
        nsView.isDropEnabled = isEnabled
        nsView.performDrop = performDrop
        nsView.dragEnded = dragEnded
        if !isEnabled { nsView.resetTargetedState() }
    }

    static func dismantleNSView(_ nsView: TargetorDropContainerView, coordinator: ()) {
        nsView.resetTargetedState()
        nsView.unregisterDraggedTypes()
        nsView.performDrop = nil
        nsView.dragEnded = nil
        nsView.layoutModel = nil
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
final class TargetorDropContainerView: NSView {
    private static let logger = Logger(
        subsystem: "com.scpz24.Peeker",
        category: "targetor-drag"
    )

    let hostingView: NSHostingView<AnyView>
    weak var layoutModel: TargetorDragLayoutModel?
    private(set) var expansionNonce = UUID()
    var targets: [TargetorTargetState] = []
    var isDropEnabled = false
    var performDrop: (@MainActor (TargetorDragEnvelope) -> Bool)?
    var dragEnded: (@MainActor () -> Void)?
    private var sequenceGate = TargetorDraggingSequenceGate()
    private var lastRejectionReason: TargetorDropRejectionReason?
    private var lastAcceptedEnvelope: TargetorDragEnvelope?

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
        resetEvaluationState()
        Self.logger.debug("drop target exited")
    }

    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard resolveEnvelope(for: sender) != nil else { return false }
        sender.animatesToDestination = false
        sender.numberOfValidItemsForDrop = 1
        return true
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let sequenceNumber = sender.draggingSequenceNumber
        guard let envelope = resolveEnvelope(for: sender) else {
            sender.animatesToDestination = false
            resetEvaluationState()
            Self.logger.debug("drop rejected during perform")
            return false
        }
        guard sequenceGate.reserve(sequenceNumber) else {
            sender.animatesToDestination = false
            resetEvaluationState()
            Self.logger.debug("drop rejected reason=duplicateSession")
            return false
        }
        guard performDrop?(envelope) == true else {
            sequenceGate.release(sequenceNumber)
            sender.animatesToDestination = false
            resetEvaluationState()
            Self.logger.debug("drop rejected by handler")
            return false
        }

        sender.animatesToDestination = false
        sender.numberOfValidItemsForDrop = 1
        resetEvaluationState()
        Self.logger.debug("drop performed")
        return true
    }

    override func concludeDragOperation(_ sender: (any NSDraggingInfo)?) {
        resetEvaluationState()
        Self.logger.debug("drop concluded")
    }

    override func draggingEnded(_ sender: any NSDraggingInfo) {
        resetEvaluationState()
        dragEnded?()
        Self.logger.debug("drag ended")
    }

    override func wantsPeriodicDraggingUpdates() -> Bool { true }

    func updateExpansionNonce(_ nonce: UUID) {
        guard expansionNonce != nonce else { return }
        expansionNonce = nonce
        sequenceGate.reset()
        resetEvaluationState()
    }

    func resetTargetedState() {
        layoutModel?.clearTargetedEnvelope()
    }

    private func updateTarget(for sender: any NSDraggingInfo) -> NSDragOperation {
        switch evaluateEnvelope(for: sender) {
        case let .accepted(envelope):
            if lastAcceptedEnvelope != envelope {
                Self.logger.debug("drop target accepted")
            }
            lastAcceptedEnvelope = envelope
            lastRejectionReason = nil
            sender.numberOfValidItemsForDrop = 1
            layoutModel?.setTargetedEnvelope(envelope)
            return .copy
        case let .rejected(reason):
            layoutModel?.clearTargetedEnvelope()
            lastAcceptedEnvelope = nil
            if lastRejectionReason != reason {
                Self.logger.debug("drop rejected reason=\(reason.rawValue, privacy: .public)")
                lastRejectionReason = reason
            }
            return []
        }
    }

    private func resolveEnvelope(for sender: any NSDraggingInfo) -> TargetorDragEnvelope? {
        guard case let .accepted(envelope) = evaluateEnvelope(for: sender) else { return nil }
        return envelope
    }

    private func evaluateEnvelope(for sender: any NSDraggingInfo) -> TargetorDropEvaluation {
        guard isDropEnabled, let layoutModel else { return .rejected(.disabled) }
        let snapshot = TargetorDragSessionSnapshot(
            rawValue: sender.draggingPasteboard.string(forType: .string),
            isLocal: sender.draggingSource != nil,
            itemCount: sender.draggingPasteboard.pasteboardItems?.count ?? 0,
            sourceOperationMask: sender.draggingSourceOperationMask,
            location: convert(sender.draggingLocation, from: nil)
        )
        return TargetorDropSessionPolicy.evaluate(
            snapshot,
            expansionNonce: expansionNonce,
            targets: targets,
            dropFrame: layoutModel.dropFrame
        )
    }

    private func resetEvaluationState() {
        layoutModel?.clearTargetedEnvelope()
        lastAcceptedEnvelope = nil
        lastRejectionReason = nil
    }
}
