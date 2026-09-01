import Observation

@MainActor
@Observable
final class TargetorExpansionHoldController {
    typealias Publisher = @MainActor (Bool) -> Void

    private(set) var isCheckinPending = false
    private(set) var blocksCollapse = false

    @ObservationIgnored private var isAttached = false
    @ObservationIgnored private var isDragActive = false
    @ObservationIgnored private var isFeedbackVisible = false
    @ObservationIgnored private var publish: Publisher?

    func attach(publish: @escaping Publisher) {
        self.publish = publish
        isAttached = true
        synchronize()
    }

    func detach() {
        guard isAttached else { return }
        isAttached = false
        isDragActive = false
        isCheckinPending = false
        isFeedbackVisible = false
        synchronize(forceRelease: true)
        publish = nil
    }

    func dragBegan() {
        guard isAttached else { return }
        isDragActive = true
        synchronize()
    }

    func dragEnded() {
        guard isAttached else { return }
        isDragActive = false
        synchronize()
    }

    func dropAccepted() {
        guard isAttached else { return }
        isCheckinPending = true
        synchronize()
    }

    func checkinCompleted(feedbackVisible: Bool) {
        guard isAttached else { return }
        isCheckinPending = false
        isFeedbackVisible = feedbackVisible
        synchronize()
    }

    func feedbackChanged(isVisible: Bool) {
        guard isAttached else { return }
        isFeedbackVisible = isVisible
        synchronize()
    }

    private func synchronize(forceRelease: Bool = false) {
        let nextValue = forceRelease
            ? false
            : isAttached && (isDragActive || isCheckinPending || isFeedbackVisible)
        guard blocksCollapse != nextValue else { return }
        blocksCollapse = nextValue
        publish?(nextValue)
    }
}
