// The guard-notice mod's pure logic (spec 096): no engine calls, so node can test it directly
// (node --experimental-strip-types lib.test.ts). register.tsx wires it to the engine.

// guard-lib.sh guard_announce and settings-edit-guard-hook.sh's repair path, word for word.
const ANNOUNCE = /^(\S+) could not decide and ALLOWED this call: (.+?)\. It fails open by design/s
const CRASHED = /^(\S+) crashed and ALLOWED this edit unchecked/

export type FailOpen = { guard: string; cause: string }

/** Every guard fail-open note among a tool call's context entries (R2). */
export function failOpenNotices(context: readonly string[] | undefined): FailOpen[] {
  const out: FailOpen[] = []
  for (const line of context ?? []) {
    const a = ANNOUNCE.exec(line)
    if (a) {
      out.push({ guard: a[1], cause: a[2] })
      continue
    }
    const c = CRASHED.exec(line)
    if (c) out.push({ guard: c[1], cause: 'it crashed' })
  }
  return out
}

export const TOAST_MAX = 160

function cut(text: string, max = TOAST_MAX): string {
  return text.length <= max ? text : text.slice(0, max - 1) + '…'
}

export function failOpenToast(n: FailOpen): string {
  return cut(`${n.guard} didn't check this call: ${n.cause}`)
}

// In a session a settings hook's deny reaches tool.call as an errored result whose text carries the
// harness prefix ("PreToolUse:Bash hook error: BLOCKED — …"); a plugin's own deny comes as { deny }.
const GUARD_DENY = /^(?:[^\n]*hook error:\s*)?BLOCKED —\s*([^\n]*)/

/** The toast for a template guard's deny, or null for any other result (R3). */
export function denyToast(text: string | undefined): string | null {
  const m = text ? GUARD_DENY.exec(text) : null
  return m ? cut(`Blocked: ${m[1]}`) : null
}

/** The deny text of a tool call's result: { deny }, or an errored result's text. */
export function denyText(r: { deny?: string; isError?: boolean; text?: string }): string | undefined {
  return r.deny ?? (r.isError ? r.text : undefined)
}

/** Once per session per key: true the first time a key is offered. */
export class Seen {
  private keys = new Set<string>()
  first(key: string): boolean {
    if (this.keys.has(key)) return false
    this.keys.add(key)
    return true
  }
}

export type Row = { id: string; slug: string }

/** The active register row: the first [/], else the first [ ], under "## Specs" only (R4). */
export function activeRow(index: string): Row | null {
  const lines = index.replace(/\r\n/g, '\n').split('\n')
  const start = lines.findIndex(l => /^## Specs\s*$/.test(l))
  if (start < 0) return null
  const body: string[] = []
  for (const l of lines.slice(start + 1)) {
    if (/^## /.test(l)) break
    body.push(l)
  }
  const pick = (mark: string) => body.find(l => l.startsWith(`- [${mark}] `))
  const line = pick('/') ?? pick(' ')
  if (!line) return null
  const [id, slug] = line.slice(6).split(' — ')
  return id && slug ? { id: id.trim(), slug: slug.trim() } : null
}

const SHORT: Record<string, string> = { 'full test suite': 'suite', 'mutation kill rate': 'mutation' }

/** The due jobs in `maintenance-due.sh --brief` output, short names; [] when none. */
export function maintenanceDue(brief: string): string[] {
  const out: string[] = []
  for (const l of brief.split('\n')) {
    const m = /^\s+· (.+?)(?: \(| —)/.exec(l)
    if (!m) continue
    const name = m[1].trim()
    const key = Object.keys(SHORT).find(k => name.startsWith(k))
    out.push(key ? SHORT[key] : name.split(/\s+/)[0])
  }
  return out
}

/** The band's text. due: the short names, [] for none, null when the script could not answer. */
export function bandText(row: Row, due: string[] | null): string {
  let text = `Next: ${row.id} ${row.slug}`
  if (due === null) text += '   Due: unknown'
  else if (due.length) text += `   Due: ${due.join(', ')}`
  if (/^H\d+/.test(row.id)) text += '   Checkpoint next'
  return text
}
