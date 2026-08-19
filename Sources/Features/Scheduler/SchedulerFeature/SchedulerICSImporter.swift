import Foundation

public struct SchedulerImportWarning: Codable, Equatable, Sendable {
    public let code: String
    public let uid: String?
    public let component: Int?
    public let message: String
}

public struct SchedulerImportedSeries: Sendable {
    public let uid: String
    public let event: SchedulerEvent
    public let overrides: [SchedulerOccurrenceOverride]
}

public struct SchedulerICSParseResult: Sendable {
    public let series: [SchedulerImportedSeries]
    public let protectedUIDs: Set<String>
    public let warnings: [SchedulerImportWarning]
}

public enum SchedulerICSParser {
    public static func parse(_ data: Data, systemTimeZone: TimeZone = .current) throws -> SchedulerICSParseResult {
        guard var text = String(data: data, encoding: .utf8) else { throw SchedulerError.icsParseFailed("ICS is not UTF-8") }
        text = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var lines: [String] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if (line.hasPrefix(" ") || line.hasPrefix("\t")), !lines.isEmpty { lines[lines.count - 1] += line.dropFirst() }
            else { lines.append(line) }
        }
        guard lines.contains(where: { $0.uppercased() == "BEGIN:VCALENDAR" }),
              lines.contains(where: { $0.uppercased() == "END:VCALENDAR" }) else {
            throw SchedulerError.icsParseFailed("Missing VCALENDAR")
        }
        var components: [[Property]] = []
        var current: [Property]?
        for (index, line) in lines.enumerated() {
            if line.uppercased() == "BEGIN:VEVENT" { current = []; continue }
            if line.uppercased() == "END:VEVENT" {
                if let current { components.append(current) }
                current = nil; continue
            }
            if current != nil, let property = property(line, line: index + 1) { current!.append(property) }
        }

        let grouped = Dictionary(grouping: components.enumerated().map { ($0.offset, $0.element) }) {
            value in value.1.first(where: { $0.name == "UID" })?.value.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        var series: [SchedulerImportedSeries] = []
        var protected = Set<String>()
        var warnings: [SchedulerImportWarning] = []
        for (uid, entries) in grouped {
            guard !uid.isEmpty else {
                warnings.append(.init(code: "ics_missing_uid", uid: nil, component: entries.first?.0, message: "VEVENT has no UID"))
                continue
            }
            do {
                guard let masterEntry = entries.first(where: { entry in
                    !entry.1.contains(where: { $0.name == "RECURRENCE-ID" })
                }) else { throw SchedulerError.icsParseFailed("UID \(uid) has no master VEVENT") }
                if value("STATUS", in: masterEntry.1)?.uppercased() == "CANCELLED" { continue }
                var event = try parseMaster(masterEntry.1, uid: uid, timeZone: systemTimeZone)
                var overrides: [SchedulerOccurrenceOverride] = []
                for entry in entries where entry.0 != masterEntry.0 {
                    let properties = entry.1
                    guard let recurrenceProperty = properties.first(where: { $0.name == "RECURRENCE-ID" }) else { continue }
                    let keyTime = try parseTime(recurrenceProperty, systemTimeZone: systemTimeZone)
                    let key = SchedulerRecurrenceExpander.originalKey(keyTime)
                    if value("STATUS", in: properties)?.uppercased() == "CANCELLED" {
                        overrides.append(SchedulerOccurrenceOverride(eventID: event.id, occurrenceKey: key, isCancelled: true, replacement: nil))
                    } else {
                        let replacementEvent = try parseMaster(properties, uid: uid, timeZone: systemTimeZone, fallback: event)
                        let occurrence = SchedulerOccurrence(
                            eventID: event.id, originalKey: key, title: replacementEvent.title,
                            notes: replacementEvent.notes, location: replacementEvent.location,
                            colorHex: replacementEvent.colorHex, time: replacementEvent.time,
                            recurring: true, isException: true, sourceID: nil
                        )
                        overrides.append(SchedulerOccurrenceOverride(eventID: event.id, occurrenceKey: key, isCancelled: false, replacement: occurrence))
                    }
                }
                for property in masterEntry.1 where property.name == "EXDATE" {
                    for raw in property.value.split(separator: ",") {
                        var copy = property; copy.value = String(raw)
                        let key = SchedulerRecurrenceExpander.originalKey(try parseTime(copy, systemTimeZone: systemTimeZone))
                        overrides.append(SchedulerOccurrenceOverride(eventID: event.id, occurrenceKey: key, isCancelled: true, replacement: nil))
                    }
                }
                for property in masterEntry.1 where property.name == "RDATE" {
                    for raw in property.value.split(separator: ",") {
                        var copy = property; copy.value = String(raw)
                        let parsed = try parseTime(copy, systemTimeZone: systemTimeZone)
                        let key = SchedulerRecurrenceExpander.originalKey(parsed)
                        let replacementTime = try occurrenceTime(startingAt: parsed, usingDurationOf: event.time, timeZone: systemTimeZone)
                        let occurrence = SchedulerOccurrence(
                            eventID: event.id, originalKey: key, title: event.title, notes: event.notes,
                            location: event.location, colorHex: event.colorHex, time: replacementTime,
                            recurring: true, isException: true, sourceID: nil
                        )
                        overrides.append(SchedulerOccurrenceOverride(eventID: event.id, occurrenceKey: key, isCancelled: false, replacement: occurrence))
                    }
                }
                event.sourceUID = uid
                series.append(SchedulerImportedSeries(uid: uid, event: event, overrides: overrides))
            } catch {
                protected.insert(uid)
                warnings.append(.init(code: "ics_invalid_uid", uid: uid, component: entries.first?.0, message: error.localizedDescription))
            }
        }
        return SchedulerICSParseResult(series: series, protectedUIDs: protected, warnings: warnings)
    }

    private struct Property { var name: String; var parameters: [String: String]; var value: String; let line: Int }

    private static func property(_ line: String, line number: Int) -> Property? {
        guard let colon = line.firstIndex(of: ":") else { return nil }
        let head = line[..<colon].split(separator: ";").map(String.init)
        guard let first = head.first else { return nil }
        var parameters: [String: String] = [:]
        for item in head.dropFirst() {
            let pair = item.split(separator: "=", maxSplits: 1).map(String.init)
            if pair.count == 2 { parameters[pair[0].uppercased()] = pair[1].trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }
        }
        return Property(name: first.uppercased(), parameters: parameters, value: String(line[line.index(after: colon)...]), line: number)
    }

    private static func value(_ name: String, in properties: [Property]) -> String? {
        properties.first(where: { $0.name == name })?.value
    }

    private static func parseMaster(
        _ properties: [Property], uid: String, timeZone: TimeZone, fallback: SchedulerEvent? = nil
    ) throws -> SchedulerEvent {
        guard let startProperty = properties.first(where: { $0.name == "DTSTART" }) else { throw SchedulerError.icsParseFailed("UID \(uid) has no DTSTART") }
        let start = try parseTime(startProperty, systemTimeZone: timeZone)
        let end: SchedulerEventTime
        if let endProperty = properties.first(where: { $0.name == "DTEND" }) {
            let parsedEnd = try parseTime(endProperty, systemTimeZone: timeZone)
            end = try combine(start: start, end: parsedEnd)
        } else if let duration = value("DURATION", in: properties) {
            end = try addDuration(duration, to: start, timeZone: timeZone)
        } else if case let .allDay(day, _) = start, let next = day.adding(days: 1, in: timeZone) {
            end = .allDay(start: day, endExclusive: next)
        } else { throw SchedulerError.icsParseFailed("UID \(uid) has no positive duration") }

        let recurrence = try properties.first(where: { $0.name == "RRULE" }).map { try parseRecurrence($0.value, start: start, systemTimeZone: timeZone) }
        return try SchedulerEvent(
            id: fallback?.id ?? UUID(), title: unescape(value("SUMMARY", in: properties) ?? fallback?.title ?? "无标题日程"),
            notes: value("DESCRIPTION", in: properties).map(unescape) ?? fallback?.notes,
            location: value("LOCATION", in: properties).map(unescape) ?? fallback?.location,
            colorHex: fallback?.colorHex ?? "#0A84FF", time: end,
            recurrence: recurrence ?? fallback?.recurrence
        )
    }

    private static func parseTime(_ property: Property, systemTimeZone: TimeZone) throws -> SchedulerEventTime {
        if property.parameters["VALUE"]?.uppercased() == "DATE" || property.value.count == 8 {
            let raw = property.value
            guard raw.count == 8,
                  let year = Int(raw.prefix(4)), let month = Int(raw.dropFirst(4).prefix(2)), let day = Int(raw.suffix(2)),
                  let date = try? SchedulerLocalDate(year: year, month: month, day: day),
                  let end = date.adding(days: 1, in: systemTimeZone) else { throw SchedulerError.invalidTimeRange }
            return .allDay(start: date, endExclusive: end)
        }
        let zone: TimeZone
        var raw = property.value
        let hasNumericOffset = raw.range(of: "[+-]\\d{4}$", options: .regularExpression) != nil
        if raw.hasSuffix("Z") { zone = TimeZone(secondsFromGMT: 0)!; raw.removeLast() }
        else if hasNumericOffset { zone = TimeZone(secondsFromGMT: 0)! }
        else if let tzid = property.parameters["TZID"] {
            guard let parsed = TimeZone(identifier: tzid) else { throw SchedulerError.icsParseFailed("Unsupported TZID \(tzid)") }
            zone = parsed
        } else { zone = systemTimeZone }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = zone
        formatter.dateFormat = hasNumericOffset ? "yyyyMMdd'T'HHmmssZ" : (raw.count == 13 ? "yyyyMMdd'T'HHmm" : "yyyyMMdd'T'HHmmss")
        guard let date = formatter.date(from: raw) else { throw SchedulerError.invalidTimeRange }
        let ms = Int64((date.timeIntervalSince1970 * 1000).rounded())
        return .timed(startMilliseconds: ms, endMilliseconds: ms + 1, timeZoneID: systemTimeZone.identifier)
    }

    private static func occurrenceTime(
        startingAt start: SchedulerEventTime,
        usingDurationOf template: SchedulerEventTime,
        timeZone: TimeZone
    ) throws -> SchedulerEventTime {
        switch (start, template) {
        case let (.timed(value, _, zone), .timed(templateStart, templateEnd, _)):
            return .timed(startMilliseconds: value, endMilliseconds: value + templateEnd - templateStart, timeZoneID: zone)
        case let (.allDay(day, _), .allDay(templateStart, templateEnd)):
            guard let startDate = templateStart.date(in: timeZone), let endDate = templateEnd.date(in: timeZone),
                  let dayDate = day.date(in: timeZone) else { throw SchedulerError.invalidTimeRange }
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
            let count = calendar.dateComponents([.day], from: startDate, to: endDate).day ?? 0
            guard count > 0, let end = calendar.date(byAdding: .day, value: count, to: dayDate),
                  let endDay = try? SchedulerLocalDate(year: calendar.component(.year, from: end), month: calendar.component(.month, from: end), day: calendar.component(.day, from: end)) else { throw SchedulerError.invalidTimeRange }
            return .allDay(start: day, endExclusive: endDay)
        default: throw SchedulerError.invalidTimeRange
        }
    }

    private static func combine(start: SchedulerEventTime, end: SchedulerEventTime) throws -> SchedulerEventTime {
        switch (start, end) {
        case let (.timed(start, _, zone), .timed(end, _, _)) where end > start:
            return .timed(startMilliseconds: start, endMilliseconds: end, timeZoneID: zone)
        case let (.allDay(start, _), .allDay(end, _)) where end > start:
            return .allDay(start: start, endExclusive: end)
        default: throw SchedulerError.invalidTimeRange
        }
    }

    private static func addDuration(_ raw: String, to start: SchedulerEventTime, timeZone: TimeZone) throws -> SchedulerEventTime {
        let pattern = try NSRegularExpression(pattern: "^P(?:(\\d+)D)?(?:T(?:(\\d+)H)?(?:(\\d+)M)?(?:(\\d+)S)?)?$")
        let range = NSRange(raw.startIndex..., in: raw)
        guard let match = pattern.firstMatch(in: raw, range: range) else { throw SchedulerError.invalidTimeRange }
        func number(_ index: Int) -> Int {
            let range = match.range(at: index); guard range.location != NSNotFound, let swift = Range(range, in: raw) else { return 0 }
            return Int(raw[swift]) ?? 0
        }
        let seconds = number(1) * 86_400 + number(2) * 3_600 + number(3) * 60 + number(4)
        guard seconds > 0 else { throw SchedulerError.invalidTimeRange }
        switch start {
        case let .timed(value, _, zone): return .timed(startMilliseconds: value, endMilliseconds: value + Int64(seconds * 1000), timeZoneID: zone)
        case let .allDay(day, _):
            guard seconds % 86_400 == 0, let end = day.adding(days: seconds / 86_400, in: timeZone) else { throw SchedulerError.invalidTimeRange }
            return .allDay(start: day, endExclusive: end)
        }
    }

    private static func parseRecurrence(_ raw: String, start: SchedulerEventTime, systemTimeZone: TimeZone) throws -> SchedulerRecurrence {
        let entries = Dictionary(uniqueKeysWithValues: raw.split(separator: ";").map { item -> (String, String) in
            let pair = item.split(separator: "=", maxSplits: 1).map(String.init); return (pair[0].uppercased(), pair.count > 1 ? pair[1] : "")
        })
        let supported = Set(["FREQ", "INTERVAL", "BYDAY", "UNTIL", "COUNT"])
        guard Set(entries.keys).isSubset(of: supported), let frequency = entries["FREQ"].flatMap({ SchedulerFrequency(rawValue: $0.lowercased()) }) else { throw SchedulerError.invalidRecurrence }
        let interval = entries["INTERVAL"].flatMap(Int.init) ?? 1
        let map = ["MO": SchedulerWeekday.mon, "TU": .tue, "WE": .wed, "TH": .thu, "FR": .fri, "SA": .sat, "SU": .sun]
        let weekdays = try (entries["BYDAY"]?.split(separator: ",").map(String.init) ?? []).map {
            guard let day = map[$0] else { throw SchedulerError.invalidRecurrence }; return day
        }
        let end: SchedulerRecurrenceEnd
        if let count = entries["COUNT"].flatMap(Int.init) { end = .count(count) }
        else if let until = entries["UNTIL"] {
            var property = Property(name: "UNTIL", parameters: [:], value: until, line: 0)
            if case .allDay = start { property.parameters["VALUE"] = "DATE" }
            switch try parseTime(property, systemTimeZone: systemTimeZone) {
            case let .timed(value, _, _): end = .untilTimed(value)
            case let .allDay(value, _): end = .untilDate(value)
            }
        } else { end = .never }
        return try SchedulerRecurrence(frequency: frequency, interval: interval, weekdays: weekdays, end: end)
    }

    private static func unescape(_ value: String) -> String {
        value.replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\,", with: ",")
            .replacingOccurrences(of: "\\;", with: ";")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }
}
