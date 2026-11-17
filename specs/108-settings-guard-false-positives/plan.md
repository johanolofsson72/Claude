# Plan — 108

| R | Where in `scripts/settings_guard.py` | Check |
|---|---|---|
| R1 | `pipe_filter(words)` replaces the bare `STDOUT_FILTERS` test in `read_flows` | `[108]` sort/uniq/rev/tac/paste/sed -n allowed; `--compress-program`, `uniq - out`, `sed -i` denied |
| R2 | `word_hit` dots test | `[108]` `//` after a lost cd allowed; `cd "$X" && rm .` denied |
| R3 | every `settings-bash` return gets a cause; `settings-edit-guard-hook.sh` prints `Rule:` | `[108]` deny reason holds `Rule:` |
| R4 | `word_hit` fragment loop, `FRAGMENT_ANCHOR` | `[108]` python regex `.*?` allowed; `python3 -c` writing `.c*/s*.json` and `bash -c 'cp x .*/settings.json'` denied |
| R5 | `chain_bases`; `split_commands` gains `seps` | `[108]` scratch fixture allowed; `;`, `\|\|`, `( )` controls denied |
| R6 | `KEYWORDS` passed over in `command_word` and `reads` | `[108]` for-do grep allowed; `then cd .claude && printf > settings.json` denied |
| R7 | `script_data(words)` → `word_hit(fragments=False)` | `[108]` finding.sh prose allowed; single-path argument and `bash -c` denied |
| R8 | `pattern_indices` finds find -exec grep | `[108]` `find . -exec grep '[a-z]*' {} +` allowed; `find . -name settings.json -delete` denied |
| R9 | `scripts/test-settings-edit-guard.sh` | this suite, sensitive-file and bash-write suites, then the template suite |

No new trust boundary. Every rule narrows a deny, and each has a control in the same block.
