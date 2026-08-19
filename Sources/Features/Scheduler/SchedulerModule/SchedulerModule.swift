import Foundation
import FeatureRuntimeKit
import FunctionCardKit
import MacPlatform
import PeekerCore
import PeekerProtocol
import PersistenceCore
import SchedulerFeature
import SchedulerGRDBAdapter

@MainActor
public struct SchedulerModule: FunctionCardModule {
    public init() {}
    public var id: FeatureID { .scheduler }
    public var databaseMigrations: [AppDatabaseMigration] { SchedulerDatabaseMigrations.all }

    public func makeRegistration(context: FunctionCardModuleContext) -> FunctionCardRegistration {
        makeRuntimeRegistration(context: context).card
    }

    public func makeRuntimeRegistration(context: FunctionCardModuleContext) -> FunctionCardRuntimeRegistration {
        let repository: any SchedulerRepository
        switch context.persistence {
        case let .success(database): repository = SchedulerGRDBRepository(database: database)
        case let .failure(error): repository = UnavailableSchedulerRepository(error: error)
        }
        let preferences = SchedulerModulePreferences(store: context.preferences)
        let store = SchedulerStore(
            repository: repository, eventHub: context.eventHub,
            reminderMinutes: preferences.reminderMinutes, isEnabled: true,
            publishPrompt: context.hostActions.publishPrompt,
            revokePrompt: context.hostActions.revokePrompt,
            onReminderChanged: { preferences.reminderMinutes = $0 }
        )
        let card = SchedulerFeatureFactory.make(store: store)
        return FunctionCardRuntimeRegistration(
            card: card,
            handleCommand: { invocation in await SchedulerCommandHandler(store: store, hostActions: context.hostActions).handle(invocation.arguments) },
            enablementChanged: { enabled in await store.setEnabled(enabled) },
            temporalContextChanged: { await store.temporalContextChanged() }
        )
    }
}

@MainActor
final class SchedulerModulePreferences {
    private enum Key { static let reminder = "schedulerReminderMinutes" }
    private let store: FeaturePreferenceStore
    init(store: FeaturePreferenceStore) { self.store=store; store.register(defaults: [Key.reminder: 10]) }
    var reminderMinutes: Int? {
        get { let value=store.integer(forKey: Key.reminder); return value == 0 ? nil : value }
        set { store.set(newValue ?? 0, forKey: Key.reminder) }
    }
}

@MainActor
private struct SchedulerCommandHandler {
    let store: SchedulerStore
    let hostActions: FunctionCardHostActions

    func handle(_ arguments: [String]) async -> PeekerEnvelope {
        do {
            guard let command=arguments.first else { throw PeekerError(code: "invalid_usage", message: "scheduler command required") }
            switch command {
            case "list": return try await list(Array(arguments.dropFirst()))
            case "get": return try await get(Array(arguments.dropFirst()))
            case "create": return try await create(Array(arguments.dropFirst()))
            case "update": return try await update(Array(arguments.dropFirst()))
            case "delete": return try await delete(Array(arguments.dropFirst()))
            case "source": return try await source(Array(arguments.dropFirst()))
            case "config": return try await config(Array(arguments.dropFirst()))
            default: throw PeekerError(code: "invalid_usage", message: "Unknown scheduler command")
            }
        } catch let error as PeekerError { return .failure(error) }
        catch let error as SchedulerError { return .failure(map(error)) }
        catch { return .failure(PeekerError(code: "persistence_error", message: error.localizedDescription)) }
    }

    private func list(_ args: [String]) async throws -> PeekerEnvelope {
        let options=try Options(args)
        let fromRaw=options.value("--from"), toRaw=options.value("--to")
        guard (fromRaw == nil) == (toRaw == nil) else { throw usage("--from and --to must be provided together") }
        let interval: DateInterval
        if let fromRaw, let toRaw {
            let from=try parseBoundary(fromRaw), to=try parseBoundary(toRaw)
            guard to > from else { throw SchedulerError.invalidTimeRange }; interval=DateInterval(start: from, end: to)
        } else { interval=SchedulerStore.weekInterval(containing: Date(), calendar: .current) }
        let values=try await store.list(from: interval.start, to: interval.end)
        return .success(.object([
            "from": .string(rfc3339(interval.start)), "to": .string(rfc3339(interval.end)),
            "occurrences": .array(values.map(occurrenceJSON))
        ]))
    }

    private func get(_ args: [String]) async throws -> PeekerEnvelope {
        let options=try Options(args); let id=try uuid(options.required("--id"))
        let event=try await store.event(id: id)
        return .success(eventJSON(event))
    }

    private func create(_ args: [String]) async throws -> PeekerEnvelope {
        let options=try Options(args)
        let event=try makeEvent(id: UUID(), options: options, existing: nil)
        return .success(eventJSON(try await store.create(event)))
    }

    private func update(_ args: [String]) async throws -> PeekerEnvelope {
        let options=try Options(args); let id=try uuid(options.required("--id"))
        let existing=try await store.event(id: id)
        let replacement=try makeEvent(id: id, options: options, existing: existing)
        let key=options.value("--occurrence"), scope=try options.value("--scope").map(parseScope)
        let result=try await store.update(replacement, occurrenceKey: key, scope: scope)
        return .success(.object(["event": eventJSON(result.0), "clearedExceptions": .number(Double(result.1))]))
    }

    private func delete(_ args: [String]) async throws -> PeekerEnvelope {
        let options=try Options(args); let id=try uuid(options.required("--id"))
        let scope=try options.value("--scope").map(parseScope)
        let cleared=try await store.delete(id: id, occurrenceKey: options.value("--occurrence"), scope: scope)
        return .success(.object(["deleted": .bool(true), "eventId": .string(id.uuidString), "clearedExceptions": .number(Double(cleared))]))
    }

    private func source(_ args: [String]) async throws -> PeekerEnvelope {
        guard let command=args.first else { throw usage("source command required") }
        let options=try Options(Array(args.dropFirst()))
        switch command {
        case "list":
            await store.load()
            return .success(.object(["sources": .array(store.sources.map(sourceJSON))]))
        case "import":
            let result=try await store.importICS(fileURL: URL(fileURLWithPath: options.required("--file")))
            return importEnvelope(result)
        case "refresh":
            let id=try uuid(options.required("--id")); let source=store.sources.first(where:{$0.id==id})
            guard let source else { throw SchedulerError.sourceNotFound }
            let path=options.value("--file") ?? source.canonicalPath
            return importEnvelope(try await store.importICS(fileURL: URL(fileURLWithPath:path), sourceID:id))
        case "remove":
            let id=try uuid(options.required("--id")); let count=try await store.removeSource(id:id)
            return .success(.object(["deleted":.bool(true),"sourceId":.string(id.uuidString),"deletedEvents":.number(Double(count))]))
        default: throw usage("Unknown source command")
        }
    }

    private func config(_ args: [String]) async throws -> PeekerEnvelope {
        guard let command=args.first else { throw usage("config get|set required") }
        if command == "get" { return .success(configJSON()) }
        guard command == "set" else { throw usage("config get|set required") }
        let options=try Options(Array(args.dropFirst())); var changed=false
        if let enabled=options.value("--enabled") {
            let value=try bool(enabled)
            do { try hostActions.setCardEnabled(.scheduler,value) }
            catch CardRegistryError.atLeastOneCardRequired { throw PeekerError(code:"card_enablement_conflict",message:"At least one card must remain enabled") }
            await store.setEnabled(value); changed=true
        }
        if let reminder=options.value("--reminder") {
            try await store.setReminder(minutes: reminder == "off" ? nil : Int(reminder)); changed=true
        }
        guard changed else { throw usage("config set requires a value") }
        return .success(configJSON())
    }

    private func makeEvent(id: UUID, options: Options, existing: SchedulerEvent?) throws -> SchedulerEvent {
        let title=options.value("--title") ?? existing?.title ?? ""
        let time: SchedulerEventTime
        if let start=options.value("--start"), let end=options.value("--end") {
            let s=try parseRFC3339(start), e=try parseRFC3339(end)
            time = .timed(startMilliseconds: ms(s), endMilliseconds: ms(e), timeZoneID: TimeZone.current.identifier)
        } else if let startRaw=options.value("--all-day-start"), let start=SchedulerLocalDate(startRaw) {
            let end = try options.value("--all-day-end").flatMap(SchedulerLocalDate.init)
                ?? start.adding(days:1,in:.current) ?? { throw SchedulerError.invalidTimeRange }()
            time = .allDay(start:start,endExclusive:end)
        } else if let existing { time=existing.time }
        else { throw usage("A complete timed or all-day range is required") }
        let recurrence=try recurrence(options: options, existing: existing?.recurrence)
        return try SchedulerEvent(
            id:id, sourceID:existing?.sourceID, sourceUID:existing?.sourceUID, sourceSegmentKey:existing?.sourceSegmentKey,
            title:title, notes:options.has("--clear-notes") ? nil : options.value("--notes") ?? existing?.notes,
            location:options.has("--clear-location") ? nil : options.value("--location") ?? existing?.location,
            colorHex:options.value("--color") ?? existing?.colorHex ?? "#0A84FF", time:time, recurrence:recurrence,
            createdAtMilliseconds:existing?.createdAtMilliseconds ?? ms(Date()), updatedAtMilliseconds:ms(Date())
        )
    }

    private func recurrence(options: Options, existing: SchedulerRecurrence?) throws -> SchedulerRecurrence? {
        guard let raw=options.value("--repeat") else { return existing }
        if raw == "none" { return nil }
        guard let frequency=SchedulerFrequency(rawValue:raw) else { throw SchedulerError.invalidRecurrence }
        let interval=options.value("--interval").flatMap(Int.init) ?? 1
        let weekdays=try (options.value("--weekdays")?.split(separator:",").map(String.init) ?? []).map {
            guard let value=SchedulerWeekday(rawValue:$0) else { throw SchedulerError.invalidRecurrence }; return value
        }
        let end:SchedulerRecurrenceEnd
        if let count=options.value("--count").flatMap(Int.init) { end = .count(count) }
        else if let until=options.value("--until") {
            if let day=SchedulerLocalDate(until) { end = .untilDate(day) } else { end = .untilTimed(ms(try parseRFC3339(until))) }
        } else { end = .never }
        return try SchedulerRecurrence(frequency:frequency,interval:interval,weekdays:weekdays,end:end)
    }

    private func occurrenceJSON(_ value: SchedulerOccurrence) -> JSONValue {
        var object:[String:JSONValue] = [
            "eventId":.string(value.eventID.uuidString),"occurrence":.string(value.originalKey),"title":.string(value.title),
            "notes":value.notes.map(JSONValue.string) ?? .null,"location":value.location.map(JSONValue.string) ?? .null,
            "color":.string(value.colorHex),"recurring":.bool(value.recurring),"exception":.bool(value.isException),
            "sourceId":value.sourceID.map { .string($0.uuidString) } ?? .null
        ]
        switch value.time {
        case let .timed(start,end,_): object["allDay"] = .bool(false); object["start"] = .string(rfc3339(date(start))); object["end"] = .string(rfc3339(date(end)))
        case let .allDay(start,end): object["allDay"] = .bool(true); object["start"] = .string(start.description); object["end"] = .string(end.description)
        }
        return .object(object)
    }

    private func eventJSON(_ value: SchedulerEvent) -> JSONValue {
        var object:[String:JSONValue] = ["eventId":.string(value.id.uuidString),"title":.string(value.title),"color":.string(value.colorHex),
            "notes":value.notes.map(JSONValue.string) ?? .null,"location":value.location.map(JSONValue.string) ?? .null,
            "sourceId":value.sourceID.map{.string($0.uuidString)} ?? .null,"sourceUid":value.sourceUID.map(JSONValue.string) ?? .null]
        switch value.time {
        case let .timed(start,end,zone): object["allDay"] = .bool(false); object["start"] = .string(rfc3339(date(start))); object["end"] = .string(rfc3339(date(end))); object["normalizedTimeZone"] = .string(zone)
        case let .allDay(start,end): object["allDay"] = .bool(true); object["start"] = .string(start.description); object["end"] = .string(end.description)
        }
        return .object(object)
    }

    private func sourceJSON(_ value: SchedulerSource) -> JSONValue { .object(["sourceId":.string(value.id.uuidString),"name":.string(value.displayName),"path":.string(value.canonicalPath),"lastSuccessfulImportAt":value.lastSuccessfulImportAtMilliseconds.map{.string(rfc3339(date($0)))} ?? .null]) }
    private func configJSON() -> JSONValue { .object(["enabled":.bool(store.isEnabled),"reminder":.object(["enabled":.bool(store.reminderMinutes != nil),"minutes":store.reminderMinutes.map{.number(Double($0))} ?? .null])]) }
    private func importEnvelope(_ result:(SchedulerImportCommit,[SchedulerImportWarning])) -> PeekerEnvelope {
        let commit=result.0
        return .success(.object(["source":sourceJSON(commit.source),"created":.number(Double(commit.created)),"updated":.number(Double(commit.updated)),"deleted":.number(Double(commit.deleted)),"skipped":.number(Double(commit.skipped))]), warnings: result.1.map { PeekerWarning(code:$0.code,message:$0.message,details:$0.uid.map{["uid":.string($0)]}) })
    }

    private func parseScope(_ raw:String) throws -> SchedulerMutationScope { guard let value=SchedulerMutationScope(rawValue:raw) else { throw usage("Invalid scope") }; return value }
    private func uuid(_ raw:String) throws -> UUID { guard let value=UUID(uuidString:raw) else { throw usage("Invalid UUID") }; return value }
    private func bool(_ raw:String) throws -> Bool { if raw=="true" {return true}; if raw=="false" {return false}; throw usage("Expected true or false") }
    private func parseBoundary(_ raw:String) throws -> Date { if let day=SchedulerLocalDate(raw),let date=day.date(in:.current){return date}; return try parseRFC3339(raw) }
    private func parseRFC3339(_ raw:String) throws -> Date { guard raw.hasSuffix("Z") || raw.range(of:"[+-]\\d{2}:\\d{2}$",options:.regularExpression) != nil, let date=ISO8601DateFormatter().date(from:raw) else { throw usage("Expected RFC 3339 with Z or offset") }; return date }
    private func rfc3339(_ date:Date) -> String { let f=ISO8601DateFormatter(); f.formatOptions=[.withInternetDateTime,.withColonSeparatorInTimeZone]; return f.string(from:date) }
    private func ms(_ date:Date)->Int64 { Int64((date.timeIntervalSince1970*1000).rounded()) }
    private func date(_ ms:Int64)->Date { Date(timeIntervalSince1970:Double(ms)/1000) }
    private func usage(_ message:String)->PeekerError { PeekerError(code:"validation_error",message:message) }

    private func map(_ error:SchedulerError)->PeekerError {
        switch error {
        case .invalidTitle:return PeekerError(code:"scheduler_invalid_title",message:"Title is required")
        case .invalidTimeRange:return PeekerError(code:"scheduler_invalid_time_range",message:"Invalid time range")
        case .invalidRecurrence:return PeekerError(code:"scheduler_invalid_recurrence",message:"Invalid recurrence")
        case .eventNotFound:return PeekerError(code:"not_found",message:"Event not found")
        case .occurrenceNotFound:return PeekerError(code:"scheduler_occurrence_not_found",message:"Occurrence not found")
        case .scopeRequired:return PeekerError(code:"scheduler_scope_required",message:"Occurrence and scope are required")
        case .scopeNotAllowed:return PeekerError(code:"scheduler_scope_not_allowed",message:"Scope is not allowed")
        case .sourceNotFound:return PeekerError(code:"scheduler_source_not_found",message:"Source not found")
        case .sourceUnreadable:return PeekerError(code:"scheduler_source_unreadable",message:"Source is unreadable")
        case .sourcePathConflict:return PeekerError(code:"scheduler_source_path_conflict",message:"Source path belongs to another source")
        case let .icsParseFailed(message):return PeekerError(code:"scheduler_ics_parse_failed",message:message)
        }
    }
}

private struct Options {
    private var values:[String:String]=[:]; private var flags=Set<String>()
    init(_ args:[String]) throws {
        var index=0
        while index<args.count {
            let key=args[index]; guard key.hasPrefix("--") else { throw PeekerError(code:"invalid_usage",message:"Unexpected argument: \(key)") }
            if ["--clear-notes","--clear-location"].contains(key) { flags.insert(key); index += 1; continue }
            guard index+1<args.count,!args[index+1].hasPrefix("--") else { throw PeekerError(code:"invalid_usage",message:"Missing value for \(key)") }
            guard values[key] == nil else { throw PeekerError(code:"invalid_usage",message:"Duplicate option: \(key)") }
            values[key]=args[index+1]; index += 2
        }
    }
    func value(_ key:String)->String?{values[key]}
    func required(_ key:String)throws->String{guard let value=values[key] else{throw PeekerError(code:"invalid_usage",message:"Missing \(key)")};return value}
    func has(_ key:String)->Bool{flags.contains(key)}
}

private final class UnavailableSchedulerRepository: SchedulerRepository, Sendable {
    private let error:StartupPersistenceError; init(error:StartupPersistenceError){self.error=error}
    func snapshot() async throws->SchedulerSnapshot{throw error}; func event(id:UUID)async throws->SchedulerEvent?{throw error}
    func save(_ event:SchedulerEvent)async throws->SchedulerEvent{throw error}; func deleteEvent(id:UUID)async throws->Bool{throw error}
    func saveOverride(_ override:SchedulerOccurrenceOverride)async throws{throw error}; func deleteOverrides(eventID:UUID,fromKey:String?)async throws->Int{throw error}
    func sources()async throws->[SchedulerSource]{throw error}; func source(id:UUID)async throws->SchedulerSource?{throw error}
    func saveSource(_ source:SchedulerSource)async throws{throw error}; func removeSource(id:UUID)async throws->Int{throw error}
    func replaceSource(_ source:SchedulerSource,series:[SchedulerImportedSeries],protectedUIDs:Set<String>)async throws->SchedulerImportCommit{throw error}
}
