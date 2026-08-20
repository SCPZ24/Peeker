public enum PeekerPresetColor: String, CaseIterable, Identifiable, Sendable {
    case red = "#FF3B30"
    case lightYellow = "#FFD60A"
    case lakeBlue = "#4F9DFF"
    case lightGreen = "#34C759"
    case purple = "#AF52DE"
    case pink = "#FF2D55"
    case cyan = "#64D2FF"

    public var id: String { rawValue }

    public var localizedName: String {
        switch self {
        case .red: "正红"
        case .lightYellow: "浅黄"
        case .lakeBlue: "湖蓝"
        case .lightGreen: "浅绿"
        case .purple: "紫"
        case .pink: "粉"
        case .cyan: "青"
        }
    }
}
