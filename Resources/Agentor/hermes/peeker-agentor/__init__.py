# peeker-agentor-managed resource-version=1
from __future__ import annotations

import json
import os
import subprocess
import time
from pathlib import Path
from typing import Any, Dict, Optional

HELPER = "__PEEKER_AGENTOR_HELPER__"
AGENT = "hermes"


def _session(kwargs: Dict[str, Any]) -> str:
    return str(kwargs.get("session_id") or kwargs.get("task_id") or "")


def _event(kwargs: Dict[str, Any], name: str, suffix: str = "", **extra: Any) -> Dict[str, Any]:
    session_id = _session(kwargs)
    task_id = str(kwargs.get("task_id") or "")
    return {
        "eventID": f"hermes:{session_id}:{task_id}:{name}:{suffix}",
        "occurredAt": int(time.time() * 1000),
        "session": {"agent": AGENT, "sessionID": session_id},
        "turnID": task_id or None,
        "parentSessionID": kwargs.get("parent_session_id"),
        "workingDirectoryName": Path.cwd().name,
        "process": {"pid": os.getpid(), "scope": "session"},
        "name": name,
        **extra,
    }


def _send(kind: str, value: Dict[str, Any], operation: str) -> None:
    if not os.path.isfile(HELPER) or not os.access(HELPER, os.X_OK):
        return
    envelope = {"schemaVersion": 1, "kind": kind, "event": value if kind == "event" else None, "question": value if kind == "question" else None}
    try:
        subprocess.Popen(
            [HELPER, AGENT, operation], stdin=subprocess.PIPE,
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            start_new_session=True,
        ).communicate(json.dumps(envelope).encode("utf-8"), timeout=2)
    except Exception:
        return


def _on_session_start(**kwargs: Any) -> None:
    if _session(kwargs):
        _send("event", _event(kwargs, "thinking", "session"), "state")


def _pre_llm_call(**kwargs: Any) -> None:
    if _session(kwargs):
        _send("event", _event(kwargs, "turnStarted", "llm"), "state")


def _pre_tool_call(tool_name: str = "", args: Optional[Dict[str, Any]] = None, tool_call_id: str = "", **kwargs: Any) -> None:
    if not _session(kwargs):
        return
    call_id = tool_call_id or str(kwargs.get("call_id") or tool_name)
    _send("event", _event(kwargs, "toolStarted", call_id, toolID=call_id), "state")
    if tool_name != "clarify" or not isinstance(args, dict):
        return
    question = args.get("question")
    choices = args.get("choices") or []
    if not isinstance(question, str) or not isinstance(choices, list) or len(choices) > 5:
        return
    request = {
        "requestID": call_id,
        "occurredAt": int(time.time() * 1000),
        "session": {"agent": AGENT, "sessionID": _session(kwargs)},
        "turnID": str(kwargs.get("task_id") or "") or None,
        "workingDirectoryName": Path.cwd().name,
        "process": {"pid": os.getpid(), "scope": "session"},
        "supportsWriteback": False,
        "questions": [{
            "id": "question-0", "answerKey": question, "body": question,
            "kind": "multiple" if bool(args.get("multi_select")) else ("single" if choices else "text"),
            "options": [{"id": f"option-{index}", "label": str(value), "wireValue": str(value)} for index, value in enumerate(choices)],
            "allowsOther": bool(choices), "isRequired": True,
        }],
    }
    _send("question", request, "question")


def _post_tool_call(tool_name: str = "", tool_call_id: str = "", **kwargs: Any) -> None:
    if not _session(kwargs):
        return
    call_id = tool_call_id or str(kwargs.get("call_id") or tool_name)
    _send("event", _event(kwargs, "toolFinished", call_id, toolID=call_id), "state")
    if tool_name == "clarify":
        _send("event", _event(kwargs, "questionResolved", call_id, requestID=call_id), "resolved")


def _on_session_end(completed: bool = True, interrupted: bool = False, **kwargs: Any) -> None:
    if _session(kwargs):
        outcome = "cancel" if interrupted else ("normal" if completed else "failure")
        _send("event", _event(kwargs, "turnEnded", "end", outcome=outcome), "state")


def _subagent_start(agent_id: str = "", **kwargs: Any) -> None:
    if _session(kwargs):
        _send("event", _event(kwargs, "subagentStarted", agent_id, subagentID=agent_id), "state")


def _subagent_stop(agent_id: str = "", **kwargs: Any) -> None:
    if _session(kwargs):
        _send("event", _event(kwargs, "subagentFinished", agent_id, subagentID=agent_id), "state")


def register(ctx: Any) -> None:
    ctx.register_hook("on_session_start", _on_session_start)
    ctx.register_hook("pre_llm_call", _pre_llm_call)
    ctx.register_hook("pre_tool_call", _pre_tool_call)
    ctx.register_hook("post_tool_call", _post_tool_call)
    ctx.register_hook("on_session_end", _on_session_end)
    ctx.register_hook("subagent_start", _subagent_start)
    ctx.register_hook("subagent_stop", _subagent_stop)
