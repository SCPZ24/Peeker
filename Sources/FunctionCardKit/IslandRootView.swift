import SwiftUI
import PeekerCore

public struct IslandRootView: View {
    @Bindable private var coordinator: IslandCoordinator
    @Bindable private var displayContext: IslandDisplayContext
    private let openSettings: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        coordinator: IslandCoordinator,
        displayContext: IslandDisplayContext,
        openSettings: @escaping () -> Void
    ) {
        self.coordinator = coordinator
        self.displayContext = displayContext
        self.openSettings = openSettings
    }

    public var body: some View {
        ZStack {
            if coordinator.isExpanded {
                expandedContent
                    .transition(.opacity)
            } else {
                compactContent
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
        .clipShape(surfaceShape)
        .foregroundStyle(.white)
        .contentShape(surfaceShape)
        .onHover { hovering in
            if hovering { coordinator.pointerEntered() }
            else { coordinator.pointerExited() }
        }
        .animation(
            reduceMotion ? nil : .easeInOut(duration: coordinator.isExpanded ? 0.22 : 0.18),
            value: coordinator.presentation.base
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Peeker")
    }

    private var compactContent: some View {
        Group {
            if let card = coordinator.registry.selectedCard {
                if let physicalNotchSize = displayContext.physicalNotchSize {
                    HStack(spacing: 0) {
                        card.makeCompactLeadingView()
                            .frame(width: card.metrics.compactLeadingWidth, alignment: .trailing)
                        Color.clear
                            .frame(width: physicalNotchSize.width)
                        card.makeCompactTrailingView()
                            .frame(width: card.metrics.compactTrailingWidth, alignment: .leading)
                    }
                } else {
                    HStack(spacing: 8) {
                        card.makeCompactLeadingView()
                        card.makeCompactTrailingView()
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var expandedContent: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                ForEach(coordinator.registry.enabledCards) { card in
                    Button {
                        coordinator.select(card.id)
                    } label: {
                        Label(card.name, systemImage: card.systemImage)
                            .labelStyle(.iconOnly)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                coordinator.registry.selectedID == card.id ? Color.white.opacity(0.18) : .clear,
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(card.name)
                    .help(card.name)
                }

                Spacer(minLength: 4)

                Button(action: openSettings) {
                    Image(systemName: "gearshape.fill")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("打开设置")
            }

            coordinator.registry.selectedCard?.makeExpandedView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(14)
        .background {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { coordinator.togglePin() }
        }
    }

    private var surfaceShape: TopAttachedRoundedRectangle {
        let metrics = coordinator.isExpanded
            ? IslandSurfaceMetrics.expanded
            : IslandSurfaceMetrics.compact
        return TopAttachedRoundedRectangle(
            topCornerRadius: metrics.top,
            bottomCornerRadius: metrics.bottom
        )
    }
}
