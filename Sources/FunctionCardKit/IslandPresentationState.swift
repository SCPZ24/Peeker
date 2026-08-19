import PeekerCore

public enum IslandBaseState: Equatable, Sendable {
    case resting
    case compact
    case prompt
    case hoverExpanded(featureID: FeatureID)
    case pinnedExpanded(featureID: FeatureID)
}

public struct CollapseBlockers: Equatable, Sendable {
    public var isPopoverPresented: Bool
    public var isDragging: Bool
    public var isEditingText: Bool

    public init(
        isPopoverPresented: Bool = false,
        isDragging: Bool = false,
        isEditingText: Bool = false
    ) {
        self.isPopoverPresented = isPopoverPresented
        self.isDragging = isDragging
        self.isEditingText = isEditingText
    }

    public var isActive: Bool {
        isPopoverPresented || isDragging || isEditingText
    }
}

public struct IslandPresentationState: Equatable, Sendable {
    public private(set) var base: IslandBaseState
    public var blockers: CollapseBlockers
    private var popoverWasPinned = false

    public init(base: IslandBaseState = .compact, blockers: CollapseBlockers = .init()) {
        self.base = base
        self.blockers = blockers
    }

    public var canAutomaticallyCollapse: Bool {
        !blockers.isActive && {
            if case .hoverExpanded = base { return true }
            return false
        }()
    }

    public mutating func pointerEntered(featureID: FeatureID) {
        switch base {
        case .resting, .compact, .prompt:
            base = .hoverExpanded(featureID: featureID)
        case .hoverExpanded, .pinnedExpanded:
            break
        }
    }

    public mutating func pointerExited() {
        guard canAutomaticallyCollapse else { return }
        base = .compact
    }

    public mutating func togglePin() {
        switch base {
        case .resting, .compact, .prompt:
            break
        case let .hoverExpanded(featureID):
            base = .pinnedExpanded(featureID: featureID)
        case let .pinnedExpanded(featureID):
            base = .hoverExpanded(featureID: featureID)
        }
    }

    public mutating func escape(pointerIsInside: Bool) {
        guard !blockers.isPopoverPresented else { return }
        switch base {
        case let .pinnedExpanded(featureID):
            base = pointerIsInside ? .hoverExpanded(featureID: featureID) : .compact
        case .hoverExpanded where !pointerIsInside:
            base = .compact
        default:
            break
        }
    }

    public mutating func setPopoverPresented(_ presented: Bool) {
        if presented {
            if case .pinnedExpanded = base { popoverWasPinned = true }
            blockers.isPopoverPresented = true
            return
        }

        blockers.isPopoverPresented = false
        if popoverWasPinned, case let .hoverExpanded(featureID) = base {
            base = .pinnedExpanded(featureID: featureID)
        }
        popoverWasPinned = false
    }

    public mutating func select(featureID: FeatureID) {
        switch base {
        case .resting, .compact, .prompt:
            break
        case .hoverExpanded:
            base = .hoverExpanded(featureID: featureID)
        case .pinnedExpanded:
            base = .pinnedExpanded(featureID: featureID)
        }
    }
}
