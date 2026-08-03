import AppKit
import Foundation
import ServiceManagement
import PeekerCore

public actor DispatchTemporalScheduler: TemporalScheduling {
    private var task: Task<Void, Never>?

    public init() {}

    public func schedule(at date: Date, action: @escaping @Sendable () -> Void) async {
        task?.cancel()
        let delay = max(0, date.timeIntervalSinceNow)
        task = Task {
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            action()
        }
    }

    public func cancelAll() async {
        task?.cancel()
        task = nil
    }
}

public struct SystemAudioNotifier: AudioNotifying {
    public init() {}

    public func playCompletionSound() async {
        await MainActor.run {
            NSSound.beep()
        }
    }
}

@MainActor
public final class LaunchAtLoginManager: LaunchAtLoginManaging {
    public init() {}

    public func status() async -> LaunchAtLoginStatus {
        switch SMAppService.mainApp.status {
        case .enabled: .enabled
        case .notRegistered: .disabled
        case .requiresApproval: .requiresApproval
        case .notFound: .notFound
        @unknown default: .notFound
        }
    }

    public func setEnabled(_ enabled: Bool) async throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try await SMAppService.mainApp.unregister()
        }
    }
}

public struct GitHubReleaseChecker: UpdateChecking {
    private let session: URLSession
    private let releasesURL = URL(string: "https://api.github.com/repos/SCPZ24/Peeker/releases")!

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func latestRelease() async throws -> AppRelease? {
        var request = URLRequest(url: releasesURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Peeker/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let releases = try JSONDecoder().decode([ReleaseResponse].self, from: data)
        guard let release = releases.first(where: { !$0.draft && !$0.prerelease }),
              let pageURL = URL(string: release.htmlURL) else { return nil }
        return AppRelease(
            version: release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV")),
            notes: release.body ?? "",
            pageURL: pageURL
        )
    }

    private struct ReleaseResponse: Decodable {
        let tagName: String
        let body: String?
        let htmlURL: String
        let draft: Bool
        let prerelease: Bool

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case body
            case htmlURL = "html_url"
            case draft
            case prerelease
        }
    }
}
