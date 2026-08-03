import Foundation

public protocol Clock: Sendable {
    func now() -> Date
}

public struct SystemClock: Clock {
    public init() {}
    public func now() -> Date { Date() }
}

public protocol TemporalScheduling: Sendable {
    func schedule(at date: Date, action: @escaping @Sendable () -> Void) async
    func cancelAll() async
}

public protocol AudioNotifying: Sendable {
    func playCompletionSound() async
}

public struct ScreenDescriptor: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let isBuiltIn: Bool

    public init(id: String, name: String, isBuiltIn: Bool) {
        self.id = id
        self.name = name
        self.isBuiltIn = isBuiltIn
    }
}

@MainActor
public protocol ScreenTopologyProviding: Sendable {
    func availableScreens() async -> [ScreenDescriptor]
    func currentMainScreenID() async -> String?
}

public enum LaunchAtLoginStatus: String, Codable, Equatable, Sendable {
    case enabled
    case disabled
    case requiresApproval
    case notFound
}

@MainActor
public protocol LaunchAtLoginManaging: Sendable {
    func status() async -> LaunchAtLoginStatus
    func setEnabled(_ enabled: Bool) async throws
}

public struct AppRelease: Codable, Equatable, Sendable {
    public let version: String
    public let notes: String
    public let pageURL: URL

    public init(version: String, notes: String, pageURL: URL) {
        self.version = version
        self.notes = notes
        self.pageURL = pageURL
    }
}

public protocol UpdateChecking: Sendable {
    func latestRelease() async throws -> AppRelease?
}

public struct SemanticVersion: Comparable, Equatable, Sendable {
    private let components: [Int]

    public init?(_ rawValue: String) {
        let normalized = rawValue.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        guard let numeric = normalized.split(separator: "-", maxSplits: 1).first else { return nil }
        let parsed = numeric.split(separator: ".").map(String.init).compactMap(Int.init)
        guard !parsed.isEmpty, parsed.count == numeric.split(separator: ".").count else { return nil }
        components = parsed
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }
}
