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
