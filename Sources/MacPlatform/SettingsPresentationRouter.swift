@MainActor
public final class SettingsPresentationRouter {
    public typealias Action = @MainActor () -> Void

    private let willOpen: Action
    private let didOpen: Action
    private var openAction: Action?
    private var hasPendingRequest = false

    public init(
        willOpen: @escaping Action = {},
        didOpen: @escaping Action = {}
    ) {
        self.willOpen = willOpen
        self.didOpen = didOpen
    }

    public func install(_ action: @escaping Action) {
        openAction = action
        guard hasPendingRequest else { return }
        hasPendingRequest = false
        performOpen(using: action)
    }

    public func requestOpen() {
        guard let openAction else {
            hasPendingRequest = true
            return
        }
        performOpen(using: openAction)
    }

    private func performOpen(using action: Action) {
        willOpen()
        action()
        didOpen()
    }
}
