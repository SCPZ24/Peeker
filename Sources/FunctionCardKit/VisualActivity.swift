import SwiftUI

private struct VisualActivityKey: EnvironmentKey {
    static let defaultValue = true
}

public extension EnvironmentValues {
    var isVisualActivityEnabled: Bool {
        get { self[VisualActivityKey.self] }
        set { self[VisualActivityKey.self] = newValue }
    }
}

private struct NativePresentationColorSchemeKey: EnvironmentKey {
    static let defaultValue = ColorScheme.light
}

public extension EnvironmentValues {
    var nativePresentationColorScheme: ColorScheme {
        get { self[NativePresentationColorSchemeKey.self] }
        set { self[NativePresentationColorSchemeKey.self] = newValue }
    }
}
