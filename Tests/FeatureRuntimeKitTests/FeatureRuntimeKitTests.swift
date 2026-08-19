import SwiftUI
import XCTest
import FunctionCardKit
import MacPlatform
import PeekerCore
import PersistenceCore
@testable import FeatureRuntimeKit

@MainActor
final class FeatureRuntimeKitTests: XCTestCase {
    func testHostActionsAreSafeBeforeAttachmentAndForwardAfterAttachment() {
        let bridge = FunctionCardHostActionsBridge()

        bridge.actions.setDragging(true)
        bridge.actions.setEditingText(true)
        bridge.actions.setPopoverPresented(true)

        let coordinator = IslandCoordinator(
            registry: CardRegistry(registrations: [makeRegistration(id: "example")])
        )
        bridge.attach(to: coordinator)
        bridge.actions.setDragging(true)
        bridge.actions.setEditingText(true)
        bridge.actions.setPopoverPresented(true)

        XCTAssertTrue(coordinator.presentation.blockers.isDragging)
        XCTAssertTrue(coordinator.presentation.blockers.isEditingText)
        XCTAssertTrue(coordinator.presentation.blockers.isPopoverPresented)
    }

    func testHostActionsRetainTheirBridgeAfterTheAssemblyLocalIsReleased() {
        var bridge: FunctionCardHostActionsBridge? = FunctionCardHostActionsBridge()
        let actions = bridge!.actions
        let coordinator = IslandCoordinator(
            registry: CardRegistry(registrations: [makeRegistration(id: "example")])
        )
        bridge!.attach(to: coordinator)

        bridge = nil
        actions.setDragging(true)

        XCTAssertTrue(coordinator.presentation.blockers.isDragging)
    }

    func testCatalogBuildsAnUnknownThirdPartyStyleModuleThroughTheContract() throws {
        let module = MockModule(id: FeatureID(rawValue: "example"))
        let catalog = try FunctionCardModuleCatalog(modules: [module])
        let context = try makeContext()

        let registrations = catalog.makeRegistrations(context: context)

        XCTAssertEqual(registrations.map(\.id), [FeatureID(rawValue: "example")])
        XCTAssertEqual(catalog.databaseMigrations.map(\.id), ["example-schema-v1"])
    }

    func testCatalogRejectsDuplicateFeatureIDs() {
        let first = MockModule(id: FeatureID(rawValue: "duplicate"))
        let second = MockModule(id: FeatureID(rawValue: "duplicate"))

        XCTAssertThrowsError(try FunctionCardModuleCatalog(modules: [first, second])) { error in
            XCTAssertEqual(
                error as? FunctionCardModuleCatalogError,
                .duplicateFeatureID(FeatureID(rawValue: "duplicate"))
            )
        }
    }

    func testCatalogRejectsDuplicateMigrationIDs() {
        let first = MockModule(
            id: FeatureID(rawValue: "first"),
            migrationID: "shared-schema-v1"
        )
        let second = MockModule(
            id: FeatureID(rawValue: "second"),
            migrationID: "shared-schema-v1"
        )

        XCTAssertThrowsError(try FunctionCardModuleCatalog(modules: [first, second])) { error in
            XCTAssertEqual(
                error as? FunctionCardModuleCatalogError,
                .duplicateMigrationID("shared-schema-v1")
            )
        }
    }

    private func makeContext() throws -> FunctionCardModuleContext {
        let defaults = UserDefaults(suiteName: "FeatureRuntimeKitTests.\(UUID().uuidString)")!
        let clock = RuntimeTestClock()
        let eventHub = TemporalEventHub(clock: clock, scheduler: RuntimeTestScheduler())
        return FunctionCardModuleContext(
            persistence: .success(try AppDatabase.inMemory()),
            clock: clock,
            resolver: BusinessDayResolver(),
            eventHub: eventHub,
            preferences: FeaturePreferenceStore(defaults: defaults),
            hostActions: FunctionCardHostActionsBridge().actions
        )
    }

    private func makeRegistration(id: String) -> FunctionCardRegistration {
        FunctionCardRegistration(
            id: FeatureID(rawValue: id),
            name: id,
            systemImage: "square",
            defaultOrder: 0,
            metrics: FunctionCardMetrics(
                compactWidth: 100,
                compactHeight: 32,
                compactLeadingWidth: 40,
                compactTrailingWidth: 40,
                expandedWidth: 400,
                expandedHeight: 300
            ),
            makeCompactLeadingView: { AnyView(EmptyView()) },
            makeCompactTrailingView: { AnyView(EmptyView()) },
            makeExpandedView: { AnyView(EmptyView()) },
            makeSettingsView: { AnyView(EmptyView()) }
        )
    }
}

@MainActor
private struct MockModule: FunctionCardModule {
    let id: FeatureID
    var migrationID = "example-schema-v1"

    var databaseMigrations: [AppDatabaseMigration] {
        [AppDatabaseMigration(id: migrationID) { _ in }]
    }

    func makeRegistration(context: FunctionCardModuleContext) -> FunctionCardRegistration {
        FunctionCardRegistration(
            id: id,
            name: "Example",
            systemImage: "square",
            defaultOrder: 10,
            metrics: FunctionCardMetrics(
                compactWidth: 100,
                compactHeight: 32,
                compactLeadingWidth: 40,
                compactTrailingWidth: 40,
                expandedWidth: 400,
                expandedHeight: 300
            ),
            makeCompactLeadingView: { AnyView(EmptyView()) },
            makeCompactTrailingView: { AnyView(EmptyView()) },
            makeExpandedView: { AnyView(EmptyView()) },
            makeSettingsView: { AnyView(EmptyView()) }
        )
    }
}

private struct RuntimeTestClock: Clock {
    func now() -> Date { Date(timeIntervalSince1970: 0) }
}

private actor RuntimeTestScheduler: TemporalScheduling {
    func schedule(at date: Date, action: @escaping @Sendable () -> Void) async {}
    func cancelAll() async {}
}

