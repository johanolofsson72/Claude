#!/usr/bin/env python3
"""The shell's own word rules, shared by the guards that judge a command's text (spec 090).

Three guards read paths out of command text: trust-anchor (is this an acceptance.md), settings-edit
(is this a settings file) and destructive-command (is this a delete refspec). Each carried its own
copy of `$'…'` decoding and brace expansion, and the copies disagreed: settings_guard expanded
`{a,b}` only, so `.cla{u..u}de/settings.json` named no settings file to it while bash wrote one
(/simplify, spec 090). One copy here, imported by all three.

    ANSI_C, ansi_c(match)   $'\\x63laude' -> claude, the way bash decodes it
    brace_alts(word)        bash brace expansion: {a,b} and {x..y[..n]}; a lone {…} is literal
    TooMany                 raised when an expansion would pass BRACE_CAP: the caller fails closed
    sed_args(words)         (in_place, scripts or None, files) for one sed command's words (spec 095)
    sed_script_kind(text)   "print", "edit" or None: what a sed script can do besides print

Imported by name from the scripts directory; no side effects, no third-party modules.
"""
from __future__ import annotations

import re

ANSI_C = re.compile(r"\$'((?:[^'\\]|\\.)*)'")
BRACE_CAP = 512


class TooMany(Exception):
    """More expansions than a guard will enumerate (spec 090, adversarial review #2 and #3)."""


def ansi_c_text(body: str) -> str:
    try:
        return body.encode("latin-1", "backslashreplace").decode("unicode_escape")
    except Exception:
        return body


def ansi_c(m: re.Match) -> str:
    return ansi_c_text(m.group(1))


def _sequence(body: str) -> list[str] | None:
    q = re.fullmatch(r"(-?\d+)\.\.(-?\d+)(?:\.\.(-?\d+))?", body) or \
        re.fullmatch(r"([A-Za-z])\.\.([A-Za-z])(?:\.\.(-?\d+))?", body)
    if not q:
        return None
    a, b, st = q.group(1), q.group(2), abs(int(q.group(3) or 1)) or 1
    num = a.lstrip("-").isdigit()
    lo, hi = (int(a), int(b)) if num else (ord(a), ord(b))
    rng = range(lo, hi + 1, st) if lo <= hi else range(lo, hi - 1, -st)
    if len(rng) > BRACE_CAP:                     # sized before it is built
        raise TooMany
    if not num:
        return [chr(n) for n in rng]
    pad = a.lstrip("-").startswith("0") or b.lstrip("-").startswith("0")
    w = max(len(a), len(b)) if pad else 0
    return [str(n).zfill(w) for n in rng]


def brace_alts(s: str, depth: int = 0) -> list[str]:
    """Every word bash makes of s by brace expansion. Raises TooMany past BRACE_CAP."""
    if depth > 8:
        raise TooMany
    for m in re.finditer(r"\{([^{}]*)\}", s):
        body, pre, post = m.group(1), s[:m.start()], s[m.end():]
        alts = body.split(",") if "," in body else _sequence(body)
        if alts is None:
            continue
        if len(alts) > BRACE_CAP:
            raise TooMany
        out: list[str] = []
        for alt in alts:
            out.extend(brace_alts(pre + alt + post, depth + 1))
            if len(out) > BRACE_CAP:
                raise TooMany
        return out
    return [s]


# ----------------------------------------------------------------------------- sed (spec 095 R8, R9)
# Two guards asked "does this sed write?" and both answered by the flag alone: settings_guard refused
# `sed -n 1,5p <settings>` (no -i, a read), and bash_write_targets kept the script word of a `sed -i`
# as a target, so a script that mentions a .git path read as a write to it (F121, F145). The script is
# parsed instead. Anything the parser does not know is None, and the caller keeps its old answer.

_SED_PRINT = set("pP=lqQnNdDgGhHxz")
_SED_SHORT = set("nefilIErsuza")
_SED_LONG = ("in-place", "expression", "file", "line-length", "quiet", "silent", "regexp-extended", "sandbox",
             "posix", "separate", "unbuffered", "null-data", "zero-terminated", "debug", "follow-symlinks",
             "binary", "help", "version")


def sed_args(words: list[str]):
    """(in_place, scripts, files) for the words after `sed`. scripts is None when a -f file supplies
    the script: it is not in the text."""
    in_place, scripts, files, first, from_file = False, [], [], None, False
    i = 0
    while i < len(words):
        w = words[i]
        i += 1
        if w == "--":
            files.extend(words[i:])
            break
        if w.startswith("--"):
            name, eq, val = w[2:].partition("=")
            # GNU takes any unambiguous prefix (`--in-pl`, threat model 095). An option this list
            # does not know, or a prefix of two, is read as a possible write.
            hits = [o for o in _SED_LONG if o.startswith(name)] if name else []
            name = name if name in _SED_LONG else (hits[0] if len(hits) == 1 else "in-place")
            if name == "in-place":
                in_place = True
            elif name in ("expression", "file", "line-length"):
                if not eq:
                    val = words[i] if i < len(words) else ""
                    i += 1
                if name == "expression":
                    scripts.append(val)
                elif name == "file":
                    from_file = True
            continue
        if w.startswith("-") and len(w) > 1:
            for j, ch in enumerate(w[1:], 1):
                if ch not in _SED_SHORT:
                    in_place = True                  # an option this parser does not know
                    break
                if ch in "iI":
                    in_place = True
                    # The rest of the word is the backup suffix. BSD sed also takes a separate suffix
                    # word (`-i ''`, `-i .bak`); GNU never does. A next word that is empty or is no
                    # script is taken as that suffix.
                    if w == "-" + ch and i < len(words) and (words[i] == "" or sed_script_kind(words[i]) is None):
                        i += 1
                    break
                if ch in "efl":                  # -e SCRIPT, -f FILE, -l N: the rest, or the next word
                    val = w[j + 1:]
                    if not val:
                        val = words[i] if i < len(words) else ""
                        i += 1
                    if ch == "e":
                        scripts.append(val)
                    elif ch == "f":
                        from_file = True
                    break
            continue
        if first is None and not scripts and not from_file:
            first = w
            continue
        files.append(w)
    if first is not None:
        scripts.append(first)
    return in_place, (None if from_file else scripts), files


def _sed_address(t: str, i: int) -> int:
    """Index after one address at t[i:] (none is fine), or -1 when it does not close."""
    if i < len(t) and t[i].isdigit():
        while i < len(t) and (t[i].isdigit() or t[i] == "~"):
            i += 1
        return i
    if i < len(t) and t[i] == "$":
        return i + 1
    if i < len(t) and t[i] in "/\\":
        d = "/"
        if t[i] == "\\":
            if i + 1 >= len(t):
                return -1
            i += 1
            d = t[i]
        i = _sed_delimited(t, i + 1, d)
        if i < 0:
            return -1
        while i < len(t) and t[i] in "IM":
            i += 1
    return i


def _sed_delimited(t: str, i: int, d: str) -> int:
    """Index after the next unescaped d at t[i:], or -1."""
    while i < len(t):
        if t[i] == "\\":
            i += 2
            continue
        if t[i] == d:
            return i + 1
        i += 1
    return -1


def sed_script_kind(t: str):
    """"print" when every command only prints, deletes or moves through the pattern space; "edit" when
    s/// or y/// appear too, with no w, W or e anywhere; None for anything else (a w file, an e
    command, a, i, c, r, labels, or text this parser cannot read)."""
    kind, i, depth = "print", 0, 0
    while i < len(t):
        while i < len(t) and t[i] in " \t\n;":
            i += 1
        if i >= len(t):
            break
        if t[i] == "}":
            depth -= 1
            if depth < 0:
                return None
            i += 1
            continue
        i = _sed_address(t, i)
        if i >= 0 and i < len(t) and t[i] == ",":
            i = _sed_address(t, i + 1)
        if i < 0:
            return None
        while i < len(t) and t[i] in " \t!":
            i += 1
        if i >= len(t):
            return None
        c = t[i]
        i += 1
        if c == "{":
            depth += 1
            continue
        if c in _SED_PRINT:
            while i < len(t) and t[i].isdigit():
                i += 1
        elif c in "sy":
            if i >= len(t) or t[i] in "\n\\":
                return None
            d = t[i]
            i = _sed_delimited(t, i + 1, d)
            i = _sed_delimited(t, i, d) if i >= 0 else -1
            if i < 0:
                return None
            if c == "s":
                while i < len(t) and t[i] in "gpiImM0123456789":
                    i += 1
            kind = "edit"
        else:
            return None
        while i < len(t) and t[i] in " \t":
            i += 1
        if i < len(t) and t[i] not in ";\n}":
            return None                          # a w, e or another flag follows: not ours to judge
    return kind if depth == 0 else None
