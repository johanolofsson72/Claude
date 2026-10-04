#!/usr/bin/env python3
"""hook_audit.py -- does every hook Claude Code loads for this project resolve? (spec 086, F001 F003)

    python3 scripts/hook_audit.py <project-root>      # via scripts/validate-hooks.sh

TWO BLIND SPOTS, ONE READER.

F001. superpowers' hooks.json carried a literal ${CLAUDE_PLUGIN_ROOT} where it was not expanded, and
the hook failed at every session start and every /clear, in every project, from February until
someone read the error. Nothing checked that a hook command resolves, because every gate here reads
the template's own scripts and none reads the configuration that runs them.

F003. test-hook-channels.sh finds the inert-deny defect (a hookSpecificOutput with no hookEventName,
which Claude Code drops) in scripts/*-hook.sh. rocky's two project-authored SC-id guards carried it
and were invisible: not CORE, not named *-hook.sh. A hand-written fleet sweep found them.

So this reads what Claude Code reads -- the project's .claude/settings.json and settings.local.json,
the user's ~/.claude/settings.json, and hooks/hooks.json of every enabled plugin -- and judges each
command hook WITHOUT RUNNING IT:

  * the program (first word of the first simple command) must exist: a path that is a file, or a
    name on PATH. Shell builtins and keywords are not judged.
  * an interpreter's script argument (bash x.sh, node x.mjs, python3 x.py, source x) must exist.
  * after expanding the variables Claude Code sets (CLAUDE_PROJECT_DIR; CLAUDE_PLUGIN_ROOT for a
    plugin's hooks) plus HOME and a leading ~ -- never inside single quotes -- no `$` may be left in
    either word. A word that keeps one is UNRESOLVED: that is the F001 shape.

A project-registered hook whose script lives in the project and is not CORE also gets the two
output-channel checks of test-hook-channels.sh: a top-level additionalContext, and a
hookSpecificOutput emitted with no hookEventName anywhere in the file. CORE hooks are covered by that
test already; user and plugin hooks are not this project's to fix, so they are judged on resolution only.

Output: one line per finding, then a summary line. Exit 0 clean, 1 findings, 2 cannot run.
Env: HOOK_AUDIT_HOME (default $HOME; the self-test points it at a fixture), HOOK_AUDIT_CORE (CORE
basenames, one per line; unset means "unknown", and every project hook script is channel-checked).
"""

import json
import os
import re
import shutil
import sys

INTERPRETERS = {"bash", "sh", "zsh", "dash", "ksh", "node", "deno", "bun", "python", "python3",
                "ruby", "perl", "pwsh", "source", "."}
BUILTINS = {"echo", "printf", "true", "false", "exit", "cd", "export", "test", "[", "[[", ":",
            "if", "then", "else", "fi", "for", "while", "until", "do", "done", "case", "esac",
            "read", "set", "unset", "local", "return", "exec", "eval", "trap", "command", "{", "}",
            "!", "time"}
OPERATORS = set(";&|()\n")
VAR = re.compile(r"\$\{([A-Za-z_][A-Za-z0-9_]*)\}|\$([A-Za-z_][A-Za-z0-9_]*)")
ASSIGN = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")


def load_json(path):
    """(data, error). A file that does not exist is (None, None); one that does not parse is an error."""
    if not os.path.isfile(path):
        return None, None
    try:
        with open(path, encoding="utf-8-sig") as f:
            return json.load(f), None
    except (OSError, ValueError) as e:
        return None, "%s: %s" % (path, str(e).splitlines()[0][:120])


def words(cmd):
    """The words of the first simple command, each as [(text, single_quoted), ...] parts.

    A small shell lexer: whitespace splits, quotes group, an unquoted operator ends the command.
    It reads; it never evaluates. Command substitution is kept as text and the word is not judged.
    """
    out, cur, i, n = [], [], 0, len(cmd)
    has = False

    def flush():
        nonlocal cur, has
        if has:
            out.append(cur)
        cur, has = [], False

    while i < n:
        c = cmd[i]
        if c in " \t":
            flush()
            i += 1
        elif c in OPERATORS:
            break
        elif c == "'":
            j = cmd.find("'", i + 1)
            j = n if j == -1 else j
            cur.append((cmd[i + 1:j], True))
            has = True
            i = j + 1
        elif c == '"':
            j, buf = i + 1, []
            while j < n and cmd[j] != '"':
                if cmd[j] == "\\" and j + 1 < n:
                    buf.append(cmd[j + 1])
                    j += 2
                else:
                    buf.append(cmd[j])
                    j += 1
            cur.append(("".join(buf), False))
            has = True
            i = j + 1
        elif c == "\\" and i + 1 < n:
            cur.append((cmd[i + 1], True))
            has = True
            i += 2
        else:
            j = i
            while j < n and cmd[j] not in " \t'\"\\" and cmd[j] not in OPERATORS:
                if cmd.startswith("$(", j):  # a substitution is one piece of the word, parens and all
                    depth, j = 1, j + 2
                    while j < n and depth:
                        depth += {"(": 1, ")": -1}.get(cmd[j], 0)
                        j += 1
                    continue
                j += 1
            cur.append((cmd[i:j], False))
            has = True
            i = j
    flush()
    return out


def expand(parts, env, home, first):
    """(text, unresolved). Variables expand outside single quotes; an unknown one stays as written."""
    text, left = [], False
    for k, (t, sq) in enumerate(parts):
        if sq:
            text.append(t)
            left = left or "$" in t
            continue
        if first and k == 0 and (t == "~" or t.startswith("~/")):
            t = home + t[1:]

        def sub(m):
            name = m.group(1) or m.group(2)
            return env[name] if name in env else m.group(0)

        t = VAR.sub(sub, t)
        left = left or "$" in t
        text.append(t)
    return "".join(text), left


def judge(cmd, args, env, home, root):
    """[(problem, word)] for one hook command, and the script path it runs (or None)."""
    ws = words(cmd)
    while ws and ASSIGN.match("".join(t for t, _ in ws[0])):
        ws = ws[1:]  # VAR=value prefixes
    exp = [expand(w, env, home, True) for w in ws]
    for a in args or []:
        t, left = expand([(str(a), False)], env, home, True)
        exp.append((t, left))
    if not exp:
        return [], None
    prog, prog_left = exp[0]
    if "$(" in prog or "`" in prog:
        return [], None
    problems, script = [], None
    if prog_left:
        return [("unexpanded variable in the program", prog)], None
    base = os.path.basename(prog)
    if prog in BUILTINS:
        return [], None
    if "/" in prog:
        p = prog if os.path.isabs(prog) else os.path.join(root, prog)
        if not os.path.isfile(p):
            problems.append(("program not found", prog))
    elif shutil.which(prog) is None:
        problems.append(("program not on PATH", prog))
    if base in INTERPRETERS:
        rest = exp[1:]
        while rest and rest[0][0].startswith("-"):
            if rest[0][0] in ("-c", "-e", "--eval", "-m"):
                return problems, None  # an inline program or a module, not a file
            rest = rest[1:]
        if rest:
            s, s_left = rest[0]
            if "$(" in s or "`" in s:
                pass  # computed at run time; not judged
            elif s_left:
                problems.append(("unexpanded variable in the script path", s))
            else:
                sp = s if os.path.isabs(s) else os.path.join(root, s)
                if not os.path.isfile(sp):
                    problems.append(("script not found", s))
                else:
                    script = sp
    elif "/" in prog and not problems:
        script = prog if os.path.isabs(prog) else os.path.join(root, prog)
    return problems, script


TOP_LEVEL = re.compile(r"""'\{additionalContext:|"additionalContext":""")


def channel_defects(path):
    """The two test-hook-channels.sh checks, on one file."""
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            text = f.read(1024 * 1024)
    except OSError:
        return []
    found = []
    if TOP_LEVEL.search(text) and "hookSpecificOutput" not in text:
        found.append("emits a top-level additionalContext, which Claude Code ignores")
    emits = [ln for ln in text.splitlines() if "hookSpecificOutput" in ln and "jq -r" not in ln]
    if emits and "hookEventName" not in text:
        found.append("emits hookSpecificOutput with no hookEventName, which Claude Code drops (an inert deny)")
    return found


def hooks_of(settings):
    """(event, matcher, hook) for every hook entry in a settings or hooks.json document."""
    if not isinstance(settings, dict):
        return
    for event, groups in (settings.get("hooks") or {}).items():
        if not isinstance(groups, list):
            continue
        for g in groups:
            if not isinstance(g, dict):
                continue
            for h in g.get("hooks") or []:
                if isinstance(h, dict):
                    yield event, g.get("matcher", ""), h


# Spec 098 R8 (F159): spec 095 R4 added |mcp__.* to the PreToolUse matchers of the two guards that keep
# MCP writes off the settings files and the trust stores. A project that never synced keeps the old
# matcher, and MCP writes skip both guards with no signal. A matcher counts as covering MCP only when it
# is "*", empty, or matches both probe names as an anchored regular expression (threat model #14: the
# stricter reading, so a pass here is a pass under any reading). One covering group per guard is enough.
MCP_GUARDS = ("settings-edit-guard-hook.sh", "trust-anchor-guard-hook.sh")
MCP_PROBES = ("mcp__x__write_file", "mcp__y__edit")


def matcher_covers_mcp(matcher):
    """(covers, why-not)."""
    if not isinstance(matcher, str):
        return False, "the matcher is not a string"
    if matcher in ("", "*"):
        return True, ""
    try:
        rx = re.compile(matcher)
    except re.error as e:
        return False, "the matcher does not compile (%s)" % e
    missed = [p for p in MCP_PROBES if not rx.fullmatch(p)]
    return (not missed), ("it does not match %s" % ", ".join(missed) if missed else "")


def mcp_matcher_findings(docs):
    seen = {}
    for label, _, d in docs:
        if not label.startswith("project"):
            continue
        for event, matcher, h in hooks_of(d):
            cmd = h.get("command") if isinstance(h.get("command"), str) else ""
            for guard in MCP_GUARDS:
                if event == "PreToolUse" and guard in cmd:
                    seen.setdefault(guard, []).append((label, matcher) + matcher_covers_mcp(matcher))
    out = []
    for guard, rows in sorted(seen.items()):
        if any(covers for _, _, covers, _ in rows):
            continue
        for label, matcher, _, why in rows:
            out.append("MATCHER %s PreToolUse[%s]: %s does not run for MCP tools: %s. Add |mcp__.* to "
                       "that matcher (the developer edits it, or the next template sync carries it)."
                       % (label, matcher, guard, why))
    return out


def inside(path, root):
    try:
        rp, rr = os.path.realpath(path), os.path.realpath(root)
    except OSError:
        return False
    return rp == rr or rp.startswith(rr.rstrip(os.sep) + os.sep)


def main(argv):
    if len(argv) != 2 or not os.path.isdir(argv[1]):
        sys.stderr.write("usage: hook_audit.py <project-root>\n")
        return 2
    root = os.path.abspath(argv[1])
    home = os.environ.get("HOOK_AUDIT_HOME") or os.path.expanduser("~")
    core_env = os.environ.get("HOOK_AUDIT_CORE")
    core = None if core_env is None else {ln.strip() for ln in core_env.splitlines() if ln.strip()}

    findings, unreadable = [], []
    sources = [("project", os.path.join(root, ".claude", "settings.json")),
               ("project-local", os.path.join(root, ".claude", "settings.local.json")),
               ("user", os.path.join(home, ".claude", "settings.json"))]
    docs = []
    for label, path in sources:
        d, err = load_json(path)
        if err:
            unreadable.append(err)
        if d is not None:
            docs.append((label, path, d))

    # Plugins: enabled in any settings file (later ones win), installed per installed_plugins.json.
    enabled = {}
    for label in ("user", "project", "project-local"):
        for lab, _, d in docs:
            if lab == label and isinstance(d, dict) and isinstance(d.get("enabledPlugins"), dict):
                enabled.update(d["enabledPlugins"])
    plugin_docs = []
    if any(v is True for v in enabled.values()):
        ip, err = load_json(os.path.join(home, ".claude", "plugins", "installed_plugins.json"))
        if err:
            unreadable.append(err)
        installs = (ip or {}).get("plugins") or {} if isinstance(ip, dict) else {}
        for key, on in sorted(enabled.items()):
            if on is not True:
                continue
            for e in installs.get(key) or []:
                if not isinstance(e, dict) or not e.get("installPath"):
                    continue
                if e.get("scope") == "project" and os.path.realpath(e.get("projectPath") or "") != os.path.realpath(root):
                    continue
                hp = os.path.join(e["installPath"], "hooks", "hooks.json")
                d, err = load_json(hp)
                if err:
                    unreadable.append(err)
                if d is not None:
                    plugin_docs.append(("plugin " + key, hp, d, e["installPath"]))
                break

    total = 0
    base_env = {"CLAUDE_PROJECT_DIR": root, "HOME": home}
    for label, path, d, plugin_root in [(a, b, c, None) for a, b, c in docs] + plugin_docs:
        env = dict(base_env)
        if plugin_root:
            env["CLAUDE_PLUGIN_ROOT"] = plugin_root
        for event, matcher, h in hooks_of(d):
            if h.get("type", "command") != "command" or not isinstance(h.get("command"), str):
                continue
            total += 1
            cmd = h["command"]
            where = "%s %s%s" % (label, event, "[%s]" % matcher if matcher else "")
            problems, script = judge(cmd, h.get("args"), env, home, root)
            shown = re.sub(r"\s+", " ", cmd)[:120]
            for why, word in problems:
                findings.append("UNRESOLVED %s: %s '%s' — %s" % (where, why, word, shown))
            if label.startswith("project") and script and inside(script, root) \
                    and (core is None or os.path.basename(script) not in core):
                for why in channel_defects(script):
                    findings.append("CHANNEL %s: %s %s" % (where, os.path.relpath(script, root), why))

    findings.extend(mcp_matcher_findings(docs))
    for err in unreadable:
        findings.append("UNREADABLE %s" % err)
    for f in findings:
        print(f)
    print("hooks: %d command hook(s) from %d file(s), %d finding(s)%s" % (
        total, len(docs) + len(plugin_docs), len(findings),
        "" if core is not None else " (CORE list unknown: every project hook script was channel-checked)"))
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
