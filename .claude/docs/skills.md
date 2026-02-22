
## .claude/docs/skills.md

```markdown
# Skills

Claude ska automatiskt installera och använda skills från `~/.claude/skills/`. Vid sessionsstart, kontrollera att följande skills finns installerade. Om någon saknas, klona repot.

## Obligatoriska skills (topp 10, sorterade efter popularitet)

| # | Skill | Repo | Stjärnor | Beskrivning |
|---|---|---|---|---|
| 1 | **anthropics/skills** | `anthropics/skills` | ~61k | Anthropics officiella skills-samling (inkl. frontend-design, owasp-security, playwright m.fl.) |
| 2 | **superpowers** | `obra/superpowers` | ~57k | Strukturerat senior-utvecklar-arbetsflöde med planering, TDD och kodgranskning |
| 3 | **ui-ux-pro-max-skill** | `nextlevelbuilder/ui-ux-pro-max-skill` | ~33k | AI-driven designintelligens med 57 UI-stilar, 95 färgpaletter, 56 fontpar |
| 4 | **planning-with-files** | `OthmanAdi/planning-with-files` | ~10k | Manus-liknande planering med persistenta markdown-filer |
| 5 | **marketingskills** | `coreyhaines31/marketingskills` | ~9k | 26 marketing-skills: CRO, copywriting, SEO, analytics |
| 6 | **context-engineering** | `muratcankoylan/Agent-Skills-for-Context-Engineering` | ~8k | Context engineering, multi-agent-arkitekturer |
| 7 | **obsidian-skills** | `kepano/obsidian-skills` | ~7k | Officiella agent-skills för Obsidian |
| 8 | **claude-scientific-skills** | `K-Dense-AI/claude-scientific-skills` | ~6k | 140+ vetenskapliga skills |
| 9 | **antfu/skills** | `antfu/skills` | ~4k | Anthony Fu:s kurerade skills med best practices |
| 10 | **dev-browser** | `SawyerHood/dev-browser` | ~3k | Webbläsarautomation — ger agenten kontroll över Chrome-flikar |

## Installationskommando

```bash
declare -A SKILL_REPOS=(
  [anthropics-skills]="anthropics/skills"
  [superpowers]="obra/superpowers"
  [ui-ux-pro-max-skill]="nextlevelbuilder/ui-ux-pro-max-skill"
  [planning-with-files]="OthmanAdi/planning-with-files"
  [marketingskills]="coreyhaines31/marketingskills"
  [context-engineering]="muratcankoylan/Agent-Skills-for-Context-Engineering"
  [obsidian-skills]="kepano/obsidian-skills"
  [claude-scientific-skills]="K-Dense-AI/claude-scientific-skills"
  [antfu-skills]="antfu/skills"
  [dev-browser]="SawyerHood/dev-browser"
)

for skill in "${!SKILL_REPOS[@]}"; do
  if [ ! -d "$HOME/.claude/skills/$skill" ]; then
    echo "Installerar skill: $skill"
    git clone "https://github.com/${SKILL_REPOS[$skill]}.git" "$HOME/.claude/skills/$skill"
  fi
done