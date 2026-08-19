import Foundation
import FeatureRuntimeKit
import FunctionCardKit
import PeekerCore
import PeekerProtocol
import PusherFeature

@MainActor
final class PusherEnablementState { var enabled=true }

@MainActor
struct PusherCommandHandler {
    let store:PusherStore
    let enabledState:PusherEnablementState
    let setEnabled:(Bool)throws->Void

    func handle(_ args:[String]) async -> PeekerEnvelope {
        do {
            guard let command=args.first else{throw usage("pusher command required")}
            await store.load()
            switch command {
            case "list":return try list(Array(args.dropFirst()))
            case "get":return .success(taskJSON(try task(for:Selector(Array(args.dropFirst())))))
            case "create":return try await create(Array(args.dropFirst()))
            case "update":return try await update(Array(args.dropFirst()))
            case "delete":return try await delete(Array(args.dropFirst()))
            case "move":return try await move(Array(args.dropFirst()))
            case "config":return try await config(Array(args.dropFirst()))
            default:throw usage("Unknown pusher command")
            }
        } catch let error as PeekerError{return .failure(error)}
        catch {return .failure(PeekerError(code:"persistence_error",message:error.localizedDescription))}
    }

    private func list(_ args:[String])throws->PeekerEnvelope {
        let options=try PusherOptions(args); let status=try options.value("--status").map(parseStatus)
        guard let board=store.board else{throw persistence()}
        let tasks=board.allTasks.filter{status==nil || $0.status==status}.sorted{a,b in a.status.rawValue==b.status.rawValue ? a.position<b.position : statusOrder(a.status)<statusOrder(b.status)}
        return .success(.object(["businessDay":.object(["start":.string(iso(board.businessDay.start)),"end":.string(iso(board.businessDay.end))]),"tasks":.array(tasks.map(taskJSON))]))
    }
    private func create(_ args:[String])async throws->PeekerEnvelope {
        let options=try PusherOptions(args);let old=Set(store.board?.allTasks.map(\.id) ?? [])
        let urgency=try parseUrgency(options.required("--urgency"));let daily=try options.value("--daily").map(bool) ?? false
        let title = try options.required("--title")
        guard await store.create(title:title,urgency:urgency,repeatsDaily:daily),let created=store.board?.allTasks.first(where:{!old.contains($0.id)})else{throw persistence()}
        return .success(taskJSON(created))
    }
    private func update(_ args:[String])async throws->PeekerEnvelope {
        let selector=try Selector(args);let options=try PusherOptions(selector.remaining);let current=try task(for:selector)
        let title=options.value("--title") ?? current.title;let urgency=try options.value("--urgency").map(parseUrgency) ?? current.urgency;let daily=try options.value("--daily").map(bool) ?? current.repeatsDaily
        guard options.value("--title") != nil || options.value("--urgency") != nil || options.value("--daily") != nil else{throw usage("update requires a field")}
        guard await store.update(taskID:current.id,title:title,urgency:urgency,repeatsDaily:daily),let value=store.board?.allTasks.first(where:{$0.id==current.id})else{throw persistence()}
        return .success(taskJSON(value))
    }
    private func delete(_ args:[String])async throws->PeekerEnvelope {
        let selected=try task(for:Selector(args));guard await store.delete(taskID:selected.id)else{throw persistence()}
        var object=taskObject(selected);object["deleted"] = .bool(true);return .success(.object(object))
    }
    private func move(_ args:[String])async throws->PeekerEnvelope {
        let selector=try Selector(args);let options=try PusherOptions(selector.remaining);let selected=try task(for:selector);let status=try parseStatus(options.required("--status"))
        guard !(options.value("--before") != nil && options.value("--after") != nil)else{throw usage("before and after are mutually exclusive")}
        guard let board=store.board else{throw persistence()};let targetColumn=board.tasks(in:status);var position=targetColumn.count
        if let raw=options.value("--before") { guard let id=UUID(uuidString:raw),let target=targetColumn.firstIndex(where:{$0.id==id})else{throw targetError(raw,status:status,board:board)};position=target }
        if let raw=options.value("--after") { guard let id=UUID(uuidString:raw),let target=targetColumn.firstIndex(where:{$0.id==id})else{throw targetError(raw,status:status,board:board)};position=target+1 }
        let before=board;guard await store.move(taskID:selected.id,to:status,at:position),let after=store.board,let value=after.allTasks.first(where:{$0.id==selected.id})else{throw persistence()}
        let changed = PusherStatus.allCases.contains { status in
            before.tasks(in: status).map(\.id) != after.tasks(in: status).map(\.id)
        }
        return .success(.object(["task":taskJSON(value),"changed":.bool(changed),"orderedTargetIds":.array(after.tasks(in:status).map{.string($0.id.uuidString)})]))
    }
    private func config(_ args:[String])async throws->PeekerEnvelope {
        guard let command=args.first else{throw usage("config get|set required")};if command=="get"{return .success(configJSON())};guard command=="set"else{throw usage("config get|set required")}
        let options=try PusherOptions(Array(args.dropFirst()));var any=false
        if let raw=options.value("--enabled"){let enabled=try bool(raw);do{try setEnabled(enabled)}catch CardRegistryError.atLeastOneCardRequired{throw PeekerError(code:"card_enablement_conflict",message:"At least one card must remain enabled")};enabledState.enabled=enabled;any=true}
        if let raw=options.value("--carry-incomplete"){store.updateCarryIncomplete(try bool(raw));any=true}
        if let raw=options.value("--refresh-time"){await store.updateRefreshTime(try refresh(raw));any=true}
        guard any else{throw usage("config set requires a value")};return .success(configJSON())
    }

    private func task(for selector:Selector)throws->PusherTask {guard let board=store.board else{throw persistence()};switch selector.kind{case let .id(id):guard let value=board.allTasks.first(where:{$0.id==id})else{throw notFound()};return value;case let .name(name):let matches=board.allTasks.filter{$0.title==name};guard matches.count==1 else{if matches.isEmpty{throw notFound()};throw PeekerError(code:"ambiguous_selector",message:"Title is ambiguous",details:["candidateIds":.array(matches.map{.string($0.id.uuidString)})])};return matches[0]}}
    private func taskJSON(_ task:PusherTask)->JSONValue{.object(taskObject(task))}
    private func taskObject(_ task:PusherTask)->[String:JSONValue]{["taskId":.string(task.id.uuidString),"seriesId":task.seriesID.map{.string($0.uuidString)} ?? .null,"title":.string(task.title),"urgency":.string(task.urgency.rawValue),"status":.string(task.status.rawValue),"position":.number(Double(task.position)),"daily":.bool(task.repeatsDaily),"createdAt":.string(iso(Date(millisecondsSince1970:task.createdAtMilliseconds))),"updatedAt":.string(iso(Date(millisecondsSince1970:task.updatedAtMilliseconds)))]}
    private func configJSON()->JSONValue{.object(["enabled":.bool(enabledState.enabled),"carryIncomplete":.bool(store.carryIncomplete),"refreshTime":.string(String(format:"%02d:%02d",store.refreshTime.hour,store.refreshTime.minute))])}
    private func targetError(_ raw:String,status:PusherStatus,board:PusherBoard)->PeekerError{if let id=UUID(uuidString:raw),board.allTasks.contains(where:{$0.id==id}){return PeekerError(code:"pusher_target_wrong_column",message:"Target is in another column")};return PeekerError(code:"pusher_target_not_found",message:"Target not found")}
    private func parseUrgency(_ raw:String)throws->PusherUrgency{guard let value=PusherUrgency(rawValue:raw)else{throw PeekerError(code:"pusher_invalid_urgency",message:"Invalid urgency")};return value}
    private func parseStatus(_ raw:String)throws->PusherStatus{guard let value=PusherStatus(rawValue:raw)else{throw PeekerError(code:"pusher_invalid_status",message:"Invalid status")};return value}
    private func statusOrder(_ value:PusherStatus)->Int{PusherStatus.allCases.firstIndex(of:value)!}
    private func refresh(_ raw:String)throws->RefreshTime{let p=raw.split(separator:":").compactMap{Int($0)};guard p.count==2 else{throw usage("Invalid refresh time")};return try RefreshTime(hour:p[0],minute:p[1])}
    private func bool(_ raw:String)throws->Bool{if raw=="true"{return true};if raw=="false"{return false};throw usage("Expected true or false")}
    private func iso(_ date:Date)->String{ISO8601DateFormatter().string(from:date)}
    private func usage(_ message:String)->PeekerError{PeekerError(code:"invalid_usage",message:message)}
    private func notFound()->PeekerError{PeekerError(code:"not_found",message:"Pusher task not found")}
    private func persistence()->PeekerError{PeekerError(code:"persistence_error",message:store.errorMessage ?? "Pusher mutation failed")}
}

private struct Selector{enum Kind{case id(UUID),name(String)};let kind:Kind;let remaining:[String];init(_ args:[String])throws{if let i=args.firstIndex(of:"--id"){guard i+1<args.count,let id=UUID(uuidString:args[i+1])else{throw PeekerError(code:"invalid_usage",message:"Invalid --id")};var c=args;c.removeSubrange(i...i+1);kind = .id(id);remaining=c;return};guard let i=args.firstIndex(where:{!$0.hasPrefix("--")})else{throw PeekerError(code:"invalid_usage",message:"Selector required")};kind = .name(args[i].trimmingCharacters(in:.whitespacesAndNewlines));var c=args;c.remove(at:i);remaining=c}}
private struct PusherOptions{private var values:[String:String]=[:];init(_ args:[String])throws{var i=0;while i<args.count{guard args[i].hasPrefix("--"),i+1<args.count,!args[i+1].hasPrefix("--")else{throw PeekerError(code:"invalid_usage",message:"Invalid option")};values[args[i]]=args[i+1];i+=2}};func value(_ key:String)->String?{values[key]};func required(_ key:String)throws->String{guard let v=values[key]else{throw PeekerError(code:"invalid_usage",message:"Missing \(key)")};return v}}
