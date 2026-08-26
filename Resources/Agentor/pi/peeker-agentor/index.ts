// peeker-agentor-managed resource-version=1
import { spawn } from "node:child_process"
import { existsSync } from "node:fs"
import { basename } from "node:path"

const HELPER = "__PEEKER_AGENTOR_HELPER__"
let turn = 0
let sequence = 0

function send(kind, value, operation = "state") {
  if (!existsSync(HELPER)) return
  try {
    const child = spawn(HELPER, ["pi", operation], { stdio: ["pipe", "ignore", "ignore"] })
    child.on("error", () => {})
    child.stdin.end(JSON.stringify({ schemaVersion: 1, kind, event: kind === "event" ? value : null, question: kind === "question" ? value : null }))
  } catch (_) {}
}

export default function (pi) {
  const metadata = (ctx) => ({
    session: { agent: "pi", sessionID: ctx.sessionManager.getSessionId() },
    turnID: turn ? String(turn) : null,
    title: ctx.sessionManager.getSessionName() || null,
    workingDirectoryName: basename(ctx.cwd),
    process: { pid: process.pid, scope: "session" },
  })
  const event = (ctx, name, suffix = "", extra = {}) => ({
    eventID: `pi:${ctx.sessionManager.getSessionId()}:${turn}:${name}:${suffix}:${++sequence}`,
    occurredAt: Date.now(), ...metadata(ctx), name, ...extra,
  })

  pi.on("before_agent_start", async (_input, ctx) => {
    turn += 1
    send("event", event(ctx, "turnStarted", "start"))
  })
  pi.on("agent_start", async (_input, ctx) => send("event", event(ctx, "thinking", "agent")))
  pi.on("tool_call", async (input, ctx) => {
    send("event", event(ctx, "toolStarted", input.toolCallId, { toolID: input.toolCallId }))
    const known = new Set(["plan_mode_question", "AskUserQuestion", "ask_user_question"])
    if (!known.has(input.toolName)) return
    const raw = input.input || {}
    let questions = Array.isArray(raw.questions) ? raw.questions : null
    if (!questions && typeof raw.question === "string") questions = [raw]
    if (!questions || questions.length < 1) return
    const normalized = questions.map((question, index) => {
      const body = question.question || question.prompt
      if (typeof body !== "string") return null
      const options = Array.isArray(question.options) ? question.options : []
      return {
        id: question.id || `question-${index}`,
        answerKey: question.id || body,
        title: question.header || null,
        body,
        kind: options.length ? (question.multiple || question.multiSelect ? "multiple" : "single") : "text",
        options: options.map((option, optionIndex) => {
          const label = typeof option === "string" ? option : option.label
          return { id: `${index}-${optionIndex}`, label, detail: typeof option === "string" ? null : option.description || null, wireValue: label }
        }),
        allowsOther: question.custom !== false && options.length > 0,
        isRequired: true,
      }
    }).filter(Boolean)
    if (normalized.length !== questions.length) return
    send("question", {
      requestID: input.toolCallId, occurredAt: Date.now(), ...metadata(ctx),
      supportsWriteback: false, questions: normalized,
    }, "question")
  })
  pi.on("tool_result", async (input, ctx) => {
    send("event", event(ctx, "toolFinished", input.toolCallId, { toolID: input.toolCallId }))
    if (["plan_mode_question", "AskUserQuestion", "ask_user_question"].includes(input.toolName)) {
      send("event", event(ctx, "questionResolved", input.toolCallId, { requestID: input.toolCallId }), "resolved")
    }
  })
  pi.on("agent_settled", async (_input, ctx) => send("event", event(ctx, "turnEnded", "settled", { outcome: "normal" })))
  pi.on("session_shutdown", async (_input, ctx) => send("event", event(ctx, "turnEnded", "shutdown", { outcome: "cancel" })))
}
