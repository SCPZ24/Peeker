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
        let surface = coordinator.surfaceDescription
        let isResting = surfaceIsResting(surface)

        ZStack(alignment: .top) {
            ZStack {
                expandedContent
                    .opacity(IslandContentTransition.expandedOpacity(
                        expansion: displayContext.expansionTarget,
                        isResting: isResting
                    ))
                    .allowsHitTesting(interactivity.expandedAllowsHitTesting)
                    .accessibilityHidden(!interactivity.expandedAllowsHitTesting)

                collapsedContent(surface)
                    .opacity(1 - displayContext.expansionTarget)
                    .allowsHitTesting(interactivity.compactAllowsHitTesting)
                    .accessibilityHidden(!interactivity.compactAllowsHitTesting)
            }
            .frame(width: surfaceSize.width, height: surfaceSize.height)
            .onGeometryChange(for: CGSize.self) { $0.size } action: {
                displayContext.updatePresentationSurfaceSize($0)
            }
            .background(displayContext.drawsBlackSurface ? Color.black : Color.clear)
            .clipShape(surfaceShape)
            .foregroundStyle(.white)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering { coordinator.pointerEntered() }
                else { coordinator.pointerExited() }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Peeker")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private func collapsedContent(_ surface: IslandSurfaceDescription) -> some View {
        switch surface {
        case .resting:
            Color.clear.accessibilityLabel("打开 Peeker")
        case .compact:
            compactContent
        case let .prompt(prompt):
            promptContent(prompt)
        case .expanded:
            Color.clear
        }
    }

    private var compactContent: some View {
        Group {
            if let card = coordinator.registry.compactCard,
               let provider = card.compactProvider {
                if let physicalNotchSize = displayContext.physicalNotchSize {
                    let sideReservation = IslandCompactLayout.sideReservation(
                        leadingWidth: card.metrics.compactLeadingWidth,
                        trailingWidth: card.metrics.compactTrailingWidth
                    )
                    HStack(spacing: 0) {
                        provider.makeLeadingView()
                            .frame(width: sideReservation, alignment: .leading)
                            .clipped()
                        Color.clear.frame(width: physicalNotchSize.width)
                        provider.makeTrailingView()
                            .frame(width: sideReservation, alignment: .trailing)
                            .clipped()
                    }
                } else {
                    HStack(spacing: 0) {
                        provider.makeLeadingView()
                        Spacer(minLength: 8)
                        provider.makeTrailingView()
                    }
                }
            }
        }
        .padding(.horizontal, IslandCompactLayout.horizontalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func promptContent(_ prompt: FunctionCardPrompt) -> some View {
        HStack(spacing: 10) {
            Image(systemName: prompt.systemImage)
                .font(.title3.weight(.semibold))
            VStack(alignment: .leading, spacing: 2) {
                Text(prompt.moduleName).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(prompt.summary).font(.subheadline).lineLimit(1).truncationMode(.tail)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.top, displayContext.physicalNotchSize == nil ? 4 : displayContext.physicalNotchSize!.height)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var expandedContent: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                ForEach(coordinator.registry.enabledCards) { card in
                    Button { coordinator.select(card.id) } label: {
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
                    Image(systemName: "gearshape.fill").frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("打开设置")
            }

            coordinator.registry.selectedCard?.makeExpandedView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(IslandExpandedLayout.contentInsets)
        .background {
            Color.clear.contentShape(Rectangle()).onTapGesture { coordinator.togglePin() }
        }
    }

    private func surfaceIsResting(_ surface: IslandSurfaceDescription) -> Bool {
        if case .resting = surface { return true }
        return false
    }

    private var surfaceShape: TopAttachedRoundedRectangle {
        let metrics = IslandSurfaceMetrics.cornerRadii(expansion: displayContext.expansionTarget)
        return TopAttachedRoundedRectangle(topCornerRadius: metrics.top, bottomCornerRadius: metrics.bottom)
    }

    private var surfaceSize: CGSize {
        IslandSurfaceLayout.size(
            compact: displayContext.compactSurfaceSize,
            expanded: displayContext.expandedSurfaceSize,
            expansion: displayContext.expansionTarget
        )
    }
}
