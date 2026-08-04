import SwiftUI
import PeekerCore

public struct IslandRootView: View {
    @Bindable private var coordinator: IslandCoordinator
    @Bindable private var displayContext: IslandDisplayContext
    private let openSettings: () -> Void

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
        let interactivity = IslandContentInteractivity(isExpanded: coordinator.isExpanded)

        ZStack(alignment: .top) {
            ZStack {
                expandedContent
                    .opacity(displayContext.expansionTarget)
                    .allowsHitTesting(interactivity.expandedAllowsHitTesting)
                    .accessibilityHidden(!interactivity.expandedAllowsHitTesting)

                compactContent
                    .opacity(1 - displayContext.expansionTarget)
                    .allowsHitTesting(interactivity.compactAllowsHitTesting)
                    .accessibilityHidden(!interactivity.compactAllowsHitTesting)
            }
            .frame(width: surfaceSize.width, height: surfaceSize.height)
            .onGeometryChange(for: CGSize.self) { proxy in
                proxy.size
            } action: { size in
                displayContext.updatePresentationSurfaceSize(size)
            }
            .background(.black)
            .clipShape(surfaceShape)
            .foregroundStyle(.white)
            .contentShape(surfaceShape)
            .onHover { hovering in
                if hovering { coordinator.pointerEntered() }
                else { coordinator.pointerExited() }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Peeker")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var compactContent: some View {
        Group {
            if let card = coordinator.registry.selectedCard {
                if let physicalNotchSize = displayContext.physicalNotchSize {
                    let sideReservation = IslandCompactLayout.sideReservation(
                        leadingWidth: card.metrics.compactLeadingWidth,
                        trailingWidth: card.metrics.compactTrailingWidth
                    )
                    HStack(spacing: 0) {
                        card.makeCompactLeadingView()
                            .frame(width: sideReservation, alignment: .leading)
                            .clipped()
                        Color.clear
                            .frame(width: physicalNotchSize.width)
                        card.makeCompactTrailingView()
                            .frame(width: sideReservation, alignment: .trailing)
                            .clipped()
                    }
                } else {
                    HStack(spacing: 0) {
                        card.makeCompactLeadingView()
                        Spacer(minLength: 8)
                        card.makeCompactTrailingView()
                    }
                }
            }
        }
        .padding(.horizontal, IslandCompactLayout.horizontalPadding)
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
        .padding(IslandExpandedLayout.contentInsets)
        .background {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { coordinator.togglePin() }
        }
    }

    private var surfaceShape: TopAttachedRoundedRectangle {
        let metrics = IslandSurfaceMetrics.cornerRadii(expansion: displayContext.expansionTarget)
        return TopAttachedRoundedRectangle(
            topCornerRadius: metrics.top,
            bottomCornerRadius: metrics.bottom
        )
    }

    private var surfaceSize: CGSize {
        IslandSurfaceLayout.size(
            compact: displayContext.compactSurfaceSize,
            expanded: displayContext.expandedSurfaceSize,
            expansion: displayContext.expansionTarget
        )
    }
}
