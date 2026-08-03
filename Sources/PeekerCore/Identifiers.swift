import Foundation

public struct FeatureID: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let timer = FeatureID(rawValue: "timer")
    public static let pusher = FeatureID(rawValue: "pusher")
}

public struct BusinessDayID: Codable, Hashable, Sendable {
    public let featureID: FeatureID
    public let startAtMilliseconds: Int64

    public init(featureID: FeatureID, startAtMilliseconds: Int64) {
        self.featureID = featureID
        self.startAtMilliseconds = startAtMilliseconds
    }
}

public extension Date {
    var millisecondsSince1970: Int64 {
        Int64((timeIntervalSince1970 * 1_000).rounded())
    }

    init(millisecondsSince1970: Int64) {
        self.init(timeIntervalSince1970: TimeInterval(millisecondsSince1970) / 1_000)
    }
}
