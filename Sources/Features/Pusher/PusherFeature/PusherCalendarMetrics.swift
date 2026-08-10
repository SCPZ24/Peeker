import Foundation

public enum PusherCalendarMetrics {
    public static func greenOpacity(doneCount: Int, totalCount: Int) -> Double? {
        guard totalCount > 0 else { return nil }
        let ratio = min(max(Double(doneCount) / Double(totalCount), 0), 1)
        switch ratio {
        case 0:
            return 0
        case ...0.25:
            return 0.16
        case ...0.50:
            return 0.28
        case ...0.75:
            return 0.43
        default:
            return 0.62
        }
    }
}
