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
    public private(set) var lastOpenedAt: [FeatureID: Date]
    @ObservationIgnored private let onChange: @MainActor ([FeatureID], FeatureID) -> Void
    @ObservationIgnored private let onEnablementChange: @MainActor (FeatureID, Bool) -> Void
    @ObservationIgnored private let onOpened: @MainActor (FeatureID, Date) -> Void

    public init(
        registrations: [FunctionCardRegistration],
        enabledIDs: [FeatureID] = [],
        recentID: FeatureID? = nil,
        lastOpenedAt: [FeatureID: Date] = [:],
        onChange: @escaping @MainActor ([FeatureID], FeatureID) -> Void = { _, _ in },
        onEnablementChange: @escaping @MainActor (FeatureID, Bool) -> Void = { _, _ in },
        onOpened: @escaping @MainActor (FeatureID, Date) -> Void = { _, _ in }
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
        self.lastOpenedAt = lastOpenedAt.filter { all in sorted.contains(where: { $0.id == all.key }) }
        self.onChange = onChange
        self.onEnablementChange = onEnablementChange
        self.onOpened = onOpened
    }

    public var enabledCards: [FunctionCardRegistration] {
        enabledIDs.compactMap { id in registrations.first(where: { $0.id == id }) }
    }

    public var selectedCard: FunctionCardRegistration? {
        registrations.first(where: { $0.id == selectedID && enabledIDs.contains($0.id) })
    }

    public var compactCard: FunctionCardRegistration? {
        enabledCards
            .filter { $0.compactProvider?.isEligible() == true }
            .sorted { lhs, rhs in
                let left = lastOpenedAt[lhs.id]
                let right = lastOpenedAt[rhs.id]
                if left != right {
                    if left == nil { return false }
                    if right == nil { return true }
                    return left! > right!
                }
                return enabledIDs.firstIndex(of: lhs.id)! < enabledIDs.firstIndex(of: rhs.id)!
            }
            .first
    }

    public func select(_ id: FeatureID, markOpened: Bool = true) {
        guard enabledIDs.contains(id) else { return }
        selectedID = id
        if markOpened { recordOpened(id) }
        onChange(enabledIDs, selectedID)
    }

    public func recordOpened(_ id: FeatureID, at date: Date = Date()) {
        guard enabledIDs.contains(id) else { return }
        lastOpenedAt[id] = date
        onOpened(id, date)
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
        onEnablementChange(id, enabled)
        onChange(enabledIDs, selectedID)
    }

    public func moveEnabled(fromOffsets: IndexSet, toOffset: Int) {
        enabledIDs.move(fromOffsets: fromOffsets, toOffset: toOffset)
        onChange(enabledIDs, selectedID)
    }
}
