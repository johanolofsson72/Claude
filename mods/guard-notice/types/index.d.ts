// The guard-notice mod's $.state contract (spec 096): the band's text, and whether it is hidden.
export type Band = { text: string }

declare module 'claude-code' {
  interface PluginState {
    'guard-notice': { band: Band | null; isHidden: boolean }
  }
}
