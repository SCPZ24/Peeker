import Foundation
import Observation
import SwiftUI
import PeekerCore

public enum CardRegistryError: Error, Equatable {
    case unknownCard
    case atLeastOneCardRequired
}

@MainActor
@Observable
public final class CardRegistry {
    public private(set) var registrations: [FunctionCardRegistration]
    public private(set) var enabledIDs: [FeatureID]
    public private(set) var selectedID: FeatureID
    @ObservationIgnored private let onChange: @MainActor ([FeatureID], FeatureID) -> Void

    public init(
        registrations: [FunctionCardRegistration],
        enabledIDs: [FeatureID] = [],
        recentID: FeatureID? = nil,
        onChange: @escaping @MainActor ([FeatureID], FeatureID) -> Void = { _, _ in }
    ) {
        let sorted = registrations.sorted { $0.defaultOrder < $1.defaultOrder }
        let valid = enabledIDs.filter { id in sorted.contains(where: { $0.id == id }) }
        let resolvedEnabled = valid.isEmpty ? sorted.map(\.id) : valid
        let resolvedSelected = recentID.flatMap { validRecent in
            resolvedEnabled.contains(validRecent) ? validRecent : nil
        } ?? resolvedEnabled.first ?? FeatureID(rawValue: "unavailable")
        self.registrations = sorted
        self.enabledIDs = resolvedEnabled
        self.selectedID = resolvedSelected
        self.onChange = onChange
    }

    public var enabledCards: [FunctionCardRegistration] {
        enabledIDs.compactMap { id in registrations.first(where: { $0.id == id }) }
    }

    public var selectedCard: FunctionCardRegistration? {
        registrations.first(where: { $0.id == selectedID && enabledIDs.contains($0.id) })
    }

    public func select(_ id: FeatureID) {
        guard enabledIDs.contains(id) else { return }
        selectedID = id
        onChange(enabledIDs, selectedID)
    }

    public func setEnabled(_ id: FeatureID, enabled: Bool) throws {
        guard registrations.contains(where: { $0.id == id }) else { throw CardRegistryError.unknownCard }
        if enabled {
            if !enabledIDs.contains(id) { enabledIDs.append(id) }
        } else {
            guard enabledIDs.count > 1 else { throw CardRegistryError.atLeastOneCardRequired }
            enabledIDs.removeAll { $0 == id }
            if selectedID == id { selectedID = enabledIDs[0] }
        }
        onChange(enabledIDs, selectedID)
    }

    public func moveEnabled(fromOffsets: IndexSet, toOffset: Int) {
        enabledIDs.move(fromOffsets: fromOffsets, toOffset: toOffset)
        onChange(enabledIDs, selectedID)
    }
}
