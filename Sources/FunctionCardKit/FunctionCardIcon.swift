import AppKit
import CryptoKit
import Foundation
import SwiftUI
import PeekerCore

public enum FunctionCardIconDescriptor: Equatable, Sendable {
    case systemSymbol(name: String)
    case bundleSVG(featureID: FeatureID, manifestResourceName: String)
}

public enum FunctionCardIconManifestError: Error, Equatable {
    case manifestMissing
    case malformedManifest
    case unsupportedSchema(Int)
    case featureMismatch
    case invalidIconName(String)
    case invalidRelativePath(String)
    case duplicateIconName(String)
    case invalidSHA256(String)
    case iconCountMismatch
}

public struct FunctionCardIconManifestEntry: Equatable, Sendable {
    public let name: String
    public let relativeFile: String
    public let tags: [String]
    public let sha256: String

    public init(name: String, relativeFile: String, tags: [String], sha256: String) {
        self.name = name
        self.relativeFile = relativeFile
        self.tags = tags
        self.sha256 = sha256
    }
}

public final class FunctionCardIconManifest: @unchecked Sendable {
    public let featureID: FeatureID
    public let version: String
    public let upstreamCommit: String
    public let rootURL: URL
    public let entries: [FunctionCardIconManifestEntry]
    private let entriesByName: [String: FunctionCardIconManifestEntry]

    public convenience init(
        featureID: FeatureID,
        bundle: Bundle,
        resourceSubdirectory: String,
        manifestResourceName: String = "manifest.json"
    ) throws {
        guard let resourceURL = bundle.resourceURL else {
            throw FunctionCardIconManifestError.manifestMissing
        }
        try self.init(
            featureID: featureID,
            rootURL: resourceURL.appendingPathComponent(resourceSubdirectory, isDirectory: true),
            manifestResourceName: manifestResourceName
        )
    }

    public init(
        featureID: FeatureID,
        rootURL: URL,
        manifestResourceName: String = "manifest.json"
    ) throws {
        let normalizedRoot = rootURL.standardizedFileURL
        let manifestURL = normalizedRoot.appendingPathComponent(manifestResourceName, isDirectory: false).standardizedFileURL
        guard Self.isContained(manifestURL, in: normalizedRoot),
              let data = try? Data(contentsOf: manifestURL)
        else { throw FunctionCardIconManifestError.manifestMissing }

        let decoded: ManifestFile
        do { decoded = try JSONDecoder().decode(ManifestFile.self, from: data) }
        catch { throw FunctionCardIconManifestError.malformedManifest }
        guard decoded.schemaVersion == 1 else {
            throw FunctionCardIconManifestError.unsupportedSchema(decoded.schemaVersion)
        }
        guard decoded.featureID == featureID.rawValue else {
            throw FunctionCardIconManifestError.featureMismatch
        }
        guard decoded.iconCount == decoded.icons.count else {
            throw FunctionCardIconManifestError.iconCountMismatch
        }

        var names = Set<String>()
        var validated: [FunctionCardIconManifestEntry] = []
        for icon in decoded.icons {
            guard Self.isCanonicalName(icon.name) else {
                throw FunctionCardIconManifestError.invalidIconName(icon.name)
            }
            guard names.insert(icon.name).inserted else {
                throw FunctionCardIconManifestError.duplicateIconName(icon.name)
            }
            guard Self.isSafeRelativePath(icon.file) else {
                throw FunctionCardIconManifestError.invalidRelativePath(icon.file)
            }
            let iconURL = normalizedRoot.appendingPathComponent(icon.file, isDirectory: false).standardizedFileURL
            guard Self.isContained(iconURL, in: normalizedRoot) else {
                throw FunctionCardIconManifestError.invalidRelativePath(icon.file)
            }
            let hash = icon.sha256.lowercased()
            guard hash.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil else {
                throw FunctionCardIconManifestError.invalidSHA256(icon.name)
            }
            validated.append(FunctionCardIconManifestEntry(
                name: icon.name,
                relativeFile: icon.file,
                tags: icon.tags,
                sha256: hash
            ))
        }

        self.featureID = featureID
        version = decoded.version
        upstreamCommit = decoded.upstreamCommit
        self.rootURL = normalizedRoot
        entries = validated
        entriesByName = Dictionary(uniqueKeysWithValues: validated.map { ($0.name, $0) })
    }

    public func contains(_ canonicalName: String) -> Bool {
        entriesByName[canonicalName] != nil
    }

    public func search(_ query: String) -> [FunctionCardIconManifestEntry] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return entries }
        return entries.filter { entry in
            entry.name.localizedCaseInsensitiveContains(needle)
                || entry.tags.contains { $0.localizedCaseInsensitiveContains(needle) }
        }
    }

    public func resourceIsValid(named canonicalName: String) -> Bool {
        guard let entry = entriesByName[canonicalName] else { return false }
        let url = rootURL.appendingPathComponent(entry.relativeFile, isDirectory: false).standardizedFileURL
        guard Self.isContained(url, in: rootURL), let data = try? Data(contentsOf: url) else { return false }
        return Self.sha256(data) == entry.sha256 && NSImage(data: data) != nil
    }

    fileprivate func loadImage(named canonicalName: String) -> NSImage? {
        guard resourceIsValid(named: canonicalName), let entry = entriesByName[canonicalName] else { return nil }
        let url = rootURL.appendingPathComponent(entry.relativeFile, isDirectory: false).standardizedFileURL
        guard let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = true
        return image
    }

    private static func isCanonicalName(_ value: String) -> Bool {
        !value.isEmpty && value.range(of: "^[a-z0-9]+(?:-[a-z0-9]+)*$", options: .regularExpression) != nil
    }

    private static func isSafeRelativePath(_ value: String) -> Bool {
        guard !value.isEmpty, !value.hasPrefix("/"), !value.hasPrefix("~"), !value.contains("\\") else { return false }
        return value.split(separator: "/", omittingEmptySubsequences: false).allSatisfy { $0 != "." && $0 != ".." && !$0.isEmpty }
    }

    private static func isContained(_ candidate: URL, in root: URL) -> Bool {
        let rootPath = root.standardizedFileURL.path.hasSuffix("/") ? root.standardizedFileURL.path : root.standardizedFileURL.path + "/"
        return candidate.standardizedFileURL.path.hasPrefix(rootPath)
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

private struct ManifestFile: Decodable {
    let schemaVersion: Int
    let featureID: String
    let version: String
    let upstreamCommit: String
    let iconCount: Int
    let icons: [ManifestIcon]
}

private struct ManifestIcon: Decodable {
    let name: String
    let file: String
    let tags: [String]
    let sha256: String
}

@MainActor
private final class FunctionCardIconImageCache {
    static let shared = FunctionCardIconImageCache()
    private var images: [String: NSImage] = [:]
    private var failures = Set<String>()

    func image(
        descriptor: FunctionCardIconDescriptor,
        manifest: FunctionCardIconManifest?
    ) -> NSImage? {
        guard case let .bundleSVG(featureID, name) = descriptor,
              manifest?.featureID == featureID,
              let manifest
        else { return nil }
        let key = "\(featureID.rawValue):\(manifest.version):\(name)"
        if let image = images[key] { return image }
        guard !failures.contains(key), let image = manifest.loadImage(named: name) else {
            failures.insert(key)
            return nil
        }
        images[key] = image
        return image
    }
}

public struct FunctionCardIconView: View {
    private let descriptor: FunctionCardIconDescriptor
    private let manifest: FunctionCardIconManifest?
    private let accessibilityLabel: String?

    public init(
        descriptor: FunctionCardIconDescriptor,
        manifest: FunctionCardIconManifest? = nil,
        accessibilityLabel: String? = nil
    ) {
        self.descriptor = descriptor
        self.manifest = manifest
        self.accessibilityLabel = accessibilityLabel
    }

    public var body: some View {
        Group {
            switch descriptor {
            case let .systemSymbol(name):
                Image(systemName: name)
            case .bundleSVG:
                if let image = FunctionCardIconImageCache.shared.image(descriptor: descriptor, manifest: manifest) {
                    Image(nsImage: image).resizable().scaledToFit()
                } else {
                    Image(systemName: "exclamationmark.triangle")
                }
            }
        }
        .accessibilityLabel(accessibilityLabel.map(Text.init) ?? Text("图标不可用"))
    }
}
