import CryptoKit
import Foundation
import SwiftUI
import XCTest
import PeekerCore
@testable import FunctionCardKit

@MainActor
final class FunctionCardIconTests: XCTestCase {
    func testSystemSymbolInitializerPreservesLegacyDescriptorsAndStaticSize() {
        let registration = makeRegistration()

        XCTAssertEqual(registration.iconDescriptor, .systemSymbol(name: "circle"))
        XCTAssertEqual(registration.settingsIconDescriptor, .systemSymbol(name: "circle"))
        XCTAssertEqual(registration.systemImage, "circle")
        XCTAssertEqual(registration.layoutState.currentExpandedSize, CGSize(width: 500, height: 300))
    }

    func testLayoutStateCanChangeWithoutMutatingCompactMetrics() {
        let state = FunctionCardLayoutState(currentExpandedSize: CGSize(width: 500, height: 300))
        let registration = makeRegistration(layoutState: state)

        state.currentExpandedSize = CGSize(width: 600, height: 400)

        XCTAssertEqual(registration.layoutState.currentExpandedSize, CGSize(width: 600, height: 400))
        XCTAssertEqual(registration.metrics.compactWidth, 100)
    }

    func testManifestValidatesFeatureSearchAndResourceHash() throws {
        let fixture = try makeManifestFixture()
        let manifest = try FunctionCardIconManifest(
            featureID: FeatureID(rawValue: "example"), rootURL: fixture.root
        )

        XCTAssertTrue(manifest.contains("target"))
        XCTAssertEqual(manifest.search("BULLSEYE").map(\.name), ["target"])
        XCTAssertTrue(manifest.resourceIsValid(named: "target"))
        XCTAssertFalse(manifest.resourceIsValid(named: "missing"))

        try Data("tampered".utf8).write(to: fixture.icon)
        XCTAssertFalse(manifest.resourceIsValid(named: "target"))
    }

    func testManifestRejectsPathTraversalAndDuplicateNames() throws {
        let root = temporaryDirectory()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let hash = String(repeating: "0", count: 64)
        try writeManifest(root: root, icons: [
            iconJSON(name: "target", file: "../target.svg", hash: hash),
        ])
        XCTAssertThrowsError(try FunctionCardIconManifest(
            featureID: FeatureID(rawValue: "example"), rootURL: root
        )) { error in
            XCTAssertEqual(error as? FunctionCardIconManifestError, .invalidRelativePath("../target.svg"))
        }

        try writeManifest(root: root, icons: [
            iconJSON(name: "target", file: "icons/target.svg", hash: hash),
            iconJSON(name: "target", file: "icons/other.svg", hash: hash),
        ])
        XCTAssertThrowsError(try FunctionCardIconManifest(
            featureID: FeatureID(rawValue: "example"), rootURL: root
        )) { error in
            XCTAssertEqual(error as? FunctionCardIconManifestError, .duplicateIconName("target"))
        }
    }

    func testCoordinatorRejectsBundlePromptFromWrongFeature() throws {
        let fixture = try makeManifestFixture()
        let feature = FeatureID(rawValue: "example")
        let manifest = try FunctionCardIconManifest(featureID: feature, rootURL: fixture.root)
        let registration = FunctionCardRegistration(
            id: feature,
            name: "Example",
            iconDescriptor: .bundleSVG(featureID: feature, manifestResourceName: "target"),
            iconManifest: manifest,
            defaultOrder: 0,
            metrics: metrics,
            makeExpandedView: { AnyView(EmptyView()) },
            makeSettingsView: { AnyView(EmptyView()) }
        )
        let coordinator = IslandCoordinator(registry: CardRegistry(registrations: [registration]))

        coordinator.publishPrompt(FunctionCardPrompt(
            token: "wrong", sourceID: feature,
            iconDescriptor: .bundleSVG(featureID: FeatureID(rawValue: "other"), manifestResourceName: "target"),
            moduleName: "Example", summary: "Wrong"
        ))
        coordinator.publishPrompt(FunctionCardPrompt(
            token: "valid", sourceID: feature,
            iconDescriptor: .bundleSVG(featureID: feature, manifestResourceName: "target"),
            moduleName: "Example", summary: "Valid"
        ))

        XCTAssertEqual(coordinator.promptCenter.count, 1)
    }

    private func makeRegistration(layoutState: FunctionCardLayoutState? = nil) -> FunctionCardRegistration {
        FunctionCardRegistration(
            id: FeatureID(rawValue: "example"), name: "Example", systemImage: "circle",
            defaultOrder: 0, metrics: metrics, layoutState: layoutState,
            makeExpandedView: { AnyView(EmptyView()) }, makeSettingsView: { AnyView(EmptyView()) }
        )
    }

    private var metrics: FunctionCardMetrics {
        FunctionCardMetrics(
            compactWidth: 100, compactHeight: 32,
            compactLeadingWidth: 40, compactTrailingWidth: 40,
            expandedWidth: 500, expandedHeight: 300
        )
    }

    private func makeManifestFixture() throws -> (root: URL, icon: URL) {
        let root = temporaryDirectory()
        let icons = root.appendingPathComponent("icons", isDirectory: true)
        try FileManager.default.createDirectory(at: icons, withIntermediateDirectories: true)
        let icon = icons.appendingPathComponent("target.svg")
        let data = Data("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"24\" height=\"24\"><circle cx=\"12\" cy=\"12\" r=\"8\"/></svg>".utf8)
        try data.write(to: icon)
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        try writeManifest(root: root, icons: [iconJSON(name: "target", file: "icons/target.svg", hash: hash)])
        return (root, icon)
    }

    private func writeManifest(root: URL, icons: [[String: Any]]) throws {
        let object: [String: Any] = [
            "schemaVersion": 1,
            "featureID": "example",
            "version": "test",
            "upstreamCommit": "fixture",
            "iconCount": icons.count,
            "icons": icons,
        ]
        try JSONSerialization.data(withJSONObject: object)
            .write(to: root.appendingPathComponent("manifest.json"))
    }

    private func iconJSON(name: String, file: String, hash: String) -> [String: Any] {
        ["name": name, "file": file, "tags": ["bullseye"], "sha256": hash]
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}
