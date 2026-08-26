import AgentorProtocol
import Darwin
import Foundation

struct ClaudeQuestionContext {
    let request: AgentorQuestionRequest
    let toolInput: [String: Any]
}

enum AgentorHookNormalizer {
    static func state(agent: AgentKind, data: Data) -> AgentorRequest? {
        if agent == .claude || agent == .codex {
            guard let object = jsonObject(data) else { return nil }
            return normalizeHook(agent: agent, object: object).map(AgentorRequest.init(event:))
        }
        guard let request = try? JSONDecoder.agentor.decode(AgentorRequest.self, from: data),
              request.kind == .event else { return nil }
        return request
    }

    static func question(agent: AgentKind, data: Data) -> (AgentorQuestionRequest, ClaudeQuestionContext?)? {
        if agent == .claude {
            guard let object = jsonObject(data), let context = claudeQuestion(object) else { return nil }
            return (context.request, context)
        }
        guard let request = try? JSONDecoder.agentor.decode(AgentorRequest.self, from: data),
              request.kind == .question, let question = request.question else { return nil }
        return (question, nil)
    }

    static func claudeOutput(response: AgentorResponse, context: ClaudeQuestionContext) -> Data? {
        guard response.kind == .answer else { return nil }
        var answers: [String: String] = [:]
        for answer in response.answers { answers[answer.answerKey] = answer.values.joined(separator: ", ") }
        var updatedInput = context.toolInput
        updatedInput["answers"] = answers
        let output: [String: Any] = [
            "hookSpecificOutput": [
                "hookEventName": "PreToolUse",
                "permissionDecision": "allow",
                "updatedInput": updatedInput,
            ],
        ]
        return try? JSONSerialization.data(withJSONObject: output)
    }

    private static func normalizeHook(agent: AgentKind, object: [String: Any]) -> AgentorEvent? {
        guard let sessionID = string(object, "session_id") ?? string(object, "sessionId"),
              let hook = string(object, "hook_event_name") ?? string(object, "hookEventName") else { return nil }
        let turnID = string(object, "turn_id") ?? string(object, "turnId")
        let toolID = string(object, "tool_use_id") ?? string(object, "toolUseId")
        let subagentID = string(object, "agent_id") ?? string(object, "agentId")
        let reason = string(object, "reason")
        let name: AgentorEventName
        var outcome: AgentorTurnOutcome?
        switch hook {
        case "UserPromptSubmit", "SessionStart": name = .turnStarted
        case "PreToolUse": name = .toolStarted
        case "PostToolUse": name = .toolFinished
        case "SubagentStart": name = .subagentStarted
        case "SubagentStop": name = .subagentFinished
        case "Stop": name = .turnEnded; outcome = .normal
        case "StopFailure": name = .turnEnded; outcome = .failure
        case "SessionEnd":
            name = .turnEnded
            outcome = reason == "interrupt" || reason == "interrupted" ? .cancel : .normal
        default: return nil
        }
        let eventID = string(object, "event_id")
            ?? [agent.rawValue, sessionID, turnID ?? "", hook, toolID ?? subagentID ?? ""].joined(separator: ":")
        let cwdName = string(object, "cwd").map { URL(fileURLWithPath: $0).lastPathComponent }
        return AgentorEvent(
            eventID: eventID, session: AgentorSessionKey(agent: agent, sessionID: sessionID),
            turnID: turnID, parentSessionID: string(object, "parent_session_id"),
            title: string(object, "title"), workingDirectoryName: cwdName,
            process: AgentorProcessIdentity(pid: getppid(), scope: .unknown),
            name: name, toolID: toolID, subagentID: subagentID, outcome: outcome,
            transcriptPath: agent == .codex ? string(object, "transcript_path") : nil
        )
    }

    private static func claudeQuestion(_ object: [String: Any]) -> ClaudeQuestionContext? {
        guard (string(object, "hook_event_name") ?? string(object, "hookEventName")) == "PreToolUse",
              (string(object, "tool_name") ?? string(object, "toolName")) == "AskUserQuestion",
              let sessionID = string(object, "session_id") ?? string(object, "sessionId"),
              let requestID = string(object, "tool_use_id") ?? string(object, "toolUseId"),
              let toolInput = object["tool_input"] as? [String: Any] ?? object["toolInput"] as? [String: Any],
              let rawQuestions = toolInput["questions"] as? [[String: Any]] else { return nil }
        let questions = rawQuestions.enumerated().map { index, raw -> AgentorQuestion in
            let body = raw["question"] as? String ?? ""
            let rawOptions = raw["options"] as? [[String: Any]] ?? []
            let parsedOptions = rawOptions.enumerated().compactMap { optionIndex, option -> AgentorQuestionOption? in
                guard let label = option["label"] as? String else { return nil }
                return AgentorQuestionOption(
                    id: "\(index)-\(optionIndex)", label: label,
                    detail: option["description"] as? String, wireValue: label
                )
            }
            let optionsAreComplete = parsedOptions.count == rawOptions.count
            let options = optionsAreComplete ? parsedOptions : []
            let multiple = raw["multiSelect"] as? Bool ?? false
            let kind: AgentorQuestionKind = rawOptions.isEmpty ? .text : (multiple ? .multiple : .single)
            return AgentorQuestion(
                id: "question-\(index)", answerKey: body, title: raw["header"] as? String,
                body: body, kind: kind, options: options,
                allowsOther: !rawOptions.isEmpty, isRequired: true
            )
        }
        let request = AgentorQuestionRequest(
            requestID: requestID,
            session: AgentorSessionKey(agent: .claude, sessionID: sessionID),
            turnID: string(object, "turn_id"), parentSessionID: string(object, "parent_session_id"),
            workingDirectoryName: string(object, "cwd").map { URL(fileURLWithPath: $0).lastPathComponent },
            process: AgentorProcessIdentity(pid: getppid(), scope: .unknown),
            supportsWriteback: true, questions: questions
        )
        return ClaudeQuestionContext(request: request, toolInput: toolInput)
    }

    private static func jsonObject(_ data: Data) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func string(_ object: [String: Any], _ key: String) -> String? {
        object[key] as? String
    }
}
