import SwiftUI
import XCTest
import PeekerCore
import FunctionCardKit
@testable import PeekerApp

@MainActor
final class SettingsNavigationTests: XCTestCase {
    func testDestinationsAreDerivedFromArbitraryRegistrations() {
        let alpha = FeatureID(rawValue: "alpha")
        let beta = FeatureID(rawValue: "beta")

        let destinations = SettingsNavigation.destinations(
            registrations: [makeRegistration(id: alpha), makeRegistration(id: beta)]
        )

        XCTAssertEqual(
            destinations,
            [.general, .cards, .feature(alpha), .feature(beta), .about]
        )
    }

    func testMissingFeatureSelectionFallsBackToGeneral() {
        let installed = FeatureID(rawValue: "installed")
        let missing = FeatureID(rawValue: "missing")

        let resolved = SettingsNavigation.resolve(
            selection: .feature(missing),
            registrations: [makeRegistration(id: installed)]
        )

        XCTAssertEqual(resolved, .general)
    }

    private func makeRegistration(id: FeatureID) -> FunctionCardRegistration {
        FunctionCardRegistration(
            id: id,
            name: id.rawValue,
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
