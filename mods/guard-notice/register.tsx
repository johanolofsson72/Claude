// The guard-notice mod (spec 096). Staged in the template under names that do not load; the developer
// installs it with `! bash scripts/install-guard-notice-mod.sh` (spec 095a M2).
//
// It never changes a tool call: every hook passes the call on and returns what came back, and a
// failure of its own is swallowed so a deny can never be lost to it.
import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import type { Band } from '../types'
import { activeRow, bandText, denyText, denyToast, failOpenNotices, failOpenToast, maintenanceDue, Seen } from './lib'

const band = atom({ plugin: 'guard-notice', key: 'band' } as const, null)
const isHidden = atom({ plugin: 'guard-notice', key: 'isHidden' } as const, false)

const MAINTENANCE_EVERY_MS = 10 * 60 * 1000

// Module state starts over on a reload; the band itself lives in $.state.
const seen = new Seen()
const session = { cwd: '', due: [] as string[] | null, dueAt: -Infinity }

async function refresh($: EngineInterface): Promise<void> {
  try {
    let index: string
    try {
      index = await $.fs.read(`${session.cwd}/specs/INDEX.md`)
    } catch {
      await update($, band, () => null)            // no register: no band
      return
    }
    const row = activeRow(index)
    const now = await $.clock.now()
    if (now - session.dueAt >= MAINTENANCE_EVERY_MS) {
      session.dueAt = now
      try {
        const r = await $.process.run(['bash', 'scripts/maintenance-due.sh', '--brief'],
          { cwd: session.cwd, timeoutMs: 20_000 })
        session.due = r.exitCode === 0 || r.stdout ? maintenanceDue(r.stdout) : null
      } catch {
        session.due = null
      }
    }
    const value: Band | null = row ? { text: bandText(row, session.due) } : null
    await update($, band, () => value)
  } catch {
    // the band is ambient: a failure leaves the last text in place
  }
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    const out = await next(e)
    session.cwd = e.cwd
    if (e.isInteractive) void refresh($)
    return out
  })

  on('turn.complete', async ($, e, next) => {
    const out = await next(e)
    void refresh($)
    return out
  })

  on('tool.call', async ($, e, next) => {
    const r = await next(e)
    try {
      for (const n of failOpenNotices(r.context)) {
        if (seen.first(`fail-open:${n.guard}:${n.cause}`)) $.ui.toast(failOpenToast(n), { timeoutMs: 6000 })
      }
      const t = denyToast(denyText(r))
      if (t && seen.first(`deny:${t}`)) $.ui.toast(t)
    } catch {
      // never lose the result to the mod's own error
    }
    return r
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const value = await read($, band)
    if (value === null || e.props.hasSurvey || (await read($, isHidden))) return next(e)
    const { Box, Button, Text } = $.ui.resolve(e)
    return (
      <Box>
        <Text dimColor wrap="truncate-end">{value.text}   </Text>
        <Button key="hide" label="Hide" onPress={() => update($, isHidden, () => true)} />
      </Box>
    )
  })
}
