import AgentorFeature
import AgentorProtocol
import CryptoKit
import Darwin
import Foundation
import PeekerCore

struct AgentorIntegrationEnvironment: Sendable {
    let homeDirectory: URL
    let configurationDirectory: URL
    let codexHome: URL
    let hermesHome: URL
    let piHome: URL
    let helperURL: URL
    let resourcesURL: URL
    let executableSearchPaths: [URL]
    let applicationDirectories: [URL]

    static var production: AgentorIntegrationEnvironment {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let environment = ProcessInfo.processInfo.environment
        let configuration = environment["XDG_CONFIG_HOME"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? home.appendingPathComponent(".config", isDirectory: true)
        let codex = environment["CODEX_HOME"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? home.appendingPathComponent(".codex", isDirectory: true)
        let hermes = environment["HERMES_HOME"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? home.appendingPathComponent(".hermes", isDirectory: true)
        let pathURLs = (environment["PATH"] ?? "").split(separator: ":").map { URL(fileURLWithPath: String($0), isDirectory: true) }
            + [URL(fileURLWithPath: "/opt/homebrew/bin"), URL(fileURLWithPath: "/usr/local/bin"), home.appendingPathComponent(".local/bin")]
        return AgentorIntegrationEnvironment(
            homeDirectory: home,
            configurationDirectory: configuration,
            codexHome: codex,
            hermesHome: hermes,
            piHome: home.appendingPathComponent(".pi/agent", isDirectory: true),
            helperURL: Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/peeker-agentor-hook"),
            resourcesURL: Bundle.main.resourceURL?.appendingPathComponent("Agentor", isDirectory: true)
                ?? Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/Agentor", isDirectory: true),
            executableSearchPaths: Array(Dictionary(grouping: pathURLs, by: \.path).keys.map { URL(fileURLWithPath: $0) }),
            applicationDirectories: [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications")]
        )
    }
}

enum AgentorIntegrationError: LocalizedError, Equatable {
    case agentNotFound
    case resourcesMissing
    case malformedConfiguration(String)
    case unsafePath(String)
    case managedFileModified(String)
    case commandFailed(String)
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .agentNotFound: "未发现 Agent，未写入任何配置。"
        case .resourcesMissing: "Peeker.app 缺少 Agentor 适配器资源。"
        case let .malformedConfiguration(path): "配置无法安全解析：\(path)"
        case let .unsafePath(path): "路径不满足安全写入条件：\(path)"
        case let .managedFileModified(path): "托管文件已被修改，请手工清理：\(path)"
        case let .commandFailed(message): "Agent 插件命令失败：\(message)"
        case let .writeFailed(path): "无法原子写入：\(path)"
        }
    }
    var localizedMessage: LocalizedMessage {
        switch self {
        case .agentNotFound: L10n.message("未发现 Agent，未写入任何配置。")
        case .resourcesMissing: L10n.message("Peeker.app 缺少 Agentor 适配器资源。")
        case let .malformedConfiguration(path): L10n.message("配置无法安全解析：%1$@", path)
        case let .unsafePath(path): L10n.message("路径不满足安全写入条件：%1$@", path)
        case let .managedFileModified(path): L10n.message("托管文件已被修改，请手工清理：%1$@", path)
        case let .commandFailed(message): L10n.message("Agent 插件命令失败：%1$@", message)
        case let .writeFailed(path): L10n.message("无法原子写入：%1$@", path)
        }
    }
}

private struct AgentorBundleResourceManifest: Codable {
    let schemaVersion: Int
    let resourceVersion: Int
    let placeholder: String
    let files: [String: String]
}

private struct AgentorManagedInstallationManifest: Codable {
    let owner: String
    let schemaVersion: Int
    let resourceVersion: Int
    let helperPath: String
    let files: [String: String]
}

private struct AgentorFileSnapshot {
    let url: URL
    let data: Data?
    let permissions: NSNumber?
}

actor AgentorIntegrationManager {
    typealias CommandRunner = @Sendable (_ executable: URL, _ arguments: [String], _ environment: [String: String]) throws -> Void

    private let environment: AgentorIntegrationEnvironment
    private let commandRunner: CommandRunner
    private let fileManager = FileManager.default

    init(
        environment: AgentorIntegrationEnvironment = .production,
        commandRunner: @escaping CommandRunner = AgentorIntegrationManager.runCommand
    ) {
        self.environment = environment
        self.commandRunner = commandRunner
    }

    func scan() -> [AgentIntegrationStatus] {
        AgentKind.allCases.map(scan)
    }

    func perform(_ agent: AgentKind, action: AgentIntegrationAction) throws {
        switch action {
        case .install: try install(agent)
        case .remove: try remove(agent)
        }
    }

    private func scan(_ agent: AgentKind) -> AgentIntegrationStatus {
        let now = Date()
        let evidence = discoveryEvidence(agent)
        let capabilities: [AgentCapability] = agent == .claude || agent == .openCode ? [.status, .answer] : [.status, .reminder]
        guard !evidence.isEmpty else {
            return AgentIntegrationStatus(agent: agent, state: .notFound, detail: "标准路径中未发现安装证据。", detailMessage: L10n.message("标准路径中未发现安装证据。"), scannedAt: now, capabilities: capabilities)
        }
        do {
            let detail = try integrationDetail(agent)
            return AgentIntegrationStatus(
                agent: agent, state: detail.integrated ? .integrated : .notIntegrated,
                paths: evidence + detail.paths, detail: detail.message, detailMessage: L10n.message(detail.message), scannedAt: now, capabilities: capabilities
            )
        } catch {
            return AgentIntegrationStatus(
                agent: agent, state: .notIntegrated, paths: evidence,
                detail: error.localizedDescription, detailMessage: (error as? AgentorIntegrationError)?.localizedMessage, scannedAt: now, capabilities: capabilities
            )
        }
    }

    private func install(_ agent: AgentKind) throws {
        guard !discoveryEvidence(agent).isEmpty else { throw AgentorIntegrationError.agentNotFound }
        guard fileManager.isExecutableFile(atPath: environment.helperURL.path),
              fileManager.fileExists(atPath: environment.resourcesURL.appendingPathComponent("manifest.json").path) else {
            throw AgentorIntegrationError.resourcesMissing
        }
        switch agent {
        case .claude: try installHookConfiguration(at: claudeSettingsURL, agent: .claude)
        case .openCode: try installManagedFiles(agent: .openCode, mappings: openCodeMappings, manifestURL: openCodeManifestURL)
        case .hermes: try installHermes()
        case .pi: try installManagedFiles(agent: .pi, mappings: piMappings, manifestURL: piManifestURL)
        case .codex:
            let snapshots = [snapshot((codexHooksURL, Data(), 0)), snapshot((codexConfigURL, Data(), 0))]
            do {
                try installHookConfiguration(at: codexHooksURL, agent: .codex)
                try enableCodexHooks()
            } catch {
                for snapshot in snapshots.reversed() { try? restore(snapshot) }
                throw error
            }
        }
    }

    private func remove(_ agent: AgentKind) throws {
        switch agent {
        case .claude: try removeHookConfiguration(at: claudeSettingsURL)
        case .openCode:
            try removeManagedFiles(mappings: openCodeMappings, manifestURL: openCodeManifestURL)
        case .hermes: try removeHermes()
        case .pi: try removeManagedFiles(mappings: piMappings, manifestURL: piManifestURL)
        case .codex:
            try removeHookConfiguration(at: codexHooksURL)
            try restoreCodexHooksGate()
        }
    }

    private func integrationDetail(_ agent: AgentKind) throws -> (integrated: Bool, paths: [String], message: String) {
        switch agent {
        case .claude:
            let present = try hookConfigurationContainsMarker(claudeSettingsURL)
            return (present, [claudeSettingsURL.path], present ? "状态与 PreToolUse 问题 hook 已接入。" : "缺少 Peeker hook。")
        case .openCode:
            let valid = try managedFilesAreValid(mappings: openCodeMappings, manifestURL: openCodeManifestURL)
            return (valid, [openCodeMappings[0].destination.path], valid ? "全局自动发现 plugin 完整。" : "plugin 缺失、过期或已修改。")
        case .hermes:
            let homes = hermesHomes
            let valid = try homes.allSatisfy { home in
                let mappings = hermesMappings(home)
                return try managedFilesAreValid(mappings: mappings, manifestURL: home.appendingPathComponent("plugins/peeker-agentor/.peeker-agentor-manifest.json"))
                    && hermesConfigEnablesPlugin(home)
            }
            return (valid, homes.map(\.path), valid ? "所有 Hermes profile 已接入。" : "一个或多个 profile 未完整启用。")
        case .pi:
            let valid = try managedFilesAreValid(mappings: piMappings, manifestURL: piManifestURL)
            return (valid, [piMappings[0].destination.path], valid ? "全局 extension 完整。" : "extension 缺失、过期或已修改。")
        case .codex:
            let hooks = try hookConfigurationContainsMarker(codexHooksURL)
            let gate = codexHooksGateEnabled()
            let trusted = codexManagedHooksTrusted()
            let integrated = hooks && gate && trusted
            let message = !hooks ? "缺少 Peeker hooks。" : (!gate ? "Codex hooks 功能未启用。" : (!trusted ? "请在 Codex 执行 /hooks 完成信任后刷新。" : "hooks 已启用并信任。"))
            return (integrated, [codexHooksURL.path, codexConfigURL.path], message)
        }
    }

    private var claudeSettingsURL: URL { environment.homeDirectory.appendingPathComponent(".claude/settings.json") }
    private var openCodeRoot: URL { environment.configurationDirectory.appendingPathComponent("opencode", isDirectory: true) }
    private var openCodeManifestURL: URL { openCodeRoot.appendingPathComponent("plugins/.peeker-agentor-manifest.json") }
    private var piManifestURL: URL { environment.piHome.appendingPathComponent("extensions/peeker-agentor/.peeker-agentor-manifest.json") }
    private var codexHooksURL: URL { environment.codexHome.appendingPathComponent("hooks.json") }
    private var codexConfigURL: URL { environment.codexHome.appendingPathComponent("config.toml") }

    private var openCodeMappings: [(source: String, destination: URL)] {
        [("opencode/peeker-agentor.js", openCodeRoot.appendingPathComponent("plugins/peeker-agentor.js"))]
    }

    private var piMappings: [(source: String, destination: URL)] {
        [("pi/peeker-agentor/index.ts", environment.piHome.appendingPathComponent("extensions/peeker-agentor/index.ts"))]
    }

    private func hermesMappings(_ home: URL) -> [(source: String, destination: URL)] {
        [
            ("hermes/peeker-agentor/__init__.py", home.appendingPathComponent("plugins/peeker-agentor/__init__.py")),
            ("hermes/peeker-agentor/plugin.yaml", home.appendingPathComponent("plugins/peeker-agentor/plugin.yaml")),
        ]
    }

    private var hermesHomes: [URL] {
        var homes = [environment.hermesHome]
        let profiles = environment.hermesHome.appendingPathComponent("profiles", isDirectory: true)
        if let children = try? fileManager.contentsOfDirectory(at: profiles, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
            homes.append(contentsOf: children.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true })
        }
        return homes
    }

    private func discoveryEvidence(_ agent: AgentKind) -> [String] {
        var values: [String] = []
        for url in configurationEvidence(agent) where fileManager.fileExists(atPath: url.path) { values.append(url.path) }
        let names: [String]
        let apps: [String]
        switch agent {
        case .claude: names = ["claude"]; apps = ["Claude.app"]
        case .openCode: names = ["opencode"]; apps = ["OpenCode.app"]
        case .hermes: names = ["hermes"]; apps = ["Hermes.app"]
        case .pi: names = ["pi"]; apps = ["Pi.app"]
        case .codex: names = ["codex"]; apps = ["Codex.app", "ChatGPT.app"]
        }
        for directory in environment.executableSearchPaths {
            for name in names {
                let url = directory.appendingPathComponent(name)
                if fileManager.isExecutableFile(atPath: url.path) { values.append(url.path) }
            }
        }
        for directory in environment.applicationDirectories {
            for app in apps {
                let url = directory.appendingPathComponent(app)
                if fileManager.fileExists(atPath: url.path) { values.append(url.path) }
            }
        }
        return Array(Set(values)).sorted()
    }

    private func configurationEvidence(_ agent: AgentKind) -> [URL] {
        switch agent {
        case .claude: [environment.homeDirectory.appendingPathComponent(".claude"), claudeSettingsURL]
        case .openCode: [openCodeRoot.appendingPathComponent("opencode.jsonc"), openCodeRoot.appendingPathComponent("opencode.json"), openCodeRoot.appendingPathComponent("config.json")]
        case .hermes: [environment.hermesHome.appendingPathComponent("config.yaml")]
        case .pi: [environment.piHome]
        case .codex: [codexConfigURL, codexHooksURL]
        }
    }

    private func installHookConfiguration(at url: URL, agent: AgentKind) throws {
        var root = try readJSONObject(url)
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        hooks = removingManagedHooks(hooks)
        for spec in hookSpecs(agent) {
            var groups = hooks[spec.event] as? [[String: Any]] ?? []
            var group: [String: Any] = [
                "hooks": [["type": "command", "command": command(agent: agent, operation: spec.operation), "timeout": spec.timeout]],
            ]
            if let matcher = spec.matcher { group["matcher"] = matcher }
            groups.append(group)
            hooks[spec.event] = groups
        }
        root["hooks"] = hooks
        try writeJSON(root, to: url)
    }

    private func removeHookConfiguration(at url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        var root = try readJSONObject(url)
        guard let hooks = root["hooks"] as? [String: Any] else { return }
        let filtered = removingManagedHooks(hooks)
        if filtered.isEmpty { root.removeValue(forKey: "hooks") }
        else { root["hooks"] = filtered }
        try writeJSON(root, to: url)
    }

    private func hookConfigurationContainsMarker(_ url: URL) throws -> Bool {
        guard fileManager.fileExists(atPath: url.path) else { return false }
        let root = try readJSONObject(url)
        guard let hooks = root["hooks"] as? [String: Any] else { return false }
        let count = hooks.values.compactMap { $0 as? [[String: Any]] }.flatMap { $0 }.flatMap { ($0["hooks"] as? [[String: Any]]) ?? [] }
            .filter { ($0["command"] as? String)?.contains("PEEKER_AGENTOR_MANAGED=1") == true }.count
        return count == hookSpecs(url == claudeSettingsURL ? .claude : .codex).count
    }

    private func removingManagedHooks(_ hooks: [String: Any]) -> [String: Any] {
        var result: [String: Any] = [:]
        for (event, value) in hooks {
            guard let groups = value as? [[String: Any]] else { result[event] = value; continue }
            let filteredGroups = groups.compactMap { group -> [String: Any]? in
                guard let commands = group["hooks"] as? [[String: Any]] else { return group }
                let kept = commands.filter { ($0["command"] as? String)?.contains("PEEKER_AGENTOR_MANAGED=1") != true }
                guard !kept.isEmpty else { return nil }
                var copy = group
                copy["hooks"] = kept
                return copy
            }
            if !filteredGroups.isEmpty { result[event] = filteredGroups }
        }
        return result
    }

    private func hookSpecs(_ agent: AgentKind) -> [(event: String, matcher: String?, operation: String, timeout: Int)] {
        if agent == .claude {
            return [
                ("UserPromptSubmit", nil, "state", 2), ("PreToolUse", ".*", "state", 2),
                ("PreToolUse", "AskUserQuestion", "question", 600), ("PostToolUse", ".*", "state", 2),
                ("Stop", nil, "state", 2), ("StopFailure", nil, "state", 2),
                ("SessionEnd", nil, "state", 2), ("SubagentStart", ".*", "state", 2), ("SubagentStop", ".*", "state", 2),
            ]
        }
        return [
            ("UserPromptSubmit", nil, "state", 2), ("PreToolUse", ".*", "state", 2),
            ("PostToolUse", ".*", "state", 2), ("Stop", nil, "state", 2),
            ("SessionEnd", nil, "state", 2), ("SubagentStart", ".*", "state", 2), ("SubagentStop", ".*", "state", 2),
        ]
    }

    private func command(agent: AgentKind, operation: String) -> String {
        let helper = shellQuote(environment.helperURL.path)
        return "PEEKER_AGENTOR_MANAGED=1; export PEEKER_AGENTOR_MANAGED; if [ -x \(helper) ]; then exec \(helper) \(agent.rawValue) \(operation); fi"
    }

    private func shellQuote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    private func readJSONObject(_ url: URL) throws -> [String: Any] {
        guard fileManager.fileExists(atPath: url.path) else { return [:] }
        let safe = try safeConfigurationURL(url)
        do {
            let value = try JSONSerialization.jsonObject(with: Data(contentsOf: safe))
            guard let object = value as? [String: Any] else { throw AgentorIntegrationError.malformedConfiguration(url.path) }
            return object
        } catch let error as AgentorIntegrationError { throw error }
        catch { throw AgentorIntegrationError.malformedConfiguration(url.path) }
    }

    private func writeJSON(_ object: [String: Any], to url: URL) throws {
        guard JSONSerialization.isValidJSONObject(object) else { throw AgentorIntegrationError.malformedConfiguration(url.path) }
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) + Data([0x0A])
        try writeAtomically(data, to: try writableConfigurationURL(url), defaultPermissions: 0o600)
    }

    private func installManagedFiles(
        agent: AgentKind,
        mappings: [(source: String, destination: URL)],
        manifestURL: URL
    ) throws {
        if fileManager.fileExists(atPath: manifestURL.path) {
            guard try managedFilesAreValid(mappings: mappings, manifestURL: manifestURL) else {
                throw AgentorIntegrationError.managedFileModified(manifestURL.path)
            }
        } else if mappings.contains(where: { fileManager.fileExists(atPath: $0.destination.path) }) {
            throw AgentorIntegrationError.unsafePath(mappings.first { fileManager.fileExists(atPath: $0.destination.path) }!.destination.path)
        }
        let bundle = try bundleManifest()
        var writes: [(URL, Data, Int)] = []
        var hashes: [String: String] = [:]
        for mapping in mappings {
            try rejectManagedSymlink(mapping.destination)
            let source = environment.resourcesURL.appendingPathComponent(mapping.source)
            guard let sourceData = try? Data(contentsOf: source),
                  sha256(sourceData) == bundle.files[mapping.source],
                  let text = String(data: sourceData, encoding: .utf8) else { throw AgentorIntegrationError.resourcesMissing }
            let rendered = text.replacingOccurrences(of: bundle.placeholder, with: environment.helperURL.path)
            let data = Data(rendered.utf8)
            hashes[mapping.destination.lastPathComponent] = sha256(data)
            writes.append((mapping.destination, data, 0o644))
        }
        let installed = AgentorManagedInstallationManifest(
            owner: "com.scpz24.Peeker", schemaVersion: 1, resourceVersion: bundle.resourceVersion,
            helperPath: environment.helperURL.path, files: hashes
        )
        writes.append((manifestURL, try JSONEncoder.agentor.encode(installed), 0o600))
        try writeTransaction(writes)
    }

    private func managedFilesAreValid(
        mappings: [(source: String, destination: URL)],
        manifestURL: URL
    ) throws -> Bool {
        guard fileManager.fileExists(atPath: manifestURL.path) else { return false }
        try rejectManagedSymlink(manifestURL)
        let installed: AgentorManagedInstallationManifest
        do { installed = try JSONDecoder.agentor.decode(AgentorManagedInstallationManifest.self, from: Data(contentsOf: manifestURL)) }
        catch { throw AgentorIntegrationError.managedFileModified(manifestURL.path) }
        guard installed.owner == "com.scpz24.Peeker", installed.schemaVersion == 1 else {
            throw AgentorIntegrationError.managedFileModified(manifestURL.path)
        }
        let bundle = try bundleManifest()
        guard installed.resourceVersion == bundle.resourceVersion else { return false }
        for mapping in mappings {
            try rejectManagedSymlink(mapping.destination)
            guard let data = try? Data(contentsOf: mapping.destination),
                  installed.files[mapping.destination.lastPathComponent] == sha256(data),
                  let text = String(data: data, encoding: .utf8),
                  let expected = bundle.files[mapping.source] else { return false }
            let normalized = Data(text.replacingOccurrences(of: installed.helperPath, with: bundle.placeholder).utf8)
            guard sha256(normalized) == expected else { throw AgentorIntegrationError.managedFileModified(mapping.destination.path) }
        }
        return true
    }

    private func removeManagedFiles(mappings: [(source: String, destination: URL)], manifestURL: URL) throws {
        guard fileManager.fileExists(atPath: manifestURL.path) else { return }
        guard try managedFilesAreValid(mappings: mappings, manifestURL: manifestURL) else {
            throw AgentorIntegrationError.managedFileModified(manifestURL.path)
        }
        for mapping in mappings { try fileManager.removeItem(at: mapping.destination) }
        try fileManager.removeItem(at: manifestURL)
        let parent = manifestURL.deletingLastPathComponent()
        if (try? fileManager.contentsOfDirectory(atPath: parent.path).isEmpty) == true { try? fileManager.removeItem(at: parent) }
    }

    private func installHermes() throws {
        let homes = hermesHomes
        let executable = try hermesExecutable()
        var installedHomes: [URL] = []
        do {
            for home in homes {
                let manifest = home.appendingPathComponent("plugins/peeker-agentor/.peeker-agentor-manifest.json")
                try installManagedFiles(agent: .hermes, mappings: hermesMappings(home), manifestURL: manifest)
                installedHomes.append(home)
                let profile = home.deletingLastPathComponent().lastPathComponent == "profiles" ? home.lastPathComponent : nil
                var arguments: [String] = []
                if let profile { arguments += ["-p", profile] }
                arguments += ["plugins", "enable", "peeker-agentor"]
                try commandRunner(executable, arguments, ["HERMES_HOME": home.path])
            }
        } catch {
            for home in installedHomes.reversed() {
                let profile = home.deletingLastPathComponent().lastPathComponent == "profiles" ? home.lastPathComponent : nil
                var arguments: [String] = []
                if let profile { arguments += ["-p", profile] }
                arguments += ["plugins", "disable", "peeker-agentor"]
                try? commandRunner(executable, arguments, ["HERMES_HOME": home.path])
                try? removeManagedFiles(
                    mappings: hermesMappings(home),
                    manifestURL: home.appendingPathComponent("plugins/peeker-agentor/.peeker-agentor-manifest.json")
                )
            }
            throw error
        }
    }

    private func removeHermes() throws {
        let homes = hermesHomes
        for home in homes {
            let manifest = home.appendingPathComponent("plugins/peeker-agentor/.peeker-agentor-manifest.json")
            guard fileManager.fileExists(atPath: manifest.path) else { continue }
            guard try managedFilesAreValid(mappings: hermesMappings(home), manifestURL: manifest) else {
                throw AgentorIntegrationError.managedFileModified(manifest.path)
            }
        }
        let executable = try hermesExecutable()
        var disabledHomes: [URL] = []
        do {
            for home in homes {
                let manifest = home.appendingPathComponent("plugins/peeker-agentor/.peeker-agentor-manifest.json")
                guard fileManager.fileExists(atPath: manifest.path) else { continue }
                let profile = home.deletingLastPathComponent().lastPathComponent == "profiles" ? home.lastPathComponent : nil
                var arguments: [String] = []
                if let profile { arguments += ["-p", profile] }
                arguments += ["plugins", "disable", "peeker-agentor"]
                try commandRunner(executable, arguments, ["HERMES_HOME": home.path])
                disabledHomes.append(home)
            }
        } catch {
            for home in disabledHomes.reversed() {
                let profile = home.deletingLastPathComponent().lastPathComponent == "profiles" ? home.lastPathComponent : nil
                var arguments: [String] = []
                if let profile { arguments += ["-p", profile] }
                arguments += ["plugins", "enable", "peeker-agentor"]
                try? commandRunner(executable, arguments, ["HERMES_HOME": home.path])
            }
            throw error
        }
        for home in disabledHomes {
            try removeManagedFiles(
                mappings: hermesMappings(home),
                manifestURL: home.appendingPathComponent("plugins/peeker-agentor/.peeker-agentor-manifest.json")
            )
        }
    }

    private func hermesExecutable() throws -> URL {
        for directory in environment.executableSearchPaths {
            let candidate = directory.appendingPathComponent("hermes")
            if fileManager.isExecutableFile(atPath: candidate.path) { return candidate }
        }
        throw AgentorIntegrationError.commandFailed("找不到 hermes CLI")
    }

    private func hermesConfigEnablesPlugin(_ home: URL) -> Bool {
        let config = home.appendingPathComponent("config.yaml")
        guard let text = try? String(contentsOf: config, encoding: .utf8) else { return false }
        return text.contains("peeker-agentor")
    }

    private func enableCodexHooks() throws {
        let url = codexConfigURL
        let original = (try? String(contentsOf: try safeConfigurationURL(url), encoding: .utf8)) ?? ""
        let updated = setCodexHooksGate(in: original)
        try writeAtomically(Data(updated.utf8), to: try writableConfigurationURL(url), defaultPermissions: 0o600)
    }

    private func restoreCodexHooksGate() throws {
        guard fileManager.fileExists(atPath: codexConfigURL.path) else { return }
        let url = try safeConfigurationURL(codexConfigURL)
        let original = try String(contentsOf: url, encoding: .utf8)
        let lines = original.components(separatedBy: "\n")
        var result: [String] = []
        for line in lines {
            if line.contains("# peeker-agentor-managed previous=false") {
                result.append("hooks = false")
            } else if line.contains("# peeker-agentor-managed previous=absent") {
                continue
            } else {
                result.append(line)
            }
        }
        try writeAtomically(Data(result.joined(separator: "\n").utf8), to: url, defaultPermissions: 0o600)
    }

    private func setCodexHooksGate(in text: String) -> String {
        var lines = text.components(separatedBy: "\n")
        let featuresIndex = lines.firstIndex { $0.trimmingCharacters(in: .whitespaces) == "[features]" }
        if featuresIndex == nil {
            if !text.isEmpty, lines.last != "" { lines.append("") }
            lines += ["[features]", "hooks = true # peeker-agentor-managed previous=absent"]
            return lines.joined(separator: "\n")
        }
        let start = featuresIndex! + 1
        let end = lines[start...].firstIndex { $0.trimmingCharacters(in: .whitespaces).hasPrefix("[") } ?? lines.endIndex
        if let index = lines[start..<end].firstIndex(where: { $0.range(of: #"^\s*hooks\s*="# , options: .regularExpression) != nil }) {
            let value = lines[index].split(separator: "#", maxSplits: 1)[0]
            if value.contains("true") { return text }
            lines[index] = "hooks = true # peeker-agentor-managed previous=false"
        } else {
            lines.insert("hooks = true # peeker-agentor-managed previous=absent", at: start)
        }
        return lines.joined(separator: "\n")
    }

    private func codexHooksGateEnabled() -> Bool {
        guard let text = try? String(contentsOf: codexConfigURL, encoding: .utf8) else { return false }
        var inFeatures = false
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") { inFeatures = trimmed == "[features]"; continue }
            if inFeatures, trimmed.range(of: #"^hooks\s*=\s*true"#, options: .regularExpression) != nil { return true }
        }
        return false
    }

    private func codexManagedHooksTrusted() -> Bool {
        guard let text = try? String(contentsOf: codexConfigURL, encoding: .utf8),
              let root = try? readJSONObject(codexHooksURL), let hooks = root["hooks"] as? [String: Any] else { return false }
        var expected: [String] = []
        for (event, value) in hooks {
            guard let groups = value as? [[String: Any]] else { continue }
            for (groupIndex, group) in groups.enumerated() {
                for (hookIndex, hook) in ((group["hooks"] as? [[String: Any]]) ?? []).enumerated()
                    where (hook["command"] as? String)?.contains("PEEKER_AGENTOR_MANAGED=1") == true {
                    let snake = event.reduce(into: "") { result, character in
                        if character.isUppercase, !result.isEmpty { result.append("_") }
                        result.append(character.lowercased())
                    }
                    expected.append("[hooks.state.\"\(codexHooksURL.path):\(snake):\(groupIndex):\(hookIndex)\"]")
                }
            }
        }
        return !expected.isEmpty && expected.allSatisfy { section in
            guard let range = text.range(of: section) else { return false }
            let tail = text[range.upperBound...].prefix(400)
            return tail.contains("trusted_hash = \"sha256:") && !tail.prefix { $0 != "[" }.contains("enabled = false")
        }
    }

    private func bundleManifest() throws -> AgentorBundleResourceManifest {
        let url = environment.resourcesURL.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: url),
              let manifest = try? JSONDecoder.agentor.decode(AgentorBundleResourceManifest.self, from: data),
              manifest.schemaVersion == 1 else { throw AgentorIntegrationError.resourcesMissing }
        return manifest
    }

    private func rejectManagedSymlink(_ url: URL) throws {
        var info = stat()
        if lstat(url.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFLNK {
            throw AgentorIntegrationError.unsafePath(url.path)
        }
    }

    private func safeConfigurationURL(_ url: URL) throws -> URL {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return url }
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL
        let home = environment.homeDirectory.resolvingSymlinksInPath().standardizedFileURL.path
        guard resolved.path == home || resolved.path.hasPrefix(home + "/") else { throw AgentorIntegrationError.unsafePath(url.path) }
        var resolvedInfo = stat()
        guard stat(resolved.path, &resolvedInfo) == 0,
              (resolvedInfo.st_mode & S_IFMT) == S_IFREG,
              resolvedInfo.st_uid == geteuid() else { throw AgentorIntegrationError.unsafePath(url.path) }
        return resolved
    }

    private func writableConfigurationURL(_ url: URL) throws -> URL {
        if fileManager.fileExists(atPath: url.path) { return try safeConfigurationURL(url) }
        let parent = url.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL
        let home = environment.homeDirectory.resolvingSymlinksInPath().standardizedFileURL.path
        guard parent.path == home || parent.path.hasPrefix(home + "/") else { throw AgentorIntegrationError.unsafePath(url.path) }
        return url
    }

    private func writeTransaction(_ writes: [(URL, Data, Int)]) throws {
        let snapshots = writes.map(snapshot)
        do {
            for (url, data, mode) in writes { try writeAtomically(data, to: url, defaultPermissions: mode) }
        } catch {
            for snapshot in snapshots.reversed() { try? restore(snapshot) }
            throw error
        }
    }

    private func snapshot(_ write: (URL, Data, Int)) -> AgentorFileSnapshot {
        let attributes = try? fileManager.attributesOfItem(atPath: write.0.path)
        return AgentorFileSnapshot(
            url: write.0, data: try? Data(contentsOf: write.0),
            permissions: attributes?[.posixPermissions] as? NSNumber
        )
    }

    private func restore(_ snapshot: AgentorFileSnapshot) throws {
        if let data = snapshot.data {
            try writeAtomically(data, to: snapshot.url, defaultPermissions: snapshot.permissions?.intValue ?? 0o600)
        } else if fileManager.fileExists(atPath: snapshot.url.path) {
            try fileManager.removeItem(at: snapshot.url)
        }
    }

    private func writeAtomically(_ data: Data, to url: URL, defaultPermissions: Int) throws {
        try rejectManagedSymlink(url)
        let directory = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let existingMode = (try? fileManager.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)?.intValue
        let temporary = directory.appendingPathComponent(".peeker-agentor-\(UUID().uuidString)")
        do {
            try data.write(to: temporary, options: .withoutOverwriting)
            try fileManager.setAttributes([.posixPermissions: existingMode ?? defaultPermissions], ofItemAtPath: temporary.path)
            guard rename(temporary.path, url.path) == 0 else { throw AgentorIntegrationError.writeFailed(url.path) }
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw error
        }
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    nonisolated private static func runCommand(_ executable: URL, _ arguments: [String], _ extraEnvironment: [String: String]) throws {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment.merging(extraEnvironment) { _, new in new }
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let semaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in semaphore.signal() }
        do {
            try process.run()
            guard semaphore.wait(timeout: .now() + 10) == .success else {
                process.terminate()
                throw AgentorIntegrationError.commandFailed("\(executable.lastPathComponent) 超时")
            }
            guard process.terminationStatus == 0 else { throw AgentorIntegrationError.commandFailed(executable.lastPathComponent) }
        } catch let error as AgentorIntegrationError { throw error }
        catch { throw AgentorIntegrationError.commandFailed(executable.lastPathComponent) }
    }
}
