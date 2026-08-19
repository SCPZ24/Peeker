import Foundation
import FeatureRuntimeKit
import FunctionCardKit
import PeekerCore
import PeekerProtocol
import TimerFeature

@MainActor
final class ModuleEnablementState { var enabled = true }

@MainActor
struct TimerCommandHandler {
    let store: TimerStore
    let enabledState: ModuleEnablementState
    let setEnabled: (Bool) throws -> Void

    func handle(_ args: [String]) async -> PeekerEnvelope {
        do {
            guard let command=args.first else { throw usage("timer command required") }
            await store.load()
            switch command {
            case "list": return .success(listJSON())
            case "get": return .success(taskJSON(try task(for: try Selector(Array(args.dropFirst())))))
            case "create": return try await create(Array(args.dropFirst()))
            case "update": return try await update(Array(args.dropFirst()))
            case "delete": return try await delete(Array(args.dropFirst()))
            case "start": return try await start(Array(args.dropFirst()))
            case "pause": return try await pause()
            case "move": return try await move(Array(args.dropFirst()))
            case "config": return try await config(Array(args.dropFirst()))
            default: throw usage("Unknown timer command")
            }
        } catch let error as PeekerError { return .failure(error) }
        catch let error as TimerDomainError { return .failure(map(error)) }
        catch { return .failure(PeekerError(code:"persistence_error",message:error.localizedDescription)) }
    }

    private func create(_ args:[String]) async throws -> PeekerEnvelope {
        let options=try TimerOptions(args); let old=Set(store.templates.map(\.id))
        let name=try options.required("--name"), target=try parseDuration(options.required("--target")), color=try color(options.required("--color"))
        await store.createTemplate(name:name,targetSeconds:target,colorHex:color)
        guard let created=store.templates.first(where:{!old.contains($0.id)}) else { throw persistence() }
        return .success(taskJSON(try task(templateID:created.id)))
    }

    private func update(_ args:[String]) async throws -> PeekerEnvelope {
        let selector=try Selector(args); let options=try TimerOptions(selector.remaining)
        let selected=try template(for:selector); var changed=selected
        var any=false
        if let name=options.value("--name") { changed.name=name.trimmingCharacters(in:.whitespacesAndNewlines); any=true }
        if let target=options.value("--target") { changed.targetSeconds=try parseDuration(target); any=true }
        if let value=options.value("--color") { changed.colorHex=try color(value); any=true }
        guard any else { throw usage("update requires a changed field") }
        changed.updatedAtMilliseconds=Int64(Date().timeIntervalSince1970*1000)
        await store.updateTemplate(changed)
        guard store.templates.contains(where:{$0==changed}) else { throw persistence() }
        return .success(taskJSON(try task(templateID:changed.id)))
    }

    private func delete(_ args:[String]) async throws -> PeekerEnvelope {
        let selector=try Selector(args); let selected=try template(for:selector)
        let snapshot=try task(templateID:selected.id); await store.deleteTemplate(id:selected.id)
        guard !store.templates.contains(where:{$0.id==selected.id}) else { throw persistence() }
        var object=taskObject(snapshot); object["deleted"] = .bool(true)
        return .success(.object(object))
    }

    private func start(_ args:[String]) async throws -> PeekerEnvelope {
        let selector=try Selector(args); let selected=try task(for:selector)
        if let active=store.runningTask,active.templateID != selected.templateID { throw PeekerError(code:"timer_already_running",message:"Another task is running") }
        if selected.status == .completed { throw PeekerError(code:"timer_task_completed",message:"Task is completed") }
        await store.start(taskID:selected.id)
        let result=try task(templateID:selected.templateID); guard result.status == .running else { throw persistence() }
        return .success(taskJSON(result))
    }

    private func pause() async throws -> PeekerEnvelope {
        guard let active=store.runningTask else { throw PeekerError(code:"timer_no_active_task",message:"No active task") }
        try await store.pause(); return .success(taskJSON(try task(templateID:active.templateID)))
    }

    private func move(_ args:[String]) async throws -> PeekerEnvelope {
        let selector=try Selector(args); let options=try TimerOptions(selector.remaining)
        guard !(options.value("--before") != nil && options.value("--after") != nil) else { throw usage("before and after are mutually exclusive") }
        let selected=try template(for:selector); guard let source=store.templates.firstIndex(where:{$0.id==selected.id}) else { throw notFound() }
        var destination=store.templates.count
        if let before=options.value("--before") { guard let id=UUID(uuidString:before),let index=store.templates.firstIndex(where:{$0.id==id}) else { throw PeekerError(code:"timer_target_not_found",message:"Target not found") }; destination=index }
        if let after=options.value("--after") { guard let id=UUID(uuidString:after),let index=store.templates.firstIndex(where:{$0.id==id}) else { throw PeekerError(code:"timer_target_not_found",message:"Target not found") }; destination=index+1 }
        await store.reorderTemplates(fromOffsets:IndexSet(integer:source),toOffset:destination)
        return .success(taskJSON(try task(templateID:selected.id)))
    }

    private func config(_ args:[String]) async throws -> PeekerEnvelope {
        guard let command=args.first else { throw usage("config get|set required") }
        if command=="get" { return .success(configJSON()) }
        guard command=="set" else { throw usage("config get|set required") }
        let options=try TimerOptions(Array(args.dropFirst())); var any=false
        if let raw=options.value("--enabled") {
            let enabled=try bool(raw)
            do { try setEnabled(enabled) } catch CardRegistryError.atLeastOneCardRequired { throw PeekerError(code:"card_enablement_conflict",message:"At least one card must remain enabled") }
            enabledState.enabled=enabled; any=true
        }
        if let raw=options.value("--refresh-time") { await store.updateRefreshTime(try refresh(raw)); any=true }
        guard any else { throw usage("config set requires a value") }
        return .success(configJSON())
    }

    private func listJSON()->JSONValue {
        guard let state=store.dayState else { return .object(["tasks":.array([])]) }
        return .object([
            "businessDay":.object(["start":.string(iso(state.businessDay.start)),"end":.string(iso(state.businessDay.end))]),
            "activeTemplateId":state.activeSession.flatMap { session in state.tasks.first(where:{$0.id==session.taskID})?.templateID }.map{.string($0.uuidString)} ?? .null,
            "activeSession":state.activeSession.map { session in .object(["sessionId":.string(session.id.uuidString),"instanceId":.string(session.taskID.uuidString),"startedAt":.string(iso(Date(millisecondsSince1970:session.startedAtMilliseconds)))]) } ?? .null,
            "tasks":.array(state.tasks.filter(\.isVisible).sorted{$0.position<$1.position}.map(taskJSON))
        ])
    }

    private func taskJSON(_ task:TimerTaskInstance)->JSONValue { .object(taskObject(task)) }
    private func taskObject(_ task:TimerTaskInstance)->[String:JSONValue] {
        let accumulated=min(task.targetSeconds,task.targetSeconds-store.remainingSeconds(for:task,at:Date()))
        return ["templateId":.string(task.templateID.uuidString),"instanceId":.string(task.id.uuidString),"name":.string(task.name),
                "targetSeconds":.number(Double(task.targetSeconds)),"accumulatedSeconds":.number(Double(accumulated)),
                "remainingSeconds":.number(Double(max(0,task.targetSeconds-accumulated))),"status":.string(task.status.rawValue),
                "color":.string(task.colorHex),"position":.number(Double(task.position))]
    }
    private func configJSON()->JSONValue { .object(["enabled":.bool(enabledState.enabled),"refreshTime":.string(String(format:"%02d:%02d",store.refreshTime.hour,store.refreshTime.minute))]) }

    private func template(for selector:Selector)throws->TimerTemplate {
        switch selector.kind {
        case let .id(id): guard let value=store.templates.first(where:{$0.id==id}) else{throw notFound()};return value
        case let .name(name): let matches=store.templates.filter{$0.name==name}; guard matches.count==1 else { if matches.isEmpty{throw notFound()}; throw PeekerError(code:"ambiguous_selector",message:"Name is ambiguous",details:["candidateIds":.array(matches.map{.string($0.id.uuidString)})])}; return matches[0]
        }
    }
    private func task(for selector:Selector)throws->TimerTaskInstance { try task(templateID: template(for:selector).id) }
    private func task(templateID:UUID)throws->TimerTaskInstance { guard let task=store.dayState?.tasks.first(where:{$0.templateID==templateID && $0.isVisible}) else{throw notFound()};return task }
    private func parseDuration(_ raw:String)throws->Int64 { let regex=try NSRegularExpression(pattern:"^(?:(\\d+)h)?(?:(\\d+)m)?(?:(\\d+)s)?$"); let range=NSRange(raw.startIndex...,in:raw); guard let match=regex.firstMatch(in:raw,range:range),match.range==range else{throw PeekerError(code:"timer_invalid_duration",message:"Invalid duration")}; func n(_ i:Int)->Int64{let r=match.range(at:i);guard r.location != NSNotFound,let sr=Range(r,in:raw)else{return 0};return Int64(raw[sr]) ?? 0}; let value=n(1)*3600+n(2)*60+n(3);guard (1...86_399).contains(value)else{throw PeekerError(code:"timer_invalid_duration",message:"Duration out of range")};return value }
    private func color(_ raw:String)throws->String { guard raw.range(of:"^#[0-9A-Fa-f]{6}$",options:.regularExpression) != nil else{throw PeekerError(code:"timer_invalid_color",message:"Invalid color")};return raw.uppercased() }
    private func refresh(_ raw:String)throws->RefreshTime { let parts=raw.split(separator:":").compactMap{Int($0)};guard parts.count==2 else{throw usage("Invalid refresh time")};return try RefreshTime(hour:parts[0],minute:parts[1]) }
    private func bool(_ raw:String)throws->Bool{if raw=="true"{return true};if raw=="false"{return false};throw usage("Expected true or false")}
    private func iso(_ date:Date)->String{ISO8601DateFormatter().string(from:date)}
    private func map(_ error:TimerDomainError)->PeekerError{switch error{case .blankName:return PeekerError(code:"validation_error",message:"Name is required");case .targetOutOfRange:return PeekerError(code:"timer_invalid_duration",message:"Invalid duration");case .taskNotFound:return notFound();case .anotherTaskIsRunning:return PeekerError(code:"timer_already_running",message:"Another task is running");case .taskCompleted:return PeekerError(code:"timer_task_completed",message:"Task is completed");case .noActiveSession:return PeekerError(code:"timer_no_active_task",message:"No active task")}}
    private func usage(_ message:String)->PeekerError{PeekerError(code:"invalid_usage",message:message)}
    private func notFound()->PeekerError{PeekerError(code:"not_found",message:"Timer task not found")}
    private func persistence()->PeekerError{PeekerError(code:"persistence_error",message:store.errorMessage ?? "Timer mutation failed")}
}

private struct Selector {
    enum Kind { case id(UUID), name(String) }
    let kind:Kind; let remaining:[String]
    init(_ args:[String])throws{
        if let index=args.firstIndex(of:"--id") { guard index+1<args.count,let id=UUID(uuidString:args[index+1])else{throw PeekerError(code:"invalid_usage",message:"Invalid --id")}; var copy=args;copy.removeSubrange(index...index+1);kind = .id(id);remaining=copy;return }
        guard let index=args.firstIndex(where:{!$0.hasPrefix("--")}) else{throw PeekerError(code:"invalid_usage",message:"Selector required")}
        kind = .name(args[index].trimmingCharacters(in:.whitespacesAndNewlines)); var copy=args;copy.remove(at:index);remaining=copy
    }
}

private struct TimerOptions {
    private var values:[String:String]=[:]
    init(_ args:[String])throws{var i=0;while i<args.count{let key=args[i];guard key.hasPrefix("--"),i+1<args.count,!args[i+1].hasPrefix("--")else{throw PeekerError(code:"invalid_usage",message:"Invalid option")};values[key]=args[i+1];i+=2}}
    func value(_ key:String)->String?{values[key]}
    func required(_ key:String)throws->String{guard let value=values[key]else{throw PeekerError(code:"invalid_usage",message:"Missing \(key)")};return value}
}
