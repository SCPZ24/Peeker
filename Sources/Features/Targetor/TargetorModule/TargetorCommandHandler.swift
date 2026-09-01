import Foundation
import PeekerCore
import PeekerProtocol
import TargetorFeature

@MainActor
final class TargetorEnablementState { var enabled = true }

@MainActor
struct TargetorCommandHandler {
    let store: TargetorStore
    let enabledState: TargetorEnablementState
    let setEnabled: (Bool) throws -> Void
    let isValidIcon: (String) -> Bool

    func handle(_ arguments: [String]) async -> PeekerEnvelope {
        do {
            guard let command = arguments.first else { throw usage("targetor command required") }
            let tail = Array(arguments.dropFirst())
            switch command {
            case "list": return try await list(tail)
            case "get": return try await get(tail)
            case "create": return try await create(tail)
            case "update": return try await update(tail)
            case "delete": return try await delete(tail)
            case "checkin": return try await checkin(tail)
            case "uncheck": return try await uncheck(tail)
            case "history": return try await history(tail)
            case "config": return try await config(tail)
            default: throw usage("Unknown targetor command: \(command)")
            }
        } catch let error as PeekerError { return .failure(error) }
        catch let error as TargetorError { return .failure(map(error)) }
        catch { return .failure(PeekerError(code: "persistence_error", message: error.localizedDescription)) }
    }

    private func list(_ arguments: [String]) async throws -> PeekerEnvelope {
        let options = try TargetorOptions(arguments)
        try options.requireOnly(["--archived"])
        let scope: TargetorArchiveScope
        switch options.value("--archived") ?? "active" {
        case "active": scope = .active
        case "all": scope = .all
        case "only": scope = .only
        default: throw usage("--archived must be active, all, or only")
        }
        return .success(.object(["targets": .array(try await store.list(scope: scope).map(targetJSON))]))
    }

    private func get(_ arguments: [String]) async throws -> PeekerEnvelope {
        let options = try TargetorOptions(arguments)
        try options.requireOnly(["--id", "--include-archived"])
        let selector = try selector(options)
        let includeArchived = try options.value("--include-archived").map(parseBool) ?? false
        return .success(targetJSON(try await store.resolve(
            id: selector.id, title: selector.title, includeArchived: includeArchived
        )))
    }

    private func create(_ arguments: [String]) async throws -> PeekerEnvelope {
        let options = try TargetorOptions(arguments)
        try options.requireOnly(["--title", "--description", "--icon", "--period", "--weekday", "--month-day", "--max-count"])
        guard options.positionals.isEmpty else { throw usage("create does not accept a positional title") }
        let title = try options.required("--title")
        let icon = options.value("--icon") ?? "target"
        guard isValidIcon(icon) else { throw TargetorError.invalidIcon }
        let rule = try periodRule(options: options, existing: nil, requireExplicitCompanion: true)
        let max = try parseMax(options.value("--max-count") ?? "1")
        return .success(targetJSON(try await store.create(
            title: title, description: options.value("--description"), iconName: icon,
            periodRule: rule, maxCount: max
        )))
    }

    private func update(_ arguments: [String]) async throws -> PeekerEnvelope {
        let options = try TargetorOptions(arguments, flags: ["--clear-description"])
        try options.requireOnly([
            "--id", "--title", "--description", "--clear-description", "--icon", "--period",
            "--weekday", "--month-day", "--max-count",
        ])
        guard !(options.has("--clear-description") && options.value("--description") != nil) else {
            throw usage("--description and --clear-description are mutually exclusive")
        }
        let selected = try selector(options)
        let existing = try await store.resolve(id: selected.id, title: selected.title)
        let icon = options.value("--icon") ?? existing.target.iconName
        guard isValidIcon(icon) else { throw TargetorError.invalidIcon }
        let rule = try periodRule(options: options, existing: existing.target.periodRule, requireExplicitCompanion: true)
        let max = try options.value("--max-count").map(parseMax) ?? existing.target.maxCount
        let description = options.has("--clear-description") ? nil : options.value("--description") ?? existing.target.description
        return .success(targetJSON(try await store.update(
            targetID: existing.id,
            title: options.value("--title") ?? existing.target.title,
            description: description,
            iconName: icon,
            periodRule: rule,
            maxCount: max
        )))
    }

    private func delete(_ arguments: [String]) async throws -> PeekerEnvelope {
        let options = try TargetorOptions(arguments)
        try options.requireOnly(["--id"])
        let selected = try selector(options)
        let target = try await store.resolve(id: selected.id, title: selected.title)
        let archived = try await store.archive(targetID: target.id)
        return .success(.object(["target": targetJSON(archived), "archived": .bool(true)]))
    }

    private func checkin(_ arguments: [String]) async throws -> PeekerEnvelope {
        let options = try TargetorOptions(arguments)
        try options.requireOnly(["--id"])
        let selected = try selector(options)
        let target = try await store.resolve(id: selected.id, title: selected.title)
        let result = try await store.checkin(targetID: target.id)
        return .success(.object(["target": targetJSON(result.target), "event": eventJSON(result.event)]))
    }

    private func uncheck(_ arguments: [String]) async throws -> PeekerEnvelope {
        let options = try TargetorOptions(arguments)
        try options.requireOnly(["--event-id"])
        guard options.positionals.isEmpty else { throw usage("uncheck accepts only --event-id") }
        let eventID = try uuid(options.required("--event-id"))
        return .success(targetJSON(try await store.uncheck(eventID: eventID)))
    }

    private func history(_ arguments: [String]) async throws -> PeekerEnvelope {
        let options = try TargetorOptions(arguments)
        try options.requireOnly(["--id", "--from", "--to"])
        let selected = try selector(options)
        let target = try await store.resolve(id: selected.id, title: selected.title, includeArchived: true)
        let fromRaw = options.value("--from"), toRaw = options.value("--to")
        guard (fromRaw == nil) == (toRaw == nil) else { throw TargetorError.invalidHistoryRange }
        let from = try fromRaw.map(parseRFC3339), to = try toRaw.map(parseRFC3339)
        let value = try await store.history(targetID: target.id, from: from, to: to)
        return .success(historyJSON(value))
    }

    private func config(_ arguments: [String]) async throws -> PeekerEnvelope {
        guard let command = arguments.first else { throw usage("targetor config get|set required") }
        let options = try TargetorOptions(Array(arguments.dropFirst()))
        switch command {
        case "get":
            try options.requireOnly([])
            return .success(configJSON())
        case "set":
            try options.requireOnly(["--enabled", "--refresh-time"])
            guard !options.values.isEmpty else { throw usage("config set requires a value") }
            if let enabled = options.value("--enabled") {
                let value = try parseBool(enabled)
                do { try setEnabled(value) }
                catch { throw PeekerError(code: "card_enablement_conflict", message: "At least one card must remain enabled") }
                enabledState.enabled = value
            }
            if let refresh = options.value("--refresh-time") {
                try await store.updateRefreshTime(parseRefreshTime(refresh))
            }
            return .success(configJSON())
        default: throw usage("targetor config get|set required")
        }
    }

    private func selector(_ options: TargetorOptions) throws -> (id: UUID?, title: String?) {
        let id = try options.value("--id").map(uuid)
        guard options.positionals.count <= 1 else { throw usage("Expected one exact title") }
        let title = options.positionals.first
        guard (id == nil) != (title == nil) else { throw usage("Use exactly one of --id or exact title") }
        return (id, title)
    }

    private func periodRule(
        options: TargetorOptions,
        existing: TargetorPeriodRule?,
        requireExplicitCompanion: Bool
    ) throws -> TargetorPeriodRule {
        let explicit = options.value("--period").flatMap(TargetorFrequency.init(rawValue:))
        if options.value("--period") != nil, explicit == nil { throw TargetorError.invalidPeriod }
        let frequency = explicit ?? existing?.frequency ?? .daily
        let weekdayRaw = options.value("--weekday")
        let monthDayRaw = options.value("--month-day")
        if explicit == .weekly, requireExplicitCompanion, weekdayRaw == nil { throw TargetorError.invalidPeriod }
        if explicit == .monthly, requireExplicitCompanion, monthDayRaw == nil { throw TargetorError.invalidPeriod }
        let weekday = weekdayRaw.flatMap(TargetorWeekday.init(rawValue:)) ?? (frequency == .weekly ? existing?.weekday : nil)
        if weekdayRaw != nil, TargetorWeekday(rawValue: weekdayRaw!) == nil { throw TargetorError.invalidPeriod }
        let monthDay: Int?
        if let monthDayRaw { guard let value = Int(monthDayRaw) else { throw TargetorError.invalidPeriod }; monthDay = value }
        else { monthDay = frequency == .monthly ? existing?.monthDay : nil }
        return try TargetorPeriodRule(frequency: frequency, weekday: weekday, monthDay: monthDay)
    }

    private func targetJSON(_ state: TargetorTargetState) -> JSONValue {
        let target = state.target
        var object: [String: JSONValue] = [
            "targetId": .string(target.id.uuidString), "title": .string(target.title),
            "description": target.description.map(JSONValue.string) ?? .null,
            "icon": .string(target.iconName), "period": ruleJSON(target.periodRule),
            "position": .number(Double(target.position)),
            "createdAt": .string(rfc3339(Date(millisecondsSince1970: target.createdAtMilliseconds))),
            "updatedAt": .string(rfc3339(Date(millisecondsSince1970: target.updatedAtMilliseconds))),
            "archivedAt": target.archivedAtMilliseconds.map { .string(rfc3339(Date(millisecondsSince1970: $0))) } ?? .null,
            "currentPeriod": state.currentPeriod.map(periodJSON) ?? .null,
        ]
        if let last = state.lastPeriod { object["lastPeriod"] = periodJSON(last) }
        return .object(object)
    }

    private func periodJSON(_ period: TargetorPeriod) -> JSONValue {
        .object([
            "periodId": .string(period.id.uuidString), "sequence": .number(Double(period.sequence)),
            "start": .string(rfc3339(Date(millisecondsSince1970: period.startMilliseconds))),
            "end": .string(rfc3339(Date(millisecondsSince1970: period.endMilliseconds))),
            "period": ruleJSON(period.ruleSnapshot),
            "count": .number(Double(period.count)), "maxCount": .number(Double(period.maxCountSnapshot)),
            "ratio": .number(period.ratio), "state": .string(period.state.rawValue),
            "settledAt": period.settledAtMilliseconds.map { .string(rfc3339(Date(millisecondsSince1970: $0))) } ?? .null,
        ])
    }

    private func ruleJSON(_ rule: TargetorPeriodRule) -> JSONValue {
        var object: [String: JSONValue] = ["frequency": .string(rule.frequency.rawValue)]
        if let weekday = rule.weekday { object["weekday"] = .string(weekday.rawValue) }
        if let monthDay = rule.monthDay { object["monthDay"] = .number(Double(monthDay)) }
        return .object(object)
    }

    private func eventJSON(_ event: TargetorCheckin) -> JSONValue {
        .object([
            "eventId": .string(event.id.uuidString), "periodId": .string(event.periodID.uuidString),
            "occurredAt": .string(rfc3339(Date(millisecondsSince1970: event.occurredAtMilliseconds))),
        ])
    }

    private func historyJSON(_ history: TargetorHistory) -> JSONValue {
        .object([
            "target": .object(["targetId": .string(history.target.id.uuidString), "title": .string(history.target.title)]),
            "from": .string(rfc3339(Date(millisecondsSince1970: history.fromMilliseconds))),
            "to": .string(rfc3339(Date(millisecondsSince1970: history.toMilliseconds))),
            "periods": .array(history.periods.map(periodJSON)),
            "events": .array(history.events.map(eventJSON)),
        ])
    }

    private func configJSON() -> JSONValue {
        .object([
            "enabled": .bool(enabledState.enabled),
            "refreshTime": .string(String(format: "%02d:%02d", store.refreshTime.hour, store.refreshTime.minute)),
        ])
    }

    private func parseMax(_ raw: String) throws -> Int {
        guard let value = Int(raw), (1...99).contains(value) else { throw TargetorError.invalidMaxCount }
        return value
    }

    private func parseBool(_ raw: String) throws -> Bool {
        if raw == "true" { return true }
        if raw == "false" { return false }
        throw usage("Expected true or false")
    }

    private func parseRefreshTime(_ raw: String) throws -> RefreshTime {
        let pieces = raw.split(separator: ":", omittingEmptySubsequences: false)
        guard pieces.count == 2, pieces[0].count == 2, pieces[1].count == 2,
              let hour = Int(pieces[0]), let minute = Int(pieces[1])
        else { throw usage("Expected HH:mm") }
        return try RefreshTime(hour: hour, minute: minute)
    }

    private func parseRFC3339(_ raw: String) throws -> Date {
        guard raw.hasSuffix("Z") || raw.range(of: "[+-]\\d{2}:\\d{2}$", options: .regularExpression) != nil,
              let date = ISO8601DateFormatter().date(from: raw)
        else { throw TargetorError.invalidHistoryRange }
        return date
    }

    private func rfc3339(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withColonSeparatorInTimeZone]
        return formatter.string(from: date)
    }

    private func uuid(_ raw: String) throws -> UUID {
        guard let value = UUID(uuidString: raw) else { throw usage("Invalid UUID") }
        return value
    }

    private func usage(_ message: String) -> PeekerError {
        PeekerError(code: "invalid_usage", message: message)
    }

    private func map(_ error: TargetorError) -> PeekerError {
        switch error {
        case .invalidTitle: PeekerError(code: "targetor_invalid_title", message: "Title is required")
        case .invalidIcon: PeekerError(code: "targetor_invalid_icon", message: "Unknown Lucide icon")
        case .invalidPeriod: PeekerError(code: "targetor_invalid_period", message: "Invalid period arguments")
        case .invalidMaxCount: PeekerError(code: "targetor_invalid_max_count", message: "max-count must be 1...99")
        case .targetNotFound: PeekerError(code: "not_found", message: "Target not found")
        case let .ambiguousSelector(ids): PeekerError(
            code: "ambiguous_selector", message: "Target title is ambiguous",
            details: ["candidateIds": .array(ids.map { .string($0.uuidString) })]
        )
        case .targetArchived: PeekerError(code: "targetor_target_archived", message: "Target is archived")
        case .cycleComplete: PeekerError(code: "targetor_cycle_complete", message: "Current period is complete")
        case .eventNotFound: PeekerError(code: "targetor_event_not_found", message: "Check-in event not found")
        case .eventNotCurrent: PeekerError(code: "targetor_event_not_current", message: "Event is not in the current period")
        case .invalidHistoryRange: PeekerError(code: "validation_error", message: "Invalid history range")
        case .noActualChange: PeekerError(code: "validation_error", message: "Update does not change the target")
        }
    }
}

private struct TargetorOptions {
    let values: [String: String]
    let flags: Set<String>
    let positionals: [String]

    init(_ arguments: [String], flags allowedFlags: Set<String> = []) throws {
        var values: [String: String] = [:]
        var flags = Set<String>()
        var positionals: [String] = []
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            if argument.hasPrefix("--") {
                if allowedFlags.contains(argument) {
                    guard flags.insert(argument).inserted else { throw PeekerError(code: "invalid_usage", message: "Duplicate option: \(argument)") }
                    index += 1
                    continue
                }
                guard values[argument] == nil else { throw PeekerError(code: "invalid_usage", message: "Duplicate option: \(argument)") }
                guard index + 1 < arguments.count, !arguments[index + 1].hasPrefix("--") else {
                    throw PeekerError(code: "invalid_usage", message: "Missing value for \(argument)")
                }
                values[argument] = arguments[index + 1]
                index += 2
            } else {
                positionals.append(argument)
                index += 1
            }
        }
        self.values = values; self.flags = flags; self.positionals = positionals
    }

    func value(_ key: String) -> String? { values[key] }
    func has(_ key: String) -> Bool { flags.contains(key) }
    func required(_ key: String) throws -> String {
        guard let value = values[key] else { throw PeekerError(code: "invalid_usage", message: "Missing \(key)") }
        return value
    }
    func requireOnly(_ allowed: Set<String>) throws {
        if let unknown = values.keys.first(where: { !allowed.contains($0) }) ?? flags.first(where: { !allowed.contains($0) }) {
            throw PeekerError(code: "invalid_usage", message: "Unknown option: \(unknown)")
        }
    }
}
