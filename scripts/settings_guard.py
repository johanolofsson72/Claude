#!/usr/bin/env python3
"""The verdict behind scripts/settings-edit-guard-hook.sh (spec 089).

Reads a PreToolUse payload on stdin and prints one line: a verdict word, then tab-separated details.

    none
    settings-key <path> <key,key>     a write that changes hooks, disableAllHooks or env
    settings-invalid <path>           a write that leaves the file unparseable
    settings-unreadable <path>        the current file is not a JSON object
    settings-shell <path>             a call with no bytes to simulate (NotebookEdit, a glob, a
                                      delegated shell write from bash-write-guard)
    settings-bash <path>              a shell command that writes, or might write, a guarded file
    unparseable                       the payload is not a JSON object

WHICH FILES (R1, developer O1). The three that this session and the next one load:
<project>/.claude/settings.json, <project>/.claude/settings.local.json and <config>/settings.json,
compared after realpath, NFC, and case folding where the file system folds case. A hard link to one
is the same file. Another project's settings are not this guard's.

WHICH KEYS (R2, O2). hooks, disableAllHooks and env, by deep equality with "absent" as a value.

THE SHELL (R4). The command text is split into simple commands, and a simple command that names a
guarded file passes only when it reads (READ_COMMANDS, `python3 -m json.tool <one file>`, GIT_READ).
A redirection into a guarded file, or an output option naming one, is a write whatever the command.
Nothing is evaluated: a name assembled at runtime from parts that spell neither the file nor its
directory is the declared bound, the same as bash-write-guard's.

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

GUARDED_KEYS = ("hooks", "disableAllHooks", "env")
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
MISSING = object()


# ----------------------------------------------------------------------------- paths

def norm(p):
    p = unicodedata.normalize("NFC", os.path.realpath(p))
    return p.lower() if FOLD else p


def norm_pattern(p):
    p = unicodedata.normalize("NFC", os.path.normpath(p))
    return p.lower() if FOLD else p


class Guarded:
    def __init__(self, env, cwd):
        self.cwd = cwd
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
        return None

    def is_dir(self, p):
        return norm(self.absolute(p)) in self.dir_keys

    def glob_hit(self, pattern):
        """A guarded file or directory a glob pattern can match, or None."""
        pat = norm_pattern(self.absolute(pattern))
        for form in self.file_forms | self.dir_forms:
            if fnmatch.fnmatchcase(form, pat):
                return form
        try:
            for m in glob.glob(self.absolute(pattern)):
                if self.file_of(m) or self.is_dir(m):
                    return m
        except Exception:
            pass
        return None


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
    # As JSON text, not Python ==: True == 1 would read env 1 -> true as unchanged (/security-review).
    return [k for k in GUARDED_KEYS if _canon(before.get(k, MISSING)) != _canon(after.get(k, MISSING))]


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
        return ["settings-shell", hit] if hit else ["none"]
    path = g.file_of(fp)
    if not path:
        return ["none"]
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

ANSI_C = re.compile(r"\$'((?:[^'\\]|\\.)*)'")
HEREDOC = re.compile(r"(?<!<)<<(?!<)(-?)[ \t]*([^\s;&|<>()]*)")
NAME_ASSIGN = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
PATHISH = re.compile(r"[^\s'\"`;&|<>()=,]+")
INTERESTING = re.compile(r"(?i)sett|\.cla|[*?\[$`{]")


def ansi_c(m):
    try:
        s = m.group(1).encode("latin-1", "backslashreplace").decode("unicode_escape")
    except Exception:
        s = m.group(1)
    return shlex.quote(s)


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
            extra.append((m.end(), " ".join(shlex.quote(w) for w in words)))
        for pos, words in reversed(extra):
            line = line[:pos] + " " + words + " " + line[pos:]
        out.append(line)
    return "\n".join(out)


def brace_expand(word, depth=0):
    m = re.search(r"\{([^{}]*,[^{}]*)\}", word)
    if not m or depth > 4:
        return [word]
    out = []
    for alt in m.group(1).split(","):
        out.extend(brace_expand(word[:m.start()] + alt + word[m.end():], depth + 1))
    return out[:64]


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
    cmd = rest[0].rpartition("/")[2]
    if cmd == "rg" and any(w == "--pre" or w.startswith("--pre=") for w in rest):
        return False                                  # rg --pre runs a program on each file
    if cmd in READ_COMMANDS:
        return True
    if cmd in ("python3", "python") and rest[1:3] == ["-m", "json.tool"]:
        return len([w for w in rest[3:] if not w.startswith("-")]) == 1
    if cmd == "git":
        j = 1
        while j < len(rest):
            w = rest[j]
            if w in ("-c", "--config-env") or w.startswith("--config-env=") or w.startswith("--exec-path"):
                return False                          # git -c core.pager=…, diff.external=…
            if w in ("-C", "--git-dir", "--work-tree", "--namespace"):
                j += 2
                continue
            if w.startswith("-"):
                j += 1
                continue
            return w in GIT_READ
        return True
    return False


def split_commands(text):
    """[(words, redirect_targets)] per simple command, or None when the text cannot be split."""
    lex = shlex.shlex(text, posix=True, punctuation_chars="();<>|&\n")
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


def bash_verdict(cmd, g):
    text = cmd.replace("\\\n", "")
    text = ANSI_C.sub(ansi_c, text)
    text = text.replace('$"', '"')
    text = attach_heredocs(text)
    parts = text.split("`")
    text = "".join(p + ("" if i == len(parts) - 1 else (" $( " if i % 2 == 0 else " ) "))
                   for i, p in enumerate(parts))
    cmds = split_commands(text)
    if cmds is None:
        low = cmd.lower()
        return ["settings-bash", "an unbalanced quote"] if ("settings" in low or ".claude" in low) else ["none"]
    bases = [g.cwd]
    by_name = dots = False
    for d in dir_targets(cmds):
        d = expand_vars(d, g)
        if "$" in d or "`" in d or GLOBCH.search(d):
            by_name = dots = True                     # somewhere this text cannot follow
            continue
        for b in list(bases):
            full = os.path.join(b, d)
            if g.is_dir(full):
                by_name = dots = True
            bases.append(full)
    runs_text = False
    for words, _, _ in cmds:
        cw = command_word(words)
        if cw and cw.rpartition("/")[2] in TREE_COMMANDS:
            by_name = True
    for words, targets, in_subst in cmds:
        for t in targets:
            hit = word_hit(t, g, bases, by_name, dots)
            if hit:
                return ["settings-bash", hit]
        naming = [(i, word_hit(w, g, bases, by_name, dots)) for i, w in enumerate(words)]
        naming = [(i, h) for i, h in naming if h]
        if not naming:
            continue
        if not reads(words) or in_subst:
            return ["settings-bash", naming[0][1]]
        # A read whose output can reach a command that runs text: cat <path> | sh, echo <path> | xargs rm.
        others = [command_word(w) for w, _, _ in cmds if w is not words]
        if any(o and o.rpartition("/")[2] in EXEC_COMMANDS for o in others):
            return ["settings-bash", naming[0][1]]
        for i, h in naming:
            if words[i].startswith("-") or (i > 0 and words[i - 1] in OUTPUT_OPTIONS):
                return ["settings-bash", h]
    return ["none"]


# ----------------------------------------------------------------------------- main

def main():
    try:
        d = json.loads(sys.stdin.read())
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
    if tool == "Bash" or (isinstance(cmd, str) and not ti.get("file_path")):
        v = bash_verdict(cmd if isinstance(cmd, str) else "", g)
    else:
        v = edit_verdict(tool, ti, g)
    print("\t".join(v))


if __name__ == "__main__":
    main()
