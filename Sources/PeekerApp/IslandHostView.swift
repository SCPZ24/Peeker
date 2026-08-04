import SwiftUI
import FunctionCardKit
import MacPlatform

struct IslandHostView: View {
    @Environment(\.openSettings) private var openSettings

    let coordinator: IslandCoordinator
    let displayContext: IslandDisplayContext
    let settingsRouter: SettingsPresentationRouter

    var body: some View {
        IslandRootView(
            coordinator: coordinator,
            displayContext: displayContext
        ) {
            settingsRouter.requestOpen()
        }
        .onAppear {
            let action = openSettings
            settingsRouter.install {
                action()
            }
        }
    }
}
