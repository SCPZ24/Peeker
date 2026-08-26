// peeker-agentor-managed resource-version=1
import { spawn } from "node:child_process"
import { existsSync } from "node:fs"
import { basename } from "node:path"

const HELPER = "__PEEKER_AGENTOR_HELPER__"
let sequence = 0
const sessions = new Map()
const statuses = new Map()
const now = () => Date.now()
const eventID = (sessionID, name, suffix = "") => `opencode:${process.pid}:${sessionID}:${name}:${suffix}:${++sequence}`
const processInfo = { pid: process.pid, scope: "shared" }

function envelope(kind, value) {
  return { schemaVersion: 1, kind, event: kind === "event" ? value : null, question: kind === "question" ? value : null }
}

function sessionKey(sessionID) { return { agent: "opencode", sessionID } }
function metadata(sessionID) {
  const info = sessions.get(sessionID) || {}
  return {
    session: sessionKey(sessionID),
    parentSessionID: info.parentID || null,
    title: info.title || null,
    workingDirectoryName: info.directory ? basename(info.directory) : null,
    process: processInfo,
  }
}

function sendState(event) {
  if (!existsSync(HELPER)) return
  try {
    const child = spawn(HELPER, ["opencode", "state"], { stdio: ["pipe", "ignore", "ignore"] })
    child.on("error", () => {})
    child.stdin.end(JSON.stringify(envelope("event", event)))
  } catch (_) {}
}

function ask(question) {
  if (!existsSync(HELPER)) return Promise.resolve(null)
  return new Promise((resolve) => {
    try {
      const child = spawn(HELPER, ["opencode", "question"], { stdio: ["pipe", "pipe", "ignore"] })
      const chunks = []
      let size = 0
      child.stdout.on("data", (chunk) => {
        size += chunk.length
        if (size <= 524288) chunks.push(chunk)
      })
      child.on("error", () => resolve(null))
      child.on("close", () => {
        if (size > 524288) return resolve(null)
        try { resolve(JSON.parse(Buffer.concat(chunks).toString("utf8"))) }
        catch (_) { resolve(null) }
      })
      child.stdin.end(JSON.stringify(envelope("question", question)))
    } catch (_) { resolve(null) }
  })
}

export const PeekerAgentor = async ({ client }) => ({
  event: async ({ event }) => {
    const properties = event.properties || {}
    if (event.type === "session.created" || event.type === "session.updated") {
      sessions.set(properties.sessionID, properties.info || {})
      return
    }
    if (event.type === "session.status") {
      const sessionID = properties.sessionID
      const previous = statuses.get(sessionID)
      const current = properties.status?.type
      statuses.set(sessionID, current)
      if (current === "busy" && previous !== "busy") {
        sendState({ eventID: eventID(sessionID, "start"), occurredAt: now(), ...metadata(sessionID), name: "turnStarted" })
      } else if (current === "retry") {
        sendState({ eventID: eventID(sessionID, "thinking"), occurredAt: now(), ...metadata(sessionID), name: "thinking" })
      } else if (current === "idle") {
        sendState({ eventID: eventID(sessionID, "end"), occurredAt: now(), ...metadata(sessionID), name: "turnEnded", outcome: "normal" })
      }
      return
    }
    if (event.type === "session.idle") {
      sendState({ eventID: eventID(properties.sessionID, "end"), occurredAt: now(), ...metadata(properties.sessionID), name: "turnEnded", outcome: "normal" })
      return
    }
    if (event.type === "session.error") {
      sendState({ eventID: eventID(properties.sessionID, "failure"), occurredAt: now(), ...metadata(properties.sessionID), name: "turnEnded", outcome: "failure" })
      return
    }
    if (event.type === "question.asked") {
      const request = properties
      const supportsWriteback = typeof client?.question?.reply === "function"
      const question = {
        requestID: request.id,
        occurredAt: now(),
        ...metadata(request.sessionID),
        supportsWriteback,
        questions: (request.questions || []).map((item, index) => ({
          id: `question-${index}`,
          answerKey: item.question,
          title: item.header || null,
          body: item.question,
          kind: item.options?.length ? (item.multiple ? "multiple" : "single") : "text",
          options: (item.options || []).map((option, optionIndex) => ({
            id: `${index}-${optionIndex}`,
            label: option.label,
            detail: option.description || null,
            wireValue: option.label,
          })),
          allowsOther: item.custom !== false,
          isRequired: true,
        })),
      }
      void ask(question).then(async (response) => {
        if (response?.kind !== "answer" || !supportsWriteback) return
        const answers = response.answers.map((answer) => answer.values)
        try {
          await client.question.reply({ requestID: request.id, answers })
          sendState({ eventID: eventID(request.sessionID, "writeback", request.id), occurredAt: now(), ...metadata(request.sessionID), name: "writebackSucceeded", requestID: request.id })
        } catch (_) {
          sendState({ eventID: eventID(request.sessionID, "writeback-failed", request.id), occurredAt: now(), ...metadata(request.sessionID), name: "writebackFailed", requestID: request.id })
        }
      }).catch(() => {})
      return
    }
    if (event.type === "question.replied" || event.type === "question.rejected") {
      sendState({ eventID: eventID(properties.sessionID, "resolved", properties.requestID), occurredAt: now(), ...metadata(properties.sessionID), name: "questionResolved", requestID: properties.requestID })
    }
  },
  "tool.execute.before": async (input) => {
    sendState({ eventID: eventID(input.sessionID, "tool-start", input.callID), occurredAt: now(), ...metadata(input.sessionID), name: "toolStarted", toolID: input.callID })
  },
  "tool.execute.after": async (input) => {
    sendState({ eventID: eventID(input.sessionID, "tool-finish", input.callID), occurredAt: now(), ...metadata(input.sessionID), name: "toolFinished", toolID: input.callID })
  },
})
