# Local LLM offload (Ollama)

Auto-detected hook layer that pushes low-stakes work to a local model when one is reachable. When Ollama is offline or disabled, every hook becomes a silent no-op and Claude works as before.

## What gets offloaded

| Hook | Trigger | What the local LLM does |
|------|---------|------------------------|
| `local-llm-classify-hook.sh` | `UserPromptSubmit` | Tags the prompt as TRIVIAL / MEDIUM / COMPLEX. Inject as routing hint so Claude can skip heavy skills (Allium, TLA+) on quick questions. |
| `local-llm-bash-tldr-hook.sh` | `PostToolUse` on `Bash`, output > 4000 chars | Three-line TLDR (WHAT / KEY / VERDICT) appended as additional context. |
| `local-llm-commit-draft-hook.sh` | `PostToolUse` on `Bash` matching `git add` | Generates a Conventional Commit draft from staged diff. Saved to `.claude/.local-llm-commit-draft.md`. |
| `local-llm-humanize-hook.sh` | `PostToolUse` on `Edit`/`Write` for `*.md`, `README*`, `CHANGELOG*`, `CONTRIBUTING*` | Scans for AI-tells (em-dash overuse, inflated vocab, rule of three, hollow openers). Reports issues; does not modify the file. |

The humanize hook excludes Claude-internal markdown (`CLAUDE.md`, `.claude/skills/`, `.claude/agents/`, `.claude/rules/`, `.claude/docs/`, `.specify/`) so it only fires on human-facing copy.

## Detection

`scripts/local-llm-detect.sh` is sourced by every hook script. It pings `${OLLAMA_HOST}/api/tags` with a 1-second timeout. On success it sets `LOCAL_LLM_AVAILABLE=1`; on failure it sets `0` and the hook exits without touching the network again.

Detection is cheap. The expensive call is the `/api/generate` request inside each hook, which uses `LOCAL_LLM_TIMEOUT` (default 15s).

## Configuration

All env vars are optional. Set them in your shell profile or a project-local `.env` you source manually.

| Variable | Default | Purpose |
|----------|---------|---------|
| `OLLAMA_HOST` | `http://localhost:11434` | Ollama base URL. |
| `LOCAL_LLM_MODEL` | `llama3` | Model tag for `ollama pull`. Untagged resolves to whatever `llama3:latest` points to on the host (8B by default). |
| `LOCAL_LLM_TIMEOUT` | `15` | Generation timeout in seconds. |
| `LOCAL_LLM_DETECT_TIMEOUT` | `1` | Reachability ping timeout. |
| `LOCAL_LLM_DISABLE` | unset | Set to `1` to force-disable every offload hook. |
| `LOCAL_LLM_CLASSIFY_TIMEOUT` | `4` | Tighter timeout for the `UserPromptSubmit` classifier so the prompt path stays snappy. |
| `LOCAL_LLM_TLDR_MIN_CHARS` | `4000` | Minimum Bash output size before the TLDR hook fires. |

## Setup

1. Install Ollama: `brew install ollama` (or your platform equivalent).
2. Pull the model: `ollama pull llama3` (or set `LOCAL_LLM_MODEL` to whatever you have, e.g. `qwen2.5:7b`).
3. Start the daemon: `ollama serve` (or just run it once; it stays warm in the background).
4. Verify: `curl -s http://localhost:11434/api/tags | jq '.models[].name'`.

That is the entire setup. Hooks pick up Ollama on the next prompt.

## Disabling

- Prefix a single command with `LOCAL_LLM_DISABLE=1` to skip the offload for that one invocation.
- Run `export LOCAL_LLM_DISABLE=1` to kill it for the whole shell session.
- Drop the four `local-llm-*-hook.sh` entries from `.claude/settings.json` to disable project-wide.

You can also stop Ollama (`pkill ollama` / quit the menubar app); detection fails silently and Claude reverts to its native behaviour.

## Cost model

The offload trades Anthropic tokens for local CPU/GPU time and a small amount of latency on every hook fire. The classifier adds ~1-3s to each user prompt; the TLDR fires only on big outputs; the commit-draft fires only on `git add`; the humanize hook fires only on documentation files.

If latency on the prompt path bothers you, set `LOCAL_LLM_CLASSIFY_TIMEOUT=2` or remove the classify hook entry from `settings.json`.

## Failure modes

Every hook is built to fail open: any error (offline, timeout, missing model, malformed JSON) results in an empty stdout and exit 0/1, which Claude Code treats as no additional context. The hooks never block tool execution and never produce errors that surface to the user.

If you want to confirm a hook is firing, run with `CLAUDE_LOG_HOOKS=1` (Claude Code's own debug flag) or invoke the script directly with synthetic input.
