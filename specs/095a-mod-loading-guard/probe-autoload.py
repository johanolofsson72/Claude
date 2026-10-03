#!/usr/bin/env python3
"""Spec 095a R8: where does an installed Claude Code load a mod from?

Run by hand after a Claude Code update, from a terminal (it drives an interactive session through a
pty, so it spends one short session per case). Not part of the suite. The developer runs it, with the
`!` prefix from inside a session: the agent's tools refuse to write the folders it builds, by design.

    python3 specs/095a-mod-loading-guard/probe-autoload.py [--wait SECONDS] [--claude PATH]

Each case builds a minimal mod whose session.start hook writes a marker file, starts `claude` in a
temporary project, answers the folder-trust question with Enter, waits, and exits. The marker says
whether the mod loaded. Everything goes to a temporary directory, except the user-skills case, which
writes ~/.claude/skills/probe-095a and removes it afterwards (also on Ctrl-C).

Compare the table it prints with the one in spec.md. A row that changed from "no" to "yes" is a load
location settings-edit-guard (scripts/settings_guard.py ModZones) must cover.
"""

import argparse
import os
import pty
import select
import shutil
import signal
import subprocess
import sys
import tempfile
import time

NAME = "probe-095a"
USER_SKILL = os.path.join(os.environ.get("CLAUDE_CONFIG_DIR") or os.path.expanduser("~/.claude"), "skills", NAME)


def module(marker):
    return (
        "import type { Register } from 'claude-code'\n\n"
        "export const register: Register = on => {\n"
        "  on('session.start', async ($, e, next) => {\n"
        f"    await $.fs.write({marker!r}, 'loaded')\n"
        "    return next(e)\n"
        "  })\n"
        "}\n"
    )


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(text)


def make_mod(folder, marker, manifest=True, module_path="./register.ts"):
    if manifest:
        write(os.path.join(folder, ".claude-plugin", "plugin.json"),
              '{ "name": "%s", "version": "0.1.0", "description": "095a load probe" }\n' % NAME)
    write(os.path.join(folder, "hooks", "hooks.json"), '{ "modules": ["%s"] }\n' % module_path)
    target = os.path.normpath(os.path.join(folder, "hooks", module_path))
    write(target, module(marker))


def run_session(claude, cwd, extra, wait):
    """Start an interactive claude in cwd, press Enter once (folder trust), wait, then stop it."""
    pid, fd = pty.fork()
    if pid == 0:
        os.chdir(cwd)
        os.execvp(claude, [claude] + extra)
    out = b""
    start = time.time()
    pressed = False
    try:
        while time.time() - start < wait:
            r, _, _ = select.select([fd], [], [], 0.5)
            if r:
                try:
                    out += os.read(fd, 65536)
                except OSError:
                    break
            if not pressed and time.time() - start > 4:
                os.write(fd, b"\r")
                pressed = True
    finally:
        try:
            os.kill(pid, signal.SIGTERM)
            time.sleep(1)
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        try:
            os.waitpid(pid, 0)
        except ChildProcessError:
            pass
    return out.decode("utf-8", "replace")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--wait", type=float, default=25.0, help="seconds per session (default 25)")
    ap.add_argument("--claude", default=shutil.which("claude") or "claude")
    a = ap.parse_args()
    if os.path.lexists(USER_SKILL):
        sys.exit(f"{USER_SKILL} exists already; remove it first")
    version = subprocess.run([a.claude, "--version"], capture_output=True, text=True).stdout.strip()
    root = tempfile.mkdtemp(prefix="probe-095a-")
    rows = []

    def case(label, setup, extra=()):
        proj = os.path.join(root, "proj-%d" % len(rows))
        os.makedirs(proj)
        marker = os.path.join(root, "marker-%d" % len(rows))
        cleanup = setup(proj, marker)
        try:
            log = run_session(a.claude, proj, list(extra), a.wait)
        finally:
            if cleanup:
                cleanup()
        loaded = os.path.exists(marker)
        note = "Path escapes plugin directory" if "Path escapes" in log else ""
        rows.append((label, "yes" if loaded else "no", note))
        print(f"  {label}: {'yes' if loaded else 'no'} {note}", flush=True)

    try:
        pd = os.path.join(root, "pd")
        case("--plugin-dir <folder>",
             lambda p, m: make_mod(pd, m), ["--plugin-dir", pd])
        pd2 = os.path.join(root, "pd2")
        case("--plugin-dir, no .claude-plugin/",
             lambda p, m: make_mod(pd2, m, manifest=False), ["--plugin-dir", pd2])

        def user_skill(p, m):
            make_mod(USER_SKILL, m)
            return lambda: shutil.rmtree(USER_SKILL, ignore_errors=True)
        case("~/.claude/skills/<name>/ with manifest and hooks/", user_skill)
        case("<project>/.claude/skills/<name>/, same files",
             lambda p, m: make_mod(os.path.join(p, ".claude", "skills", NAME), m))

        pd3 = os.path.join(root, "pd3")

        def escape_pd(p, m):
            make_mod(os.path.join(pd3, "inner"), m, module_path="../../outside.ts")
        case("hooks.json naming a module outside the folder (--plugin-dir)",
             escape_pd, ["--plugin-dir", os.path.join(pd3, "inner")])
    finally:
        shutil.rmtree(USER_SKILL, ignore_errors=True)
        shutil.rmtree(root, ignore_errors=True)

    print(f"\nClaude Code {version}\n")
    print("| Where the folder is | Loaded? |")
    print("|---|---|")
    for label, loaded, note in rows:
        print(f"| {label} | {loaded}{'; ' + note if note else ''} |")


if __name__ == "__main__":
    main()
