import AgentorFeature
import AgentorProtocol
import Foundation
import XCTest
@testable import AgentorModule

final class AgentorIntegrationManagerTests: XCTestCase {
    func testOpenCodeInstallLeavesJSONCUnchangedAndRefusesModifiedRemoval() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let config = fixture.config.appendingPathComponent("opencode/opencode.jsonc")
        try fixture.write("{\n  // keep me\n  \"theme\": \"dark\"\n}\n", to: config)
        let original = try Data(contentsOf: config)
        let manager = fixture.manager()

        try await manager.perform(.openCode, action: .install)
        XCTAssertEqual(try Data(contentsOf: config), original)
        let statuses = await manager.scan()
        XCTAssertEqual(statuses.first { $0.agent == .openCode }?.state, .integrated)

        let plugin = fixture.config.appendingPathComponent("opencode/plugins/peeker-agentor.js")
        try "\n// user change".data(using: .utf8)!.append(to: plugin)
        do {
            try await manager.perform(.openCode, action: .remove)
            XCTFail("Expected modified managed file to block removal")
        } catch let error as AgentorIntegrationError {
            guard case .managedFileModified = error else { return XCTFail("Unexpected error: \(error)") }
        }
    }

    func testClaudeInstallUsesOnlyPreToolUseQuestionHookAndPreservesOtherHooks() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let settings = fixture.home.appendingPathComponent(".claude/settings.json")
        try fixture.write(#"{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"other"}]}]},"theme":"dark"}"#, to: settings)
        let manager = fixture.manager()

        try await manager.perform(.claude, action: .install)
        let root = try JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as! [String: Any]
        let hooks = root["hooks"] as! [String: Any]
        XCTAssertNil(hooks["PermissionRequest"])
        let pre = hooks["PreToolUse"] as! [[String: Any]]
        XCTAssertTrue(pre.contains { ($0["matcher"] as? String) == "AskUserQuestion" })
        XCTAssertEqual(root["theme"] as? String, "dark")

        try await manager.perform(.claude, action: .remove)
        let removed = try JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as! [String: Any]
        let stop = ((removed["hooks"] as! [String: Any])["Stop"] as! [[String: Any]])[0]
        XCTAssertEqual(((stop["hooks"] as! [[String: Any]])[0]["command"] as? String), "other")
    }

    func testHermesProfileFailureRollsBackManagedFilesEverywhere() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.write("plugins:\n  enabled: []\n", to: fixture.hermes.appendingPathComponent("config.yaml"))
        let profile = fixture.hermes.appendingPathComponent("profiles/coder", isDirectory: true)
        try fixture.write("plugins:\n  enabled: []\n", to: profile.appendingPathComponent("config.yaml"))
        let counter = LockedCounter()
        let manager = fixture.manager { _, arguments, _ in
            if arguments.contains("enable"), counter.increment() == 2 {
                throw AgentorIntegrationError.commandFailed("profile")
            }
        }

        do {
            try await manager.perform(.hermes, action: .install)
            XCTFail("Expected profile command failure")
        } catch {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.hermes.appendingPathComponent("plugins/peeker-agentor/__init__.py").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: profile.appendingPathComponent("plugins/peeker-agentor/__init__.py").path))
    }

    func testSafeConfigSymlinkInsideHomeIsPreservedAndOutsideHomeIsRejected() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let dotfiles = fixture.home.appendingPathComponent("dotfiles", isDirectory: true)
        let target = dotfiles.appendingPathComponent("claude-settings.json")
        try fixture.write("{}", to: target)
        let settings = fixture.home.appendingPathComponent(".claude/settings.json")
        try FileManager.default.createDirectory(at: settings.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: settings, withDestinationURL: target)
        try await fixture.manager().perform(.claude, action: .install)
        XCTAssertEqual(try settings.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink, true)

        try FileManager.default.removeItem(at: settings)
        let outside = fixture.root.appendingPathComponent("outside.json")
        try fixture.write("{}", to: outside)
        try FileManager.default.createSymbolicLink(at: settings, withDestinationURL: outside)
        do {
            try await fixture.manager().perform(.claude, action: .install)
            XCTFail("Expected outside-home symlink rejection")
        } catch let error as AgentorIntegrationError {
            guard case .unsafePath = error else { return XCTFail("Unexpected error: \(error)") }
        }
    }

    func testCodexGateRestoresFalseAndHooksRemainUntrustedUntilReviewed() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.write("[features]\nhooks = false\n", to: fixture.codex.appendingPathComponent("config.toml"))
        let manager = fixture.manager()

        try await manager.perform(.codex, action: .install)
        let enabled = try String(contentsOf: fixture.codex.appendingPathComponent("config.toml"), encoding: .utf8)
        XCTAssertTrue(enabled.contains("hooks = true # peeker-agentor-managed previous=false"))
        let statuses = await manager.scan()
        XCTAssertEqual(statuses.first { $0.agent == .codex }?.state, .notIntegrated)

        try await manager.perform(.codex, action: .remove)
        let restored = try String(contentsOf: fixture.codex.appendingPathComponent("config.toml"), encoding: .utf8)
        XCTAssertTrue(restored.contains("hooks = false"))
        XCTAssertFalse(restored.contains("peeker-agentor-managed"))
    }
}

private final class Fixture {
    let root: URL
    let home: URL
    let config: URL
    let codex: URL
    let hermes: URL
    let pi: URL
    let helper: URL
    let resources: URL

    init() throws {
        root = URL(fileURLWithPath: "/tmp/agentor-integration-\(UUID().uuidString.prefix(8))", isDirectory: true)
        home = root.appendingPathComponent("home", isDirectory: true)
        config = home.appendingPathComponent(".config", isDirectory: true)
        codex = home.appendingPathComponent(".codex", isDirectory: true)
        hermes = home.appendingPathComponent(".hermes", isDirectory: true)
        pi = home.appendingPathComponent(".pi/agent", isDirectory: true)
        helper = root.appendingPathComponent("Peeker.app/Contents/MacOS/peeker-agentor-hook")
        var repository = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { repository.deleteLastPathComponent() }
        resources = repository.appendingPathComponent("Resources/Agentor", isDirectory: true)
        try FileManager.default.createDirectory(at: helper.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: helper.path, contents: Data("#!/bin/sh\n".utf8), attributes: [.posixPermissions: 0o755])
        let hermesCLI = root.appendingPathComponent("bin/hermes")
        try FileManager.default.createDirectory(at: hermesCLI.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: hermesCLI.path, contents: Data("#!/bin/sh\nexit 0\n".utf8), attributes: [.posixPermissions: 0o755])
    }

    func manager(
        commandRunner: @escaping AgentorIntegrationManager.CommandRunner = { _, _, _ in }
    ) -> AgentorIntegrationManager {
        AgentorIntegrationManager(environment: AgentorIntegrationEnvironment(
            homeDirectory: home,
            configurationDirectory: config,
            codexHome: codex,
            hermesHome: hermes,
            piHome: pi,
            helperURL: helper,
            resourcesURL: resources,
            executableSearchPaths: [root.appendingPathComponent("bin")],
            applicationDirectories: []
        ), commandRunner: commandRunner)
    }

    func write(_ value: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(value.utf8).write(to: url)
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return value
    }
}

private extension Data {
    func append(to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: self)
    }
}
