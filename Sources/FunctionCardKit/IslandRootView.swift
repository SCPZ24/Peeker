import SwiftUI
import PeekerCore

public struct IslandRootView: View {
    @Bindable private var coordinator: IslandCoordinator
    private let openSettings: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(coordinator: IslandCoordinator, openSettings: @escaping () -> Void) {
        self.coordinator = coordinator
        self.openSettings = openSettings
    }

    public var body: some View {
        Group {
            if coordinator.isExpanded {
                expandedContent
            } else {
                compactContent
            }
        }
        .frame(width: width, height: height)
        .background(.black, in: RoundedRectangle(cornerRadius: coordinator.isExpanded ? 22 : 19))
        .foregroundStyle(.white)
        .contentShape(RoundedRectangle(cornerRadius: coordinator.isExpanded ? 22 : 19))
        .onHover { hovering in
            if hovering { coordinator.pointerEntered() }
            else { coordinator.pointerExited() }
        }
        .onTapGesture { coordinator.togglePin() }
        .animation(
            reduceMotion ? nil : .easeInOut(duration: coordinator.isExpanded ? 0.22 : 0.18),
            value: coordinator.presentation.base
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Peeker")
    }

    private var compactContent: some View {
        coordinator.registry.selectedCard?.makeCompactView()
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
                            .labelStyle(.titleAndIcon)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                coordinator.registry.selectedID == card.id ? Color.white.opacity(0.18) : .clear,
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(card.name)
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
    }

    private var width: CGFloat {
        guard let metrics = coordinator.registry.selectedCard?.metrics else { return 280 }
        return coordinator.isExpanded ? metrics.expandedWidth : min(460, max(280, metrics.compactWidth))
    }

    private var height: CGFloat {
        guard let metrics = coordinator.registry.selectedCard?.metrics else { return 38 }
        return coordinator.isExpanded ? metrics.expandedHeight : metrics.compactHeight
    }
}
