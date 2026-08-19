import Foundation
import XCTest
import FeatureRuntimeKit
import MacPlatform
import PeekerCore
import PeekerProtocol
import PersistenceCore
import SchedulerFeature
@testable import SchedulerModule

@MainActor
final class SchedulerModuleTests: XCTestCase {
    func testModuleOwnsIdentityMigrationAndCommandRoute() async throws {
        let module = SchedulerModule()
        XCTAssertEqual(module.id, .scheduler)
        XCTAssertEqual(module.databaseMigrations.map(\.id), ["scheduler-schema-v1"])
        let database = try AppDatabase.inMemory(featureMigrations: module.databaseMigrations)
        let clock = SchedulerTestClock()
        let runtime = module.makeRuntimeRegistration(context: FunctionCardModuleContext(
            persistence: .success(database), clock: clock, resolver: BusinessDayResolver(),
            eventHub: TemporalEventHub(clock: clock, scheduler: SchedulerTestTemporalScheduler()),
            preferences: FeaturePreferenceStore(defaults: makeDefaults()),
            hostActions: FunctionCardHostActionsBridge().actions
        ))
        XCTAssertNil(runtime.card.compactProvider)
        XCTAssertEqual(runtime.card.introducedConfigurationVersion, 2)

        let create = await runtime.handleCommand(CommandInvocation(
            featureID: "scheduler",
            arguments: ["create", "--title", "Review", "--start", "2026-08-20T09:00:00Z", "--end", "2026-08-20T09:30:00Z"],
            category: .mutation
        ))
        XCTAssertTrue(create.ok)
        let list = await runtime.handleCommand(CommandInvocation(
            featureID: "scheduler",
            arguments: ["list", "--from", "2026-08-20", "--to", "2026-08-21"],
            category: .read
        ))
        XCTAssertTrue(list.ok)
        guard case let .object(data)? = list.data,
              case let .array(occurrences)? = data["occurrences"] else { return XCTFail("missing occurrences") }
        XCTAssertEqual(occurrences.count, 1)
    }

    private func makeDefaults() -> UserDefaults {
        let name="SchedulerModuleTests.\(UUID().uuidString)";let defaults=UserDefaults(suiteName:name)!;defaults.removePersistentDomain(forName:name);return defaults
    }
}

private final class SchedulerTestClock: Clock, @unchecked Sendable { func now()->Date{Date()} }
private actor SchedulerTestTemporalScheduler: TemporalScheduling {
    func schedule(at date:Date,action:@escaping @Sendable()->Void)async{}
    func cancelAll()async{}
}
