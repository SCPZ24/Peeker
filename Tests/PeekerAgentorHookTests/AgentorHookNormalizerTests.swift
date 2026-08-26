import AgentorProtocol
import XCTest
@testable import PeekerAgentorHook

final class AgentorHookNormalizerTests: XCTestCase {
    func testClaudeQuestionKeepsOriginalAnswerKeyAndOnlyBasename() throws {
        let payload: [String: Any] = [
            "session_id": "session",
            "hook_event_name": "PreToolUse",
            "tool_name": "AskUserQuestion",
            "tool_use_id": "tool",
            "cwd": "/private/work/project",
            "tool_input": [
                "questions": [[
                    "header": "Choice",
                    "question": "Choose exactly",
                    "multiSelect": true,
                    "options": [["label": "A", "description": "First"], ["label": "B", "description": "Second"]],
                ]],
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let normalized = try XCTUnwrap(AgentorHookNormalizer.question(agent: .claude, data: data))

        XCTAssertEqual(normalized.0.workingDirectoryName, "project")
        XCTAssertEqual(normalized.0.questions.first?.answerKey, "Choose exactly")
        XCTAssertEqual(normalized.0.questions.first?.kind, .multiple)
        XCTAssertFalse(String(data: try JSONEncoder.agentor.encode(AgentorRequest(question: normalized.0)), encoding: .utf8)!.contains("/private/work"))
    }

    func testClaudeQuestionWithPartialOptionsDegradesAsAWhole() throws {
        let payload: [String: Any] = [
            "session_id": "session", "hook_event_name": "PreToolUse",
            "tool_name": "AskUserQuestion", "tool_use_id": "tool",
            "tool_input": ["questions": [[
                "question": "Choose", "options": [["label": "Valid"], ["description": "Missing label"]],
            ]]],
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let normalized = try XCTUnwrap(AgentorHookNormalizer.question(agent: .claude, data: data))
        XCTAssertNotNil(normalized.0.validationFailure)
        XCTAssertTrue(normalized.0.questions[0].options.isEmpty)
    }

    func testClaudeOutputPreservesToolInputAndEncodesMultipleValues() throws {
        let request = AgentorQuestionRequest(
            requestID: "r", session: AgentorSessionKey(agent: .claude, sessionID: "s"),
            supportsWriteback: true,
            questions: [AgentorQuestion(id: "q", answerKey: "Question", body: "Question", kind: .multiple)]
        )
        let context = ClaudeQuestionContext(request: request, toolInput: ["questions": [], "other": "kept"])
        let data = try XCTUnwrap(AgentorHookNormalizer.claudeOutput(
            response: .answer([AgentorAnswer(questionID: "q", answerKey: "Question", values: ["A", "B"])]),
            context: context
        ))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let specific = try XCTUnwrap(object["hookSpecificOutput"] as? [String: Any])
        let input = try XCTUnwrap(specific["updatedInput"] as? [String: Any])
        XCTAssertEqual(input["other"] as? String, "kept")
        XCTAssertEqual((input["answers"] as? [String: String])?["Question"], "A, B")
    }

    func testCodexStateOnlyCarriesWhitelistedFields() throws {
        let payload: [String: Any] = [
            "session_id": "session", "turn_id": "turn", "hook_event_name": "PreToolUse",
            "tool_use_id": "call", "tool_input": ["command": "secret"],
            "transcript_path": "/Users/test/.codex/sessions/rollout.jsonl",
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let request = try XCTUnwrap(AgentorHookNormalizer.state(agent: .codex, data: data))
        let encoded = String(data: try JSONEncoder.agentor.encode(request), encoding: .utf8)!
        XCTAssertFalse(encoded.contains("secret"))
        XCTAssertEqual(request.event?.toolID, "call")
    }
}
