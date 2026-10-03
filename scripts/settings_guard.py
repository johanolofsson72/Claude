#!/usr/bin/env python3
"""The verdict behind scripts/settings-edit-guard-hook.sh (spec 089).

Reads a PreToolUse payload on stdin and prints one line: a verdict word, then tab-separated details.

    none
    settings-key <path> <key,key>     a write that changes a guarded key
    settings-invalid <path>           a write that leaves the file unparseable
    settings-unreadable <path>        the current file is not a JSON object
    settings-shell <path>             a call with no bytes to simulate (NotebookEdit, a glob, a
                                      delegated shell write from bash-write-guard, an MCP tool)
    settings-bash <path>              a shell command that writes, or might write, a guarded file
    settings-git <path> <cause>       a git verb that would rewrite a guarded key, or that git
                                      cannot answer for (spec 095 R1)
    unparseable                       the payload is not a JSON object

WHICH FILES (R1, developer O1). The three that this session and the next one load:
<project>/.claude/settings.json, <project>/.claude/settings.local.json and <config>/settings.json,
compared after realpath, NFC, and case folding where the file system folds case. A hard link to one
is the same file. Another project's settings are not this guard's.

WHICH KEYS (spec 095 R2, developer O1). Every key except SAFE_KEYS and, inside permissions,
SAFE_PERMISSION_KEYS, by deep equality with "absent" as a value. Until 095 it was hooks,
disableAllHooks and env only, and apiKeyHelper, statusLine or enabledPlugins passed (F115).

THE SHELL (R4). The command text is split into simple commands, and a simple command that names a
guarded file passes only when it reads (READ_COMMANDS by bare name or from a system bin directory,
print-only sed, `python3 -m json.tool <one file>`, GIT_READ). A redirection into a guarded file, or an
output option naming one, is a write whatever the command. A read is not trusted on a line that also
exports, assigns or declares a variable, defines a function or alias, or sources a file (095 R7).
Nothing is evaluated: a name assembled at runtime from parts that spell neither the file nor its
directory is the declared bound, the same as bash-write-guard's.

GIT (095 R1, O3). A git verb that writes the working tree is judged by the content it would leave,
read from git; see the "git tree writes" section. `git pull` from a configured remote is the bound.

MCP (095 R3). An mcp__ tool is judged by every string in its input; see the "MCP tools" section.

The command text is never printed.
"""

import fnmatch
import glob
import json
import os
import re
import shlex
import sys
import unicodedata

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from shell_glob import (ANSI_C, TooMany, ansi_c_text, brace_alts,   # one copy of bash's word rules (spec 090)
                        sed_args, sed_script_kind)

# Spec 095 R2 (developer O1): every key is guarded except these. A key Claude Code adds later runs a
# command or adds a tool surface as often as not (apiKeyHelper, statusLine, enabledPlugins), so it is
# guarded until someone puts it here.
# The threat model's TB2 (developer decision, 2026-10-03) took four keys back off: cleanupPeriodDays 0
# purges the transcripts the developer audits, attribution and includeCoAuthoredBy strip authorship,
# and outputStyle names a file the agent can write, so it is prompt text.
SAFE_KEYS = frozenset(("$schema", "language", "model"))
SAFE_PERMISSION_KEYS = frozenset(("allow", "ask", "additionalDirectories"))
SETTINGS_NAMES = ("settings.json", "settings.local.json")
FOLD = sys.platform in ("darwin", "win32", "cygwin")
GLOBCH = re.compile(r"[*?\[]")

READ_COMMANDS = frozenset(
    "cat head tail less more grep egrep fgrep rg jq wc diff cmp ls stat file shasum sha1sum "
    "sha256sum md5 md5sum test [ realpath readlink basename dirname echo printf".split())
GIT_READ = frozenset(
    "diff log show status blame add commit ls-files grep check-ignore rev-parse cat-file".split())
# A command that finds files by name below a directory: after it, a bare `settings.json` may be one.
TREE_COMMANDS = frozenset("find fd xargs rsync tar zip".split())
OUTPUT_OPTIONS = frozenset(("-o", "--output", "--output-file", "--output-directory"))
EXEC_COMMANDS = frozenset(
    "sh bash zsh dash ksh fish eval source . exec xargs env python python3 perl ruby node php awk "
    "osascript parallel".split())
SYSTEM_BIN = frozenset(("/bin", "/usr/bin", "/usr/local/bin", "/opt/homebrew/bin", "/usr/sbin", "/sbin"))
MISSING = object()


# ----------------------------------------------------------------------------- paths

def norm(p):
    p = unicodedata.normalize("NFC", os.path.realpath(p))
    return p.casefold() if FOLD else p   # casefold: APFS opens hook\u017f as hooks (095a TM-1)


def norm_pattern(p):
    p = unicodedata.normalize("NFC", os.path.normpath(p))
    return p.casefold() if FOLD else p   # casefold: APFS opens hook\u017f as hooks (095a TM-1)


def shell_glob_match(path, pat):
    """The shell's rule, not fnmatch's (spec 090 R8(c)): `*`, `?` and `[…]` stay inside one path
    component, and a component that starts with a dot is matched only by a pattern component that
    starts with a literal dot. fnmatch over the whole path let `<cwd>/*` match
    `<cwd>/.claude/settings.json`, so every `*` in an interpreter's heredoc (`a * b`, `*args`) read
    as a write to the settings file."""
    ps, qs = path.split("/"), pat.split("/")
    if len(ps) != len(qs):
        return False
    for p, q in zip(ps, qs):
        if p.startswith(".") and not q.startswith("."):
            return False
        if not fnmatch.fnmatchcase(p, q):
            return False
    return True


# ----------------------------------------------------------------------------- mod paths (spec 095a)
# A plugin folder whose hooks/hooks.json names a module is a mod. A loaded mod's tool.call hook can allow
# a call past every settings hook, and the module runs code of its own, so no agent tool may create or
# change one (R1, developer decision M1: anywhere on disk, not only where Claude Code loads from).
#
#   hard  any write is refused: a .claude-plugin component, a hooks/hooks.json, anything at or under a
#         folder that already holds either, anything under a load root, the user's skills root and its
#         children, and a hooks/ folder inside any skill
#   soft  a project's <dir>/.claude/skills or one of its skill folders: only verbs that place a folder
#         there (cp, mv, ln, rsync, tar, …) are refused, so SKILL.md work, find and rm stay open
ANCESTOR_CAP = 64
PLACING = frozenset("cp mv ln rsync tar unzip ditto install bsdtar gtar cpio".split())
PLUGIN_MARK = ".claude-plugin"


def plugin_dirs_value(env, settings_files):
    """Every folder CLAUDE_CODE_PLUGIN_DIRS names: the hook's environment, and the env block of each
    settings file (the user's is the one Claude Code reads; the project's two are read too, TM-16)."""
    vals = [env.get("CLAUDE_CODE_PLUGIN_DIRS") or ""]
    for f in settings_files:
        try:
            with open(f, "r", encoding="utf-8") as fh:
                d = json.load(fh)
            v = d.get("env", {}).get("CLAUDE_CODE_PLUGIN_DIRS") if isinstance(d, dict) else None
            if isinstance(v, str):
                vals.append(v)
        except Exception:
            pass
    out = []
    for v in vals:
        for part in v.split(os.pathsep):
            part = part.strip()
            if part:
                out.append(os.path.expanduser(part))
    return out


class ModZones:
    def __init__(self, env, conf, settings_files):
        home = os.path.join(os.path.expanduser("~"), ".claude")
        confs = {conf, home}
        roots = [os.path.join(c, n) for c in confs for n in ("plugins", "dev-mods")]
        roots += plugin_dirs_value(env, settings_files)
        self.roots = {f for r in roots for f in (norm(r), norm_pattern(r))}
        self.user_skills = {f for c in confs for f in (norm(os.path.join(c, "skills")),
                                                       norm_pattern(os.path.join(c, "skills")))}
        self._marked = {}

    def _has_mark(self, d):
        if d not in self._marked:
            self._marked[d] = (os.path.lexists(os.path.join(d, PLUGIN_MARK))
                               or os.path.lexists(os.path.join(d, "hooks", "hooks.json")))
        return self._marked[d]

    def in_plugin_folder(self, p):
        """True when p or one of its ancestors holds a plugin marker; past the cap, True (fails closed)."""
        d = p
        for _ in range(ANCESTOR_CAP):
            if self._has_mark(d):
                return True
            parent = os.path.dirname(d)
            if parent == d:
                return False
            d = parent
        return True

    def kind(self, p):
        """"hard", "soft" or None for an absolute path."""
        forms = (norm(p), norm_pattern(p))
        mark = PLUGIN_MARK.casefold() if FOLD else PLUGIN_MARK
        hooks = "hooks", "hooks.json"
        soft = False
        for f in forms:
            comps = f.split("/")
            if mark in comps or tuple(comps[-2:]) == hooks:
                return "hard"
            for r in self.roots:
                if f == r or f.startswith(r.rstrip("/") + "/"):
                    return "hard"
            for r in self.user_skills:
                if f == r or f.startswith(r + "/"):
                    rest = f[len(r):].strip("/").split("/") if f != r else []
                    if len(rest) <= 1 or rest[1] == "hooks":
                        return "hard"
            for i in range(len(comps) - 1):
                if comps[i] == ".claude" and comps[i + 1] in ("plugins", "dev-mods"):
                    return "hard"
                if comps[i] == ".claude" and comps[i + 1] == "skills":
                    rest = comps[i + 2:]
                    if len(rest) >= 2 and rest[1] == "hooks":
                        return "hard"
                    if len(rest) <= 1:
                        soft = True
        if self.in_plugin_folder(os.path.realpath(p)) or self.in_plugin_folder(os.path.normpath(p)):
            return "hard"
        return "soft" if soft else None


class Guarded:
    def __init__(self, env, cwd):
        self.cwd = cwd
        self.loose_glob = False
        self.depth = 0
        self.proj = env.get("CLAUDE_PROJECT_DIR") or cwd
        self.conf = env.get("CLAUDE_CONFIG_DIR") or os.path.join(os.path.expanduser("~"), ".claude")
        self.env = env
        self.files = [os.path.join(self.proj, ".claude", n) for n in SETTINGS_NAMES]
        self.files.append(os.path.join(self.conf, "settings.json"))
        self.dirs = [os.path.join(self.proj, ".claude"), self.conf]
        self.file_keys = {norm(f): f for f in self.files}
        self.dir_keys = {norm(d) for d in self.dirs}
        # Unresolved spellings too: a pattern is matched against both.
        self.file_forms = set(self.file_keys) | {norm_pattern(f) for f in self.files}
        self.dir_forms = set(self.dir_keys) | {norm_pattern(d) for d in self.dirs}
        self.mods = ModZones(env, self.conf, self.files)
        self.mod_hits = {}                            # path -> "hard" | "soft", for the verdict word

    def absolute(self, p):
        return p if os.path.isabs(p) else os.path.join(self.cwd, p)

    def file_of(self, p):
        """The guarded file p is, or None."""
        p = self.absolute(p)
        hit = self.file_keys.get(norm(p))
        if hit:
            return hit
        try:
            if os.path.isfile(p) and os.stat(p).st_nlink > 1:
                for f in self.files:
                    if os.path.exists(f) and os.path.samefile(p, f):
                        return f
        except OSError:
            pass
        return self.mod_of(p)

    def mod_of(self, p):
        """p (absolute) when it is a mod path (spec 095a R1), else None. The kind goes to mod_hits."""
        p = self.absolute(p)
        kind = self.mods.kind(p)
        if kind:
            self.mod_hits[p] = kind
            return p
        return None

    def is_dir(self, p):
        return norm(self.absolute(p)) in self.dir_keys

    def glob_hit(self, pattern):
        """A guarded file or directory a glob pattern can match, or None."""
        pat = norm_pattern(self.absolute(pattern))
        for form in self.file_forms | self.dir_forms:
            # `shopt -s dotglob` lets `*` match .claude, and `globstar` lets `**` cross `/`; a command
            # that names either is judged by the old whole-path match (adversarial review #8).
            if self.loose_glob:
                # globstar's `**/` also matches no directory at all: `.claude/**/settings.json`.
                if fnmatch.fnmatchcase(form, pat) or fnmatch.fnmatchcase(form, pat.replace("**/", "")):
                    return form
            elif shell_glob_match(form, pat):
                return form
        try:
            for m in glob.glob(self.absolute(pattern)):
                if self.file_of(m) or self.is_dir(m):
                    return m
        except Exception:
            pass
        # A pattern that matches nothing yet still spells where it would write (095a TM-12).
        return self.mod_of(pattern)


# ----------------------------------------------------------------------------- the Edit route

def parse_settings(text):
    """A dict, or None when the text is not a JSON object. Empty text is {}."""
    if text.strip() == "":
        return {}
    try:
        d = json.loads(text, parse_constant=_no_constant)
    except Exception:
        return None
    return d if isinstance(d, dict) else None


def _no_constant(name):
    # Python reads NaN and Infinity; JSON.parse does not, so Claude Code would drop the whole file
    # while this guard saw every key unchanged (adversarial pass, 2026-10-02).
    raise ValueError(name)


def _canon(v):
    return "\0absent" if v is MISSING else json.dumps(v, sort_keys=True)


def changed_keys(before, after):
    """The guarded keys whose value differs, sorted; `permissions.<key>` inside permissions.
    As JSON text, not Python ==: True == 1 would read env 1 -> true as unchanged (/security-review)."""
    out = []
    for k in sorted((set(before) | set(after)) - SAFE_KEYS):
        b, a = before.get(k, MISSING), after.get(k, MISSING)
        if k == "permissions" and isinstance(b if b is not MISSING else {}, dict) \
                and isinstance(a if a is not MISSING else {}, dict):
            b = {} if b is MISSING else b
            a = {} if a is MISSING else a
            out.extend("permissions." + s for s in sorted((set(b) | set(a)) - SAFE_PERMISSION_KEYS)
                       if _canon(b.get(s, MISSING)) != _canon(a.get(s, MISSING)))
        elif _canon(b) != _canon(a):
            out.append(k)
    return out


QUOTES = str.maketrans({"‘": "'", "’": "'", "“": '"', "”": '"'})


def loose(s):
    return s.translate(QUOTES).replace("\r\n", "\n")


class Unsimulable(Exception):
    pass


def apply_edit(text, old, new, replace_all):
    """What the Edit tool leaves behind. A failing edit leaves the text as it was."""
    if not isinstance(old, str) or not isinstance(new, str):
        raise Unsimulable
    if old == "":
        if text == "":
            return new
        raise Unsimulable
    n = text.count(old)
    if n == 0:
        # The tool retries with quotes and line endings normalised; that match cannot be replayed
        # here byte for byte, so it is not simulated.
        if loose(old) in loose(text):
            raise Unsimulable
        return None
    if n > 1 and not replace_all:
        return None
    return text.replace(old, new) if replace_all else text.replace(old, new, 1)


def edit_verdict(tool, ti, g):
    fp = ti.get("file_path") or ti.get("notebook_path")
    if not isinstance(fp, str) or not fp:
        return ["none"]
    if GLOBCH.search(fp):
        hit = g.glob_hit(fp)
        if hit in g.mod_hits:
            return ["mod-file", hit] if g.mod_hits[hit] == "hard" else ["none"]
        return ["settings-shell", hit] if hit else ["none"]
    path = g.file_of(fp)
    if not path:
        return ["none"]
    if path in g.mod_hits:                            # 095a R2: a module is code, nothing is compared
        return ["mod-file", path] if g.mod_hits[path] == "hard" else ["none"]
    if tool == "NotebookEdit" or "notebook_path" in ti:
        return ["settings-shell", path]
    if not any(k in ti for k in ("content", "old_string", "new_string", "edits")):
        return ["settings-shell", path]
    try:
        with open(g.absolute(fp), "r", encoding="utf-8", newline="") as fh:
            cur = fh.read()
    except FileNotFoundError:
        cur = ""
    except (OSError, UnicodeDecodeError):
        return ["settings-unreadable", path]
    before = parse_settings(cur)
    if before is None:
        return ["settings-unreadable", path]
    try:
        if isinstance(ti.get("content"), str):
            after_text = ti["content"]
        elif "edits" in ti:
            edits = ti["edits"]
            if not isinstance(edits, list):
                raise Unsimulable
            after_text = cur
            for e in edits:
                if not isinstance(e, dict):
                    raise Unsimulable
                r = apply_edit(after_text, e.get("old_string"), e.get("new_string"), bool(e.get("replace_all")))
                if r is None:              # one failing edit fails the whole MultiEdit
                    after_text = cur
                    break
                after_text = r
        elif "old_string" in ti:
            r = apply_edit(cur, ti.get("old_string"), ti.get("new_string"), bool(ti.get("replace_all")))
            after_text = cur if r is None else r
        else:
            raise Unsimulable
    except Unsimulable:
        return ["settings-shell", path]
    after = parse_settings(after_text)
    if after is None:
        return ["settings-invalid", path]
    keys = changed_keys(before, after)
    return ["settings-key", path, ",".join(keys)] if keys else ["none"]


# ----------------------------------------------------------------------------- the shell route

HEREDOC = re.compile(r"(?<!<)<<(?!<)(-?)[ \t]*([^\s;&|<>()]*)")
NAME_ASSIGN = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
PATHISH = re.compile(r"[^\s'\"`;&|<>()=,]+")
INTERESTING = re.compile(r"(?i)sett|\.cla|[*?\[$`{]")


def ansi_c(m):
    return shlex.quote(ansi_c_text(m.group(1)))


def attach_heredocs(text):
    """Each heredoc body's settings-shaped words, moved onto the line that opens it."""
    lines = text.split("\n")
    out = []
    i = 0
    while i < len(lines):
        line = lines[i]
        i += 1
        found = list(HEREDOC.finditer(line))
        if not found:
            out.append(line)
            continue
        extra = []
        for m in found:
            strip_tabs = m.group(1) == "-"
            delim = re.sub(r"[\"'\\]", "", m.group(2))
            body = []
            while i < len(lines):
                cand = lines[i].lstrip("\t") if strip_tabs else lines[i]
                i += 1
                if delim and cand == delim:      # no delimiter parsed: the rest of the text is the body
                    break
                body.append(lines[i - 1])
            words = [w for w in PATHISH.findall("\n".join(body)) if INTERESTING.search(w)]
            if re.search(r"\bgit\b", "\n".join(body)):
                words.append("\n".join(body))       # judged as a program of its own (095 adversarial #2)
            extra.append((m.end(), " ".join(shlex.quote(w) for w in words)))
        for pos, words in reversed(extra):
            line = line[:pos] + " " + words + " " + line[pos:]
        out.append(line)
    return "\n".join(out)


def brace_expand(word):
    """bash brace expansion, sequences included: `.cla{u..u}de` is .claude (/simplify, spec 090).
    Past the cap the word itself stands in, so a settings-shaped word is still judged."""
    try:
        return brace_alts(word)
    except TooMany:
        return [word, re.sub(r"\{[^{}]*\}", "*", word)]


def expand_vars(w, g):
    home = os.path.expanduser("~")
    if w == "~" or w.startswith("~/"):
        w = home + w[1:]
    subs = {"HOME": home, "PWD": g.cwd, "CLAUDE_PROJECT_DIR": g.proj, "CLAUDE_CONFIG_DIR": g.conf}
    for k, v in subs.items():
        w = w.replace("${%s}" % k, v)
        w = re.sub(r"\$%s(?![A-Za-z0-9_])" % k, lambda _m, v=v: v, w)
    return w


def word_hit(word, g, bases, by_name, dots):
    """The guarded file or directory a shell word names, or None.

    bases: the directories a relative word may be relative to (the payload cwd, every cd/-C target).
    by_name: a bare settings.json / settings.local.json counts (after a cd that cannot be resolved,
    or a command that finds files by name). dots: `.`, `..`, `./` count too (after a cd into a
    guarded directory, or one that cannot be resolved)."""
    cands = [word]
    if "=" in word:
        cands.append(word.split("=", 1)[1])
    if re.match(r"^-[A-Za-z]", word) and len(word) > 2:
        cands.append(word[2:])
    if re.search(r"[\s;&|()<>'\"]", word):          # a program inside a word: bash -c "…", python3 -c
        cands.extend(PATHISH.findall(word))
    for c in cands:
        for w in brace_expand(c):
            w = expand_vars(w, g)
            if not w:
                continue
            if "$" in w or "`" in w:
                head = w.rstrip("/").rpartition("/")[0]
                if head and "$" not in head and "`" not in head:
                    for b in bases:
                        if g.is_dir(os.path.join(b, head)):
                            return os.path.join(b, head)
                continue
            for b in bases:
                p = os.path.join(b, w)
                if GLOBCH.search(w):
                    hit = g.glob_hit(p)
                else:
                    hit = g.file_of(p) or (p if g.is_dir(p.rstrip("/") or "/") else None)
                if hit:
                    return hit
            if dots and re.fullmatch(r"[./]+", w):
                return w
            if by_name:
                b = w.rstrip("/").rpartition("/")[2].lower()
                for n in SETTINGS_NAMES:
                    if b == n or fnmatch.fnmatchcase(n, b):
                        return w
    return None


DIR_OPTIONS = ("-C", "--work-tree", "--directory", "--git-dir")


def dir_targets(cmds):
    """Every directory a command moves into or points a tool at: cd/pushd arguments, -C values."""
    out = []
    for words, _, _ in cmds:
        cw = command_word(words)
        base = cw.rpartition("/")[2] if cw else ""
        if base in ("cd", "pushd"):
            i = words.index(cw) + 1
            args = [w for w in words[i:] if not w.startswith("-")]
            out.append(args[0] if args else "~")
        for i, w in enumerate(words):
            if w in DIR_OPTIONS and i + 1 < len(words):
                out.append(words[i + 1])
            elif any(w.startswith(o + "=") for o in DIR_OPTIONS):
                out.append(w.split("=", 1)[1])
    return out


def command_word(words):
    for w in words:
        if NAME_ASSIGN.match(w):
            continue
        return w
    return None


def reads(words):
    rest = list(words)
    while rest and NAME_ASSIGN.match(rest[0]):
        rest.pop(0)
    if not rest:
        return False                                  # p=<settings>; … "$p": the name goes on (/security-review)
    if len(rest) != len(words):
        return False                                  # LESSOPEN=… less, GIT_EXTERNAL_DIFF=… git diff
    head, _, cmd = rest[0].rpartition("/")
    if head and head not in SYSTEM_BIN:
        return False                                  # ./cat, /tmp/x/jq: the agent's program under a read name
    if cmd == "rg" and any(w in ("--pre", "--hostname-bin") or w.startswith(("--pre=", "--hostname-bin=")) for w in rest):
        return False                                  # rg --pre runs a program on each file
    if cmd in READ_COMMANDS:
        return True
    if cmd == "sed":                                  # spec 095 R8: print-only and s/// to stdout read
        in_place, scripts, _ = sed_args(rest[1:])
        return not in_place and bool(scripts) and all(sed_script_kind(s) for s in scripts)
    if cmd in ("python3", "python") and rest[1:3] == ["-m", "json.tool"]:
        return len([w for w in rest[3:] if not w.startswith("-")]) == 1
    if cmd == "git":
        j = 1
        while j < len(rest):
            w = rest[j]
            if w in ("-c", "--config-env") or w.startswith("--config-env=") or w.startswith("--exec-path"):
                return False                          # git -c core.pager=…, diff.external=…
            if w in ("--git-dir", "--work-tree") or w.startswith(("--git-dir=", "--work-tree=")):
                return False                          # a config the agent wrote (095 adversarial #8)
            if w in ("-C", "--namespace"):
                j += 2
                continue
            if w.startswith("-"):
                j += 1
                continue
            # git grep -O runs a pager program on each match; --ext-diff and --textconv run the
            # configured diff programs (095 adversarial #8).
            if any(a.startswith(("-O", "--open-files-in-pager", "--ext-diff", "--textconv")) for a in rest[j + 1:]):
                return False
            return w in GIT_READ
        return True
    return False


def strip_comments(text):
    """The text with bash comments removed: a # at the start of a word, outside quotes, runs to the end
    of its line. The lexer has no comment rule, and without this `echo # '` on one line and `# '` two
    lines later made one quoted word of a real command between them (095 adversarial #5)."""
    out, i, quote, n = [], 0, None, len(text)
    while i < n:
        c = text[i]
        if quote:
            out.append(c)
            if c == "\\" and quote == '"' and i + 1 < n:
                out.append(text[i + 1])
                i += 2
                continue
            if c == quote:
                quote = None
        elif c == "\\" and i + 1 < n:
            out.append(c + text[i + 1])
            i += 2
            continue
        elif c in "'\"":
            quote = c
            out.append(c)
        elif c == "#" and (i == 0 or text[i - 1] in " \t\n;&|()<>"):
            j = text.find("\n", i)
            i = n if j < 0 else j
            continue
        else:
            out.append(c)
        i += 1
    return "".join(out)


def split_commands(text, strip=False):
    """[(words, redirect_targets)] per simple command, or None when the text cannot be split. strip:
    remove bash comments first (see bash_verdict for why both readings are judged)."""
    lex = shlex.shlex(strip_comments(text) if strip else text, posix=True, punctuation_chars="();<>|&\n")
    lex.whitespace = " \t\r"
    lex.commenters = ""
    lex.whitespace_split = True
    out = []
    words, targets = [], []
    pending_redirect = False
    depth = 0                                         # inside $( ), >( ), <( ): output flows on
    def flush():
        if words or targets:
            out.append((words, targets, depth > 0))
    try:
        for tok in lex:
            if tok and all(ch in "();<>|&\n" for ch in tok):
                if "(" in tok or ")" in tok:          # >(…) <(…) $(…) (…): a new command starts
                    subst = ("<" in tok or ">" in tok) or (words and words[-1].endswith("$"))
                    if words and words[-1].endswith("$"):
                        words[-1] = words[-1][:-1]
                        if not words[-1]:
                            words.pop()
                    flush()
                    words, targets = [], []
                    pending_redirect = False
                    depth = depth + tok.count("(") * (1 if subst else 0) - tok.count(")")
                    depth = max(depth, 0)
                    continue
                if "<<" in tok and ">" not in tok:
                    pending_redirect = False          # the delimiter follows; already handled
                    continue
                if ">" in tok or "<" in tok:
                    pending_redirect = ">" in tok
                    if words and words[-1].isdigit():     # 2>&1: the 2 is a descriptor, not a word
                        words.pop()
                    continue
                flush()
                words, targets = [], []
                pending_redirect = False
                continue
            if pending_redirect:
                targets.append(tok)
                pending_redirect = False
            else:
                words.append(tok)
    except ValueError:
        return None
    flush()
    return out


# Spec 095 R7 (F121): a read is trusted only in a command that does not first change what a read runs.
# An exported GIT_EXTERNAL_DIFF, PAGER or LESSOPEN, a function or alias named cat, a hashed path, or a
# sourced file turns `git diff <settings>` or `cat <settings>` into a program. A bare assignment counts
# too: assigning a variable that is already exported (PATH, the developer's GIT_PAGER) changes the
# child's environment without any export on the line.
PRELUDE_COMMANDS = frozenset("export declare typeset readonly local alias hash enable shopt source . function".split())
FUNC_DEF = re.compile(r"(?:^|[\s;&|(){}])(?:function\s+[^\s(){};&|]+|[A-Za-z_][\w.:+-]*\s*\(\s*\))")


def prelude_taints(cmds, text):
    # A definition is shell syntax, never quoted text: `grep 'ok()' f` defines nothing (found 095).
    if FUNC_DEF.search(re.sub(r"'[^']*'|\"(?:[^\"\\\\]|\\\\.)*\"", "''", text)):
        return True
    for words, _, _ in cmds:
        if not words:
            continue
        if all(NAME_ASSIGN.match(w) for w in words):
            return True
        cw = command_word(words) or ""
        base = cw.rpartition("/")[2]
        if base in PRELUDE_COMMANDS:
            return True
        if base == "set" and any(w == "allexport" or (w[:1] in "-+" and "a" in w[1:]) for w in words[1:]):
            return True
    return False


# Spec 095 R8 (F145): grep's and rg's pattern is not a file name, so `'[a-z]*'` does not "match"
# settings.json in the by-name check that a find or xargs elsewhere on the line turns on.
GREP_COMMANDS = frozenset("grep egrep fgrep rg".split())
GREP_VALUED = frozenset("-f -m -A -B -C -g -t -T -j -M --file --max-count --glob --type --type-not "
                        "--threads --max-columns --context --after-context --before-context".split())


def pattern_indices(words):
    cw = command_word(words)
    if not cw:
        return set()
    start = words.index(cw) + 1
    if cw.rpartition("/")[2] == "xargs":              # find … | xargs grep PATTERN
        while start < len(words) and words[start].startswith("-"):
            start += 2 if words[start] in ("-I", "-n", "-L", "-P", "-s", "-d", "-E", "-a") else 1
        if start >= len(words):
            return set()
        cw = words[start]
        start += 1
    if cw.rpartition("/")[2] not in GREP_COMMANDS:
        return set()
    pats, positional, with_e = set(), [], False
    i = start
    while i < len(words):
        w = words[i]
        if w == "--":
            positional.extend(range(i + 1, len(words)))
            break
        if w in ("-e", "--regexp"):
            with_e = True
            pats.add(i + 1)
            i += 2
            continue
        if w.startswith("--regexp=") or (w.startswith("-e") and len(w) > 2):
            with_e = True
            pats.add(i)
        elif w in GREP_VALUED:
            i += 2
            continue
        elif not w.startswith("-"):
            positional.append(i)
        i += 1
    if not with_e and positional:
        pats.add(positional[0])
    return pats


# ----------------------------------------------------------------------------- git tree writes (R1)
# Spec 095 R1 (F114, developer O3). `git checkout HEAD -- .`, `git restore --source=REV .`, `git stash
# pop` and `git apply` rewrite a settings file without naming it, so the name check never saw them. A
# git verb that writes the working tree is judged by what it would write: for each guarded file inside
# the repository and the verb's pathspec, the content it would leave is read from git (a revision, the
# index, a stash, nothing for a removal) and compared on the guarded keys. History verbs (merge, rebase,
# cherry-pick, revert, stash pop) compare the change they apply. A patch is read for the file names it
# touches. Any git call that fails or times out denies. `git pull` is allowed: what it brings is on
# origin, in the shared history (O3, recorded bound).

TREE_VERBS = frozenset("checkout switch restore reset stash clean apply merge rebase cherry-pick revert "
                       "read-tree checkout-index rm".split())
# Flags that make a verb write nothing. Per verb: `-n` is a dry run for clean and --no-commit for merge,
# cherry-pick and revert, and `--stat` is a report for apply and a merge option (095 adversarial #1).
CONTROL_FLAGS = frozenset("--abort --quit --continue --skip".split())
DRY_RUN_FLAGS = {"clean": frozenset(("-n", "--dry-run")),
                 "apply": frozenset(("--check", "--stat", "--numstat", "--summary")),
                 "rebase": frozenset(("--edit-todo",)),
                 "rm": frozenset(("-n", "--dry-run", "--cached"))}
GIT_GLOBAL_VALUED = frozenset(("-c", "--config-env", "--namespace", "--exec-path", "--attr-source",
                               "--super-prefix", "--list-cmds"))


class GitUnknown(Exception):
    """git could not answer, or the call cannot be modelled: the guard denies."""


class NoSuchRev(Exception):
    """A revision the verb names does not exist now; git refuses the verb."""


def _git_env():
    """Every GIT_ variable dropped (GIT_DIR, GIT_WORK_TREE, GIT_INDEX_FILE, GIT_CONFIG_*, GIT_EXTERNAL_DIFF,
    …), the same rule as acceptance_cases._git_env, with replace refs and grafts off."""
    env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
    env.update(GIT_NO_REPLACE_OBJECTS="1", GIT_GRAFT_FILE=os.devnull, GIT_OPTIONAL_LOCKS="0",
               GIT_TERMINAL_PROMPT="0", LC_ALL="C")
    return env


def _git_timeout():
    try:
        v = float(os.environ.get("SETTINGS_GUARD_GIT_TIMEOUT", "5"))
    except ValueError:
        return 5.0
    return v if v > 0 else 5.0


GIT_ENV = _git_env()
GIT_TIMEOUT = _git_timeout()


def run_git(where, *args):
    """(rc, stdout bytes). Timeouts and a missing git raise GitUnknown."""
    import subprocess
    try:
        p = subprocess.run(["git", "-c", "core.fsmonitor=false", "-C", where] + list(args),
                           stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, stdin=subprocess.DEVNULL,
                           timeout=GIT_TIMEOUT, env=GIT_ENV)
    except (OSError, subprocess.SubprocessError):
        raise GitUnknown("git did not answer in time")
    return p.returncode, p.stdout


class Repo:
    def __init__(self, where, g):
        rc, out = run_git(where, "rev-parse", "--show-toplevel")
        if rc != 0:
            self.top = None                           # not a repository: the verb writes nothing
            return
        self.where = where
        self.top = out.decode("utf-8", "replace").strip()
        top = norm(self.top)
        self.files = {}                               # rel path (as git spells it) -> absolute guarded file
        for f in g.files:
            nf = norm(f)
            if nf.startswith(top.rstrip("/") + "/"):
                rel = os.path.relpath(os.path.realpath(f), os.path.realpath(self.top)).replace(os.sep, "/")
                self.files[rel] = f
        self._revs = {}
        self._tracked = {}

    def rev(self, r):
        """The commit r names, or None when it names none. Any other failure raises."""
        if r not in self._revs:
            rc, out = run_git(self.top, "rev-parse", "--verify", "--quiet", "--end-of-options", r + "^{commit}")
            self._revs[r] = out.decode().strip() if rc == 0 and out.strip() else None
        return self._revs[r]

    def blob(self, spec):
        """Text at <rev>:<path> or :<path>, or MISSING when git has no such object."""
        rc, out = run_git(self.top, "cat-file", "-e", spec)
        if rc != 0:
            return MISSING
        rc, out = run_git(self.top, "cat-file", "blob", spec)
        if rc != 0:
            raise GitUnknown("git could not read " + spec)
        return out.decode("utf-8", "replace")

    def tracked(self, rel):
        if rel not in self._tracked:
            rc, _ = run_git(self.top, "ls-files", "--error-unmatch", "--", rel)
            self._tracked[rel] = rc == 0
        return self._tracked[rel]

    def ignored(self, rel):
        rc, _ = run_git(self.top, "check-ignore", "-q", "--no-index", "--", rel)
        return rc == 0

    def merge_base(self, a, b):
        rc, out = run_git(self.top, "merge-base", a, b)
        if rc != 0 or not out.strip():
            return None
        return out.decode().strip()

    def current(self, rel):
        try:
            with open(self.files[rel], "r", encoding="utf-8", newline="") as fh:
                return fh.read()
        except FileNotFoundError:
            return MISSING
        except (OSError, UnicodeDecodeError):
            raise GitUnknown("the current file cannot be read")


def in_scope(rel, specs, repo):
    """Does a pathspec list (empty = everything) cover rel?"""
    if not specs:
        return True
    for p in specs:
        if p.startswith(":") or GLOBCH.search(p):
            return True                               # magic or a glob: assume it reaches the file
        a = os.path.normpath(os.path.join(repo.where, p))
        try:
            r = os.path.relpath(os.path.realpath(a), os.path.realpath(repo.top)).replace(os.sep, "/")
        except ValueError:
            continue
        r, f = (r.lower(), rel.lower()) if FOLD else (r, rel)
        if r == "." or f == r or f.startswith(r.rstrip("/") + "/"):
            return True
    return False


def _parsed(text):
    return {} if text is MISSING else parse_settings(text)


CONFLICT = object()


def compare(before, after):
    """None when the guarded keys agree; else a short cause."""
    if after is CONFLICT:
        return "both sides change it, so git would leave conflict markers"
    b, a = _parsed(before), _parsed(after)
    if a is None:
        return "leaves invalid JSON"
    if b is None:
        b = {}
    keys = changed_keys(b, a)
    return ",".join(keys) if keys else None


def split_args(args):
    """(options, operands, after_dashdash) with operands in order; a valued option's value is kept with it."""
    opts, ops, tail = [], [], []
    i = 0
    while i < len(args):
        a = args[i]
        if a == "--":
            tail = args[i + 1:]
            break
        if a.startswith("-") and a != "-":
            opts.append(a)
        else:
            ops.append(a)
        i += 1
    return opts, ops, tail


def opt_value(args, *names):
    for i, a in enumerate(args):
        for n in names:
            if a == n and i + 1 < len(args):
                return args[i + 1]
            if n.startswith("--") and a.startswith(n + "="):
                return a.split("=", 1)[1]
            if not n.startswith("--") and a.startswith(n) and len(a) > len(n):
                return a[len(n):]
    return None


def without_values(args, valued):
    """args with each valued option's separate value removed."""
    out, i = [], 0
    while i < len(args):
        out.append(args[i])
        i += 2 if args[i] in valued else 1
    return out


def patch_names(path, where):
    try:
        with open(os.path.join(where, path), "r", encoding="utf-8", errors="replace") as fh:
            text = fh.read(4 << 20)
    except OSError:
        raise GitUnknown("a patch this guard cannot read")
    names = []
    for line in text.splitlines():
        for head in ("diff --git ", "--- ", "+++ ", "rename to ", "copy to ", "rename from ", "copy from "):
            if line.startswith(head):
                names.extend(line[len(head):].split())
    return names


def judge_tree_write(verb, args, where, g):
    """None when the verb leaves every guarded file's guarded keys as they are; else (path, cause)."""
    if any(a in CONTROL_FLAGS or a in DRY_RUN_FLAGS.get(verb, ()) for a in args):
        if not (verb == "apply" and "--apply" in args):
            return None
    if verb == "apply":
        if "--cached" in args and "--index" not in args:
            return None
        valued = {"-p", "-C", "--directory", "--exclude", "--include", "--whitespace", "-S", "--patch-format"}
        _, ops, tail = split_args(without_values(args, valued))
        files = ops + tail
        if not files:
            return ("a patch", "comes from stdin, which this guard cannot read")
        for f in files:
            names = patch_names(f, where)
            if True:
                # git's own reading of the names (renames, --directory, quoted names), with the
                # hand-read headers kept as well.
                passthrough = [a for a in args if a.startswith(("-p", "--directory"))]
                rc, out = run_git(where, "apply", "--numstat", "-z", *passthrough, "--", f)
                if rc == 0:
                    names += [x.split("\t")[-1] for x in out.decode("utf-8", "replace").split("\0") if x]
            for n in names:
                if n.rpartition("/")[2].lower() in SETTINGS_NAMES:
                    return (n, "patches a settings file")
        return None
    repo = Repo(where, g)
    if repo.top is None or not repo.files:
        return None
    try:
        pairs = plan(verb, args, repo)               # [(rel, before, after)]
    except NoSuchRev:
        return None
    for rel, before, after in pairs:
        cause = compare(before, after)
        if cause:
            return (repo.files[rel], cause)
    return None


def plan(verb, args, repo):
    """What the verb would do to each guarded file in scope: [(rel, before text, after text)]."""
    out = []
    rels = list(repo.files)

    def need(r):
        c = repo.rev(r)
        if c is None:
            raise NoSuchRev(r)                        # git fails on it too, and writes nothing
        return c

    def from_rev(commit, specs, remove_missing):
        for rel in rels:
            if not in_scope(rel, specs, repo):
                continue
            cur = repo.current(rel)
            after = repo.blob(commit + ":" + rel)
            if after is MISSING and not (remove_missing and repo.tracked(rel)):
                continue
            out.append((rel, cur, after))

    def from_index(specs):
        for rel in rels:
            if in_scope(rel, specs, repo):
                after = repo.blob(":" + rel)
                if after is not MISSING:
                    out.append((rel, repo.current(rel), after))

    def change(base, target):
        # The change base -> target lands on the current file. When both sides changed it, git leaves
        # conflict markers, which no JSON parser reads (threat model, 095).
        for rel in rels:
            b = MISSING if base is None else repo.blob(base + ":" + rel)
            t = repo.blob(target + ":" + rel)
            if t == b:
                continue
            h = repo.current(rel)
            out.append((rel, h, t if h in (b, t) else CONFLICT))

    if verb == "checkout":
        valued = {"-b", "-B", "--orphan", "--conflict", "--pathspec-from-file"}
        if opt_value(args, "--pathspec-from-file"):
            raise GitUnknown("a pathspec read from a file")
        if "--orphan" in args:
            return out
        create = opt_value(args, "-b", "-B")
        opts, ops, tail = split_args(without_values(args, valued))
        if create is not None:
            if ops:
                from_rev(need(ops[0]), [], True)
            return out
        has_dd = "--" in args
        if has_dd:
            if ops:
                from_rev(need(ops[0]), tail, False)
            else:
                from_index(tail)
        elif ops and (ops[0] == "-" or repo.rev(ops[0])):
            r = "@{-1}" if ops[0] == "-" else ops[0]
            if ops[1:]:
                from_rev(need(r), ops[1:], False)
            else:
                from_rev(need(r), [], True)
        elif ops:
            from_index(ops)
        return out
    if verb == "switch":
        if any(a == "--orphan" for a in args):
            for rel in rels:
                if repo.tracked(rel):
                    out.append((rel, repo.current(rel), MISSING))
            return out
        start = None
        if opt_value(args, "-c", "-C", "--create", "--force-create") is not None:
            _, ops, _ = split_args(without_values(args, {"-c", "-C", "--create", "--force-create"}))
            start = ops[0] if ops else None
        else:
            _, ops, _ = split_args(args)
            start = ops[0] if ops else None
            if start == "-":
                start = "@{-1}"
        if start:
            from_rev(need(start), [], True)
        return out
    if verb == "restore":
        staged = any(a in ("-S", "--staged") for a in args)
        worktree = any(a in ("-W", "--worktree") for a in args)
        if staged and not worktree:
            return out
        if opt_value(args, "--pathspec-from-file"):
            raise GitUnknown("a pathspec read from a file")
        src = opt_value(args, "--source", "-s")
        _, ops, tail = split_args(without_values(args, {"-s", "--source", "--conflict"}))
        specs = ops + tail
        if src:
            from_rev(need(src), specs, True)
        else:
            from_index(specs)
        return out
    if verb == "reset":
        if not any(a in ("--hard", "--keep", "--merge") for a in args):
            return out
        _, ops, _ = split_args(args)
        from_rev(need(ops[0] if ops else "HEAD"), [], True)
        return out
    if verb == "stash":
        _, ops, tail = split_args(args)
        sub = args[0] if args and not args[0].startswith("-") else "push"
        if sub in ("list", "show", "drop", "clear", "create", "store"):
            return out
        if sub in ("pop", "apply", "branch"):
            rest = ops[1:]
            if sub == "branch":
                rest = rest[1:]
            ref = need(rest[0] if rest else "stash@{0}")
            for rel in rels:
                b, a = repo.blob(ref + "^1:" + rel), repo.blob(ref + ":" + rel)
                untracked = repo.rev(ref + "^3")
                if untracked and a == b:
                    a = repo.blob(untracked + ":" + rel)
                    if a is MISSING:
                        continue
                out.append((rel, b, a))
            return out
        # push, save, or a bare stash: tracked changes go back to HEAD (or the index with -k),
        # untracked files go with -u, ignored ones too with -a.
        specs = (ops[1:] if sub in ("push", "save") and args and args[0] == sub else ops) + tail
        if sub == "save":
            specs = []                                # save takes a message, not paths
        keep = any(a in ("-k", "--keep-index") for a in args)
        untracked = any(a in ("-u", "--include-untracked") for a in args)
        everything = any(a in ("-a", "--all") for a in args)
        head = repo.rev("HEAD")
        for rel in rels:
            if not in_scope(rel, specs, repo):
                continue
            cur = repo.current(rel)
            if repo.tracked(rel):
                src = repo.blob(":" + rel) if keep else (repo.blob(head + ":" + rel) if head else MISSING)
                out.append((rel, cur, src))
            elif cur is not MISSING and (everything or (untracked and not repo.ignored(rel))):
                out.append((rel, cur, MISSING))
        return out
    if verb == "clean":
        if not any(a.startswith("-") and not a.startswith("--") and "f" in a or a == "--force" for a in args):
            return out                                # without -f git refuses (clean.requireForce)
        x = any(a.startswith("-") and not a.startswith("--") and "x" in a for a in args)
        only_ignored = any(a.startswith("-") and not a.startswith("--") and "X" in a for a in args)
        _, ops, tail = split_args(without_values(args, {"-e", "--exclude"}))
        for rel in rels:
            if not in_scope(rel, ops + tail, repo) or repo.tracked(rel):
                continue
            cur = repo.current(rel)
            if cur is MISSING:
                continue
            ign = repo.ignored(rel)
            if (ign and (x or only_ignored)) or (not ign and not only_ignored):
                out.append((rel, cur, MISSING))
        return out
    if verb == "merge":
        valued = {"-s", "-X", "-m", "-F", "--strategy", "--strategy-option", "--file", "--into-name"}
        _, ops, _ = split_args(without_values(args, valued))
        for r in ops or ["@{upstream}"]:
            target = need(r)
            change(repo.merge_base("HEAD", target), target)
        return out
    if verb == "rebase":
        if "--root" in args:
            raise GitUnknown("a rebase with --root")
        onto = opt_value(args, "--onto")
        valued = {"--onto", "-s", "-X", "--strategy", "--strategy-option", "-x", "--exec"}
        _, ops, _ = split_args(without_values(args, valued))
        upstream = need(ops[0] if ops else "@{upstream}")
        target = need(onto) if onto else upstream
        change(repo.merge_base("HEAD", upstream), target)
        if len(ops) > 1:
            from_rev(need(ops[1]), [], True)
        return out
    if verb in ("cherry-pick", "revert"):
        valued = {"-m", "--mainline", "-s", "-X", "--strategy", "--strategy-option"}
        _, ops, _ = split_args(without_values(args, valued))
        for r in ops:
            if ".." in r:
                a, _, b = r.partition("...") if "..." in r else r.partition("..")
                lo, hi = need(a or "HEAD"), need(b or "HEAD")
            else:
                hi = need(r)
                lo = repo.rev(r + "^")
            if verb == "cherry-pick":
                change(lo, hi)
            else:
                if lo is None:
                    raise GitUnknown("a revert of a root commit")
                change(hi, lo)
        return out
    if verb == "read-tree":
        if not any(a == "-u" for a in args):
            return out
        if opt_value(args, "--prefix"):
            raise GitUnknown("read-tree --prefix")
        _, ops, _ = split_args(args)
        if not ops:
            raise GitUnknown("read-tree with no tree")
        from_rev(need(ops[-1]), [], True)
        return out
    if verb == "rm":
        _, ops, tail = split_args(args)
        for rel in rels:
            if in_scope(rel, ops + tail, repo) and repo.tracked(rel):
                out.append((rel, repo.current(rel), MISSING))
        return out
    if verb == "checkout-index":
        if "--stdin" in args:
            raise GitUnknown("checkout-index --stdin reads its paths from a pipe")
        _, ops, tail = split_args(args)
        if any(a in ("-a", "--all") for a in args):
            from_index([])
        elif ops or tail:
            from_index(ops + tail)
        return out
    return out


# Verbs that move no ref, index entry or object a later tree verb on the same line would read.
GIT_STILL = frozenset("status diff log show add ls-files rev-parse grep blame cat-file check-ignore config "
                      "remote push describe shortlog whatchanged ls-tree ls-remote help version".split())
GIT_KNOWN = TREE_VERBS | GIT_STILL | frozenset(
    "pull fetch commit branch tag update-ref symbolic-ref hash-object update-index commit-tree mktree "
    "fast-import replace notes init clone worktree submodule sparse-checkout mv am bisect gc fsck "
    "maintenance reflog prune repack archive bundle format-patch send-email range-diff difftool "
    "mergetool filter-branch".split())
# Verbs that rewrite the tree in ways this guard does not model: denied when a guarded file is there.
TREE_UNMODELLED = frozenset("sparse-checkout submodule filter-branch bisect am".split())


def _where(args, g, base, strict=True):
    """(directory, index of the subcommand) after git's global options. strict: a --git-dir or
    --work-tree, which moves the tree out of this guard's sight, raises."""
    where, i = base, 0
    while i < len(args) and args[i].startswith("-"):
        a = args[i]
        if a in ("--git-dir", "--work-tree") or a.startswith(("--git-dir=", "--work-tree=")):
            if strict:
                raise GitUnknown("--git-dir or --work-tree")
            i += 1 if "=" in a else 2
            continue
        if a == "-C" and i + 1 < len(args):
            where = os.path.join(where, expand_vars(args[i + 1], g))
            if "$" in where or "`" in where:
                raise GitUnknown("a directory this guard cannot follow")
            i += 2
            continue
        i += 2 if a in GIT_GLOBAL_VALUED else 1
    return where, i


PROGRAM_RUNNERS = frozenset("sh bash zsh dash ksh fish eval".split())
GIT_WRAPPERS = frozenset("env command exec nohup nice time timeout sudo xargs stdbuf ionice caffeinate".split())


def git_args(words):
    """The words after `git` when the simple command runs git, through env, command, xargs, timeout and
    the like (095 adversarial #2); else None."""
    cw = command_word(words)
    if not cw:
        return None
    i = words.index(cw)
    while i < len(words):
        base = words[i].rpartition("/")[2]
        if base == "git":
            return words[i + 1:]
        if base not in GIT_WRAPPERS:
            return None
        i += 1
        while i < len(words) and (words[i].startswith("-") or NAME_ASSIGN.match(words[i])
                                  or re.fullmatch(r"[0-9.]+[smhd]?", words[i])):
            i += 1
    return None


def git_verb(words, g, bases):
    """(verb, args) for one git command, an alias resolved once (a one-shot `-c alias.x=…` first). A
    shell alias is "!alias"."""
    args = git_args(words)
    one_shot = {}
    for k, a in enumerate(args):
        if a == "-c" and k + 1 < len(args) and args[k + 1].lower().startswith("alias."):
            name, _, value = args[k + 1][6:].partition("=")
            one_shot[name] = value
    try:
        where, i = _where(args, g, bases[0], strict=False)
    except GitUnknown:
        where, i = bases[0], len(args)
    if i >= len(args):
        return None, []
    verb, rest = args[i], args[i + 1:]
    if verb in one_shot or (verb not in GIT_KNOWN and os.path.isdir(where)):
        if verb in one_shot:
            rc, out = 0, one_shot[verb].encode()
        else:
            rc, out = run_git(where, "config", "--get", "alias." + verb)
        if rc == 0 and out.strip():
            value = out.decode("utf-8", "replace").strip()
            if value.startswith("!"):
                return "!alias", rest
            try:
                parts = shlex.split(value)
            except ValueError:
                raise GitUnknown("an alias this guard cannot read")
            if parts:
                return parts[0], parts[1:] + rest
    return verb, rest


def git_tree_verdict(words, verb, rest, g, bases, lost):
    """(path, cause) for one git command (its verb resolved by git_verb) that writes the tree and
    changes a guarded key, or None."""
    if verb not in TREE_VERBS and verb not in TREE_UNMODELLED and verb != "pull":
        return None
    if lost:
        raise GitUnknown("a directory this guard cannot follow")
    args = git_args(words)
    for base in bases:
        where, _ = _where(args, g, base)
        if not os.path.isdir(where):
            continue
        if verb in TREE_UNMODELLED:
            repo = Repo(where, g)
            if repo.top and repo.files:
                raise GitUnknown("git " + verb + " is not modelled by this guard")
            continue
        if verb == "pull":
            hit = judge_pull(rest, where, g)
        else:
            hit = judge_tree_write(verb, rest, where, g)
        if hit:
            return hit
    return None


def judge_pull(args, where, g):
    """O3: a pull from a configured remote brings the shared history and is allowed. `git pull .
    branch` is a merge of a local branch; a pull from a path or URL is not origin (threat model)."""
    valued = {"-s", "-X", "--strategy", "--strategy-option", "--depth", "--upload-pack", "-j", "--jobs"}
    _, ops, _ = split_args(without_values(args, valued))
    if not ops:
        return None
    rc, out = run_git(where, "remote")
    remotes = set(out.decode("utf-8", "replace").split()) if rc == 0 else set()
    if ops[0] in remotes:
        return None
    if ops[0] == ".":
        return judge_tree_write("merge", ops[1:] or ["HEAD"], where, g)
    raise GitUnknown("a pull from something that is not a configured remote")


def bash_verdict(cmd, g):
    """The text judged twice, as the lexer reads it and with bash comments removed. Neither reading is
    bash's: a `# '` pair hides a command from the first (095 adversarial #5), a quote inside "$( )"
    hides one from the second (095 /security-review). A command either reading sees is judged."""
    v = _bash_verdict(cmd, g, False)
    return v if v[0] != "none" else _bash_verdict(cmd, g, True)


def _bash_verdict(cmd, g, strip):
    # Read with quotes and backslashes gone and $'…' decoded, as bash reads it: `dot''glob` and
    # `$'\x64otglob'` turn the option on too (/security-review, spec 090). Any shopt or -O at all
    # counts, since the option name may come from a variable.
    plain = re.sub(r"[\"'\\]", "", ANSI_C.sub(ansi_c, cmd))
    g.loose_glob = bool(re.search(r"shopt|dotglob|globstar|GLOBIGNORE|(^|\s)-O", plain))
    text = cmd.replace("\\\n", "")
    text = ANSI_C.sub(ansi_c, text)
    text = text.replace('$"', '"')
    text = attach_heredocs(text)
    parts = text.split("`")
    text = "".join(p + ("" if i == len(parts) - 1 else (" $( " if i % 2 == 0 else " ) "))
                   for i, p in enumerate(parts))
    cmds = split_commands(text, strip)
    if cmds is None:
        low = cmd.lower()
        return ["settings-bash", "an unbalanced quote"] if ("settings" in low or ".claude" in low) else ["none"]
    bases = [g.cwd]
    by_name = dots = lost = False
    for d in dir_targets(cmds):
        d = expand_vars(d, g)
        if "$" in d or "`" in d or GLOBCH.search(d):
            by_name = dots = lost = True              # somewhere this text cannot follow
            continue
        for b in list(bases):
            full = os.path.join(b, d)
            if g.is_dir(full):
                by_name = dots = True
            bases.append(full)
    for words, _, _ in cmds:
        cw = command_word(words)
        if cw and cw.rpartition("/")[2] in TREE_COMMANDS:
            by_name = True
    tainted = prelude_taints(cmds, text)
    for words, targets, in_subst in cmds:
        for t in targets:
            hit = word_hit(t, g, bases, by_name, dots)
            if hit:
                return ["settings-bash", hit]
        pats = pattern_indices(words) if not dots else set()
        naming = [(i, word_hit(w, g, bases, by_name and i not in pats, dots)) for i, w in enumerate(words)]
        naming = [(i, h) for i, h in naming if h]
        if not naming:
            continue
        if not reads(words) or in_subst or tainted:
            return ["settings-bash", naming[0][1]]
        # A read whose output can reach a command that runs text: cat <path> | sh, echo <path> | xargs rm.
        others = [command_word(w) for w, _, _ in cmds if w is not words]
        if any(o and o.rpartition("/")[2] in EXEC_COMMANDS for o in others):
            return ["settings-bash", naming[0][1]]
        for i, h in naming:
            if words[i].startswith("-") or (i > 0 and words[i - 1] in OUTPUT_OPTIONS):
                return ["settings-bash", h]
    # A program inside a word (bash -c '…', a heredoc body handed on) that runs git is judged as a
    # command of its own (095 adversarial #2).
    # Only a shell or eval runs the text: a heredoc handed to cat is data.
    if g.depth < 3:
        for words, _, _ in cmds:
            if (command_word(words) or "").rpartition("/")[2] not in PROGRAM_RUNNERS:
                continue
            for w in words[1:]:
                if re.search(r"\s", w) and re.search(r"\bgit\b", w):
                    g.depth += 1
                    try:
                        v = bash_verdict(w, g)
                    finally:
                        g.depth -= 1
                    if v[0] != "none":
                        return v
    return git_verdicts(cmds, g, bases, lost, text)


def git_verdicts(cmds, g, bases, lost, text):
    """R1 over every git command in the text."""
    gits = [w for w, _, _ in cmds if git_args(w) is not None]
    if not gits:
        return ["none"]
    try:
        verbs = [git_verb(w, g, bases) for w in gits]
        for k, (verb, _) in enumerate(verbs):
            if verb not in TREE_VERBS and verb not in TREE_UNMODELLED and verb != "pull":
                continue
            # A ref, index or object moved earlier on the same line is read before it moves: `git
            # update-ref refs/heads/x <evil> && git checkout x -- .` (threat model, 095).
            if any(v not in TREE_VERBS and v not in GIT_STILL for v, _ in verbs[:k] if v):
                raise GitUnknown("another git command earlier on the line moves what it would read")
            # GIT_INDEX_FILE, GIT_DIR … set anywhere on the line point git at what this guard does not
            # read: the guard's own git calls drop them (095 adversarial #3).
            if re.search(r"\bGIT_[A-Z_]+", text):
                raise GitUnknown("a GIT_ variable on the same line")
        for words, (verb, rest) in zip(gits, verbs):
            if verb in TREE_VERBS or verb in TREE_UNMODELLED or verb == "pull":
                hit = git_tree_verdict(words, verb, rest, g, bases, lost)
                if hit:
                    return ["settings-git", hit[0], hit[1]]
    except GitUnknown as exc:
        return ["settings-git", "the working tree", str(exc)]
    return ["none"]


# ----------------------------------------------------------------------------- MCP tools (R3)
# Spec 095 R3 (F116). An MCP or plugin tool names its file in a field of its own choosing (path,
# destination, files: {path: text}), so every string is read: values and object keys, plus each
# container's strings joined with "" and with "/" (a path split across fields). A string that looks
# like a command (whitespace or a shell operator) is judged as a Bash command too, which covers an
# execute_command tool handed `git checkout HEAD -- .`. A tool whose name says it only reads is left to
# the read rules: the server's own name is the developer's configuration.
MCP_MAX_DEPTH = 8
MCP_MAX_STRINGS = 512
MCP_READ_NAME = re.compile(r"^(read|get|list|search|view|stat|find|query|describe|show|head|tail|cat|grep)"
                           r"(_|$)", re.I)
# A read-named tool that also writes (find_and_replace, search_and_replace) is not a read (095 adversarial #10).
MCP_WRITE_WORD = re.compile(r"replace|write|edit|move|copy|delete|remove|set|create|put|update|apply|patch|"
                            r"save|rename|append|insert|exec|run", re.I)


class McpTooBig(Exception):
    pass


def mcp_strings(v, depth=0, acc=None, groups=None):
    acc = [] if acc is None else acc
    groups = [] if groups is None else groups
    if depth > MCP_MAX_DEPTH:
        raise McpTooBig
    if isinstance(v, str):
        acc.append(v)
    elif isinstance(v, dict):
        mine = []
        for k, x in v.items():
            acc.append(k)
            if isinstance(x, str):
                mine.append(x)
            mcp_strings(x, depth + 1, acc, groups)
        groups.append(mine)
    elif isinstance(v, list):
        mine = [x for x in v if isinstance(x, str)]
        for x in v:
            mcp_strings(x, depth + 1, acc, groups)
        groups.append(mine)
    if len(acc) > MCP_MAX_STRINGS:
        raise McpTooBig
    return acc, groups


def mcp_inputs(tool, ti):
    """(path candidates, command strings) for an mcp__ call, or None for a tool whose name says it
    reads. Shared with trust-anchor-guard, which judges the same two lists against its own stores.
    Raises McpTooBig past the caps."""
    name = tool.rsplit("__", 1)[-1]
    if MCP_READ_NAME.match(name) and not MCP_WRITE_WORD.search(name):
        return None
    strings, groups = mcp_strings(ti)
    cands = list(strings)
    for grp in groups:                               # every run of 2-4 neighbouring strings
        for i in range(len(grp)):
            for j in range(i + 2, min(i + 4, len(grp)) + 1):
                cands += ["".join(grp[i:j]), "/".join(grp[i:j])]
    from urllib.parse import unquote
    paths = []
    for s in cands:
        if s and "\n" not in s and len(s) <= 4096:
            for p in {s, unquote(s)}:                  # file:///p/%2Eclaude/… (095 adversarial #10)
                paths.append(re.sub(r"^file://(localhost)?", "", p))
    commands = [s for s in strings if re.search(r"\s|[;&|<>`$]", s) and len(s) <= 65536]
    return paths, commands


def mcp_verdict(tool, ti, g, raw):
    try:
        found = mcp_inputs(tool, ti)
    except McpTooBig:
        low = raw.lower()
        return ["settings-shell", "an MCP payload too large to read"] if ("sett" in low or ".cla" in low) else ["none"]
    if found is None:
        return ["none"]
    paths, commands = found
    for p in paths:
        p = expand_vars(p, g)
        hit = g.file_of(p) or (p if g.is_dir(p.rstrip("/") or "/") else None) or \
            (g.glob_hit(p) if GLOBCH.search(p) else None)
        if hit:
            return ["settings-shell", hit]
    for s in commands:
        v = bash_verdict(s, g)
        if v[0] != "none":
            return v
    return ["none"]


# ----------------------------------------------------------------------------- main

def main():
    raw = sys.stdin.read()
    try:
        d = json.loads(raw)
        if not isinstance(d, dict):
            raise ValueError
    except Exception:
        print("unparseable")
        return
    ti = d.get("tool_input")
    if not isinstance(ti, dict):
        print("unparseable")
        return
    cwd = d.get("cwd") if isinstance(d.get("cwd"), str) and d.get("cwd") else os.getcwd()
    g = Guarded(os.environ, cwd)
    tool = d.get("tool_name") or ""
    cmd = ti.get("command")
    if isinstance(tool, str) and tool.startswith("mcp__"):
        v = mcp_verdict(tool, ti, g, raw)
    elif tool == "Bash" or (isinstance(cmd, str) and not ti.get("file_path")):
        v = bash_verdict(cmd if isinstance(cmd, str) else "", g)
    else:
        v = edit_verdict(tool, ti, g)
    print("\t".join(v))


if __name__ == "__main__":
    main()
