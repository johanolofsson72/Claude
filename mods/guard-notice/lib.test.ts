// Spec 096: node --experimental-strip-types --test mods/guard-notice/lib.test.ts
// Fixtures are the real texts of scripts/guard-lib.sh, settings-edit-guard-hook.sh and
// maintenance-due.sh --brief, so a change to any of them fails here.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import {
  activeRow, bandText, denyText, denyToast, failOpenNotices, failOpenToast, maintenanceDue, Seen, TOAST_MAX,
} from './lib.ts'

const ANNOUNCE = 'bash-write-guard could not decide and ALLOWED this call: no JSON parser on PATH (install jq; python3 is the fallback). It fails open by design (see its header), so this edit or command was not checked by it. Fix the cause to restore the check.'
const CRASH = "settings-edit-guard crashed and ALLOWED this edit unchecked, because it is an edit of the guard's own code (settings_guard.py): a guard that cannot run must not block its own repair."

test('096-R2 fail-open: the announce text names the guard and the cause', () => {
  assert.deepEqual(failOpenNotices([ANNOUNCE]), [
    { guard: 'bash-write-guard', cause: 'no JSON parser on PATH (install jq; python3 is the fallback)' },
  ])
})
test('096-R2 fail-open: the crash text', () => {
  assert.deepEqual(failOpenNotices([CRASH]), [{ guard: 'settings-edit-guard', cause: 'it crashed' }])
})
test('096-R2 fail-open: ordinary context, empty, undefined', () => {
  assert.deepEqual(failOpenNotices(['Spec register: next row 096']), [])
  assert.deepEqual(failOpenNotices([]), [])
  assert.deepEqual(failOpenNotices(undefined), [])
})
test('096-R2 fail-open: a near miss in lower case is not a notice', () => {
  assert.deepEqual(failOpenNotices(['x could not decide and allowed this call: y. It fails open by design']), [])
})
test('096-R2 fail-open: a notice quoted mid-text is not one', () => {
  assert.deepEqual(failOpenNotices([`the log said: ${ANNOUNCE}`]), [])
})
test('096-R2 fail-open: several entries, two notices', () => {
  assert.equal(failOpenNotices([ANNOUNCE, 'other', CRASH]).length, 2)
})
test('096-R2 fail-open: a very long cause is cut to the toast limit', () => {
  const long = ANNOUNCE.replace('no JSON parser', 'x'.repeat(400))
  const t = failOpenToast(failOpenNotices([long])[0])
  assert.equal(t.length, TOAST_MAX)
  assert.ok(t.endsWith('…'))
  assert.ok(t.startsWith("bash-write-guard didn't check this call: "))
})

test('096-R3 deny: a guard deny gives its first line', () => {
  const deny = 'BLOCKED — this edit changes hooks in /p/.claude/settings.json (spec 089, 095).\n\nEvery settings key is guarded'
  assert.equal(denyToast(deny), 'Blocked: this edit changes hooks in /p/.claude/settings.json (spec 089, 095).')
})
test('096-R3 deny: another hook, no deny, empty', () => {
  assert.equal(denyToast('Denied by policy'), null)
  assert.equal(denyToast(undefined), null)
  assert.equal(denyToast(''), null)
})
test('096-R3 deny: the session form, an errored result with the harness prefix', () => {
  const text = 'PreToolUse:Bash hook error: BLOCKED — this shell command writes, or may write, a Claude Code mod: x (spec 095a).\n\nA plugin folder'
  assert.equal(denyToast(denyText({ isError: true, text })),
    'Blocked: this shell command writes, or may write, a Claude Code mod: x (spec 095a).')
})
test('096-R3 deny: an ordinary tool error is no deny; a plain result has none', () => {
  assert.equal(denyToast(denyText({ isError: true, text: 'Exit code 1\nnpm ERR!' })), null)
  assert.equal(denyText({ isError: false, text: 'BLOCKED — quoted output' }), undefined)
  assert.equal(denyText({ deny: 'BLOCKED — x' }), 'BLOCKED — x')
})
test('096-R3 deny: BLOCKED quoted mid-output is not a deny', () => {
  assert.equal(denyToast('the log said BLOCKED — x'), null)
})
test('096-R3 deny: a long first line is cut', () => {
  const t = denyToast('BLOCKED — ' + 'y'.repeat(300))
  assert.equal(t?.length, TOAST_MAX)
})

test('096-R2/R3 Seen: once per key', () => {
  const s = new Seen()
  assert.equal(s.first('a'), true)
  assert.equal(s.first('a'), false)
  assert.equal(s.first('b'), true)
})

const REG = (rows: string) => `# Spec register\n\n## Specs\n\n${rows}\n\n## Register history (newest first)\n\n- [ ] 999 — in-history — not a row\n`
test('096-R4 row: the in-progress row wins over the next one', () => {
  assert.deepEqual(activeRow(REG('- [x] 095a — mod-loading-guard — full\n- [ ] 097 — b — x\n- [/] 096 — guard-notice-mod — light')),
    { id: '096', slug: 'guard-notice-mod' })
})
test('096-R4 row: only unstarted rows', () => {
  assert.deepEqual(activeRow(REG('- [x] 001 — a — x\n- [ ] 002 — b — x')), { id: '002', slug: 'b' })
})
test('096-R4 row: a held row is skipped', () => {
  assert.deepEqual(activeRow(REG('- [!] 003 — held — x\n- [ ] 004 — next — x')), { id: '004', slug: 'next' })
})
test('096-R4 row: all done, no Specs section, history rows ignored', () => {
  assert.equal(activeRow(REG('- [x] 001 — a — x')), null)
  assert.equal(activeRow('# nothing here\n- [ ] 001 — a — x'), null)
})
test('096-R4 row: CRLF line endings', () => {
  assert.deepEqual(activeRow(REG('- [ ] 005 — crlf — x').replace(/\n/g, '\r\n')), { id: '005', slug: 'crlf' })
})
test('096-R4 row: a checkpoint row adds "Checkpoint next"', () => {
  const row = activeRow(REG('- [ ] H6 — integration-hardening — checkpoint — x'))
  assert.deepEqual(row, { id: 'H6', slug: 'integration-hardening' })
  assert.equal(bandText(row!, []), 'Next: H6 integration-hardening   Checkpoint next')
})

const BRIEF = `quality gates: 27 flags, 10 files skipped from 2026-10-03 — .claude/state/quality-gates/latest.md
⚠ MAINTENANCE DUE (2):
  · full test suite (unit + integration + E2E + visual regression) — 10 spec(s) ticked since 2026-10-02 (due at 1)
  · mutation kill rate (Stryker) — 13 spec(s) ticked since 2026-10-01 (due at 5)
  Run now: bash scripts/project-maintenance.sh --full --suite`
test('096-R4 maintenance: two due, short names', () => {
  assert.deepEqual(maintenanceDue(BRIEF), ['suite', 'mutation'])
})
test('096-R4 maintenance: none due, garbage, empty', () => {
  assert.deepEqual(maintenanceDue('quality gates: 0 flags'), [])
  assert.deepEqual(maintenanceDue('\u0000\u0001 not output'), [])
  assert.deepEqual(maintenanceDue(''), [])
})
test('096-R4 maintenance: an unknown job by its first word', () => {
  assert.deepEqual(maintenanceDue('  · secrets scan (gitleaks) — 3 days'), ['secrets'])
})
test('096-R4 band: due, none, unknown', () => {
  const row = { id: '097', slug: 'prompt-audit-cleanup' }
  assert.equal(bandText(row, ['suite', 'mutation']), 'Next: 097 prompt-audit-cleanup   Due: suite, mutation')
  assert.equal(bandText(row, []), 'Next: 097 prompt-audit-cleanup')
  assert.equal(bandText(row, null), 'Next: 097 prompt-audit-cleanup   Due: unknown')
})
