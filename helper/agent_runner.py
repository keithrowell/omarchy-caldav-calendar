"""Find and run the agent chosen with `omarchy default agent`.

Shared by the calendar's agent helpers. Each call runs the agent headless
with no tools and no access beyond the prompt, and returns the JSON object
that matches the given schema.
"""

import json
import os
import shutil
import subprocess
from pathlib import Path

AGENT_TIMEOUT = 120  # seconds; a cold start of a headless agent can take a while
SUPPORTED = ("claude", "codex")


def agent_name() -> str:
    try:
        result = subprocess.run(["omarchy-default-agent"], capture_output=True, text=True, timeout=10)
        return result.stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return ""


def unsupported_message(name: str) -> str:
    if name:
        return f"The calendar agent works with Claude or Codex, and your default agent is {name}."
    return "No default agent is set. Choose one with: omarchy default agent claude"


def find(command: str) -> str | None:
    found = shutil.which(command)
    if found:
        return found
    for folder in (Path.home() / ".local/share/mise/shims", Path.home() / ".local/bin"):
        candidate = folder / command
        if candidate.exists():
            return str(candidate)
    return None


def run_claude(system: str, schema: dict, prompt: str, workdir: str) -> dict:
    binary = find("claude")
    if not binary:
        raise RuntimeError("Claude Code isn't installed.")
    command = [
        binary, "-p", "--model", os.environ.get("CALENDAR_AGENT_MODEL", "sonnet"),
        "--tools", "", "--setting-sources", "", "--strict-mcp-config", "--no-session-persistence",
        "--system-prompt", system, "--output-format", "json", "--json-schema", json.dumps(schema), prompt,
    ]
    result = subprocess.run(command, capture_output=True, text=True, timeout=AGENT_TIMEOUT, cwd=workdir)
    try:
        payload = json.loads(result.stdout)
    except json.JSONDecodeError:
        raise RuntimeError((result.stderr or result.stdout or "Claude gave no answer.").strip()[:300])
    if payload.get("is_error"):
        raise RuntimeError(str(payload.get("result") or "Claude reported an error.")[:300])
    answer = payload.get("structured_output")
    if not isinstance(answer, dict):
        answer = json.loads(payload.get("result") or "{}")
    return answer


def run_codex(system: str, schema: dict, prompt: str, workdir: str) -> dict:
    binary = find("codex")
    if not binary:
        raise RuntimeError("Codex isn't installed.")
    schema_file = Path(workdir) / "schema.json"
    schema_file.write_text(json.dumps(schema))
    out_file = Path(workdir) / "answer.json"
    full = system + "\n\n" + prompt + "\nAnswer with JSON only, matching the output schema."
    command = [binary, "exec", "--skip-git-repo-check", "--sandbox", "read-only",
               "--output-schema", str(schema_file), "--output-last-message", str(out_file), "-"]
    result = subprocess.run(command, input=full, capture_output=True, text=True, timeout=AGENT_TIMEOUT, cwd=workdir)
    if not out_file.exists():
        raise RuntimeError((result.stderr or "Codex gave no answer.").strip()[-300:])
    return json.loads(out_file.read_text())


RUNNERS = {"claude": run_claude, "codex": run_codex}


def run(name: str, system: str, schema: dict, prompt: str, workdir: str) -> dict:
    runner = RUNNERS.get(name)
    if not runner:
        raise RuntimeError(unsupported_message(name))
    return runner(system, schema, prompt, workdir)
