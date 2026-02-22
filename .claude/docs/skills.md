# Skills

Claude ska automatiskt installera och använda skills från `~/.claude/skills/`. Vid sessionsstart, kontrollera att följande skills finns installerade. Om någon saknas, klona repot.

## Obligatoriska skills (topp 11, sorterade efter popularitet)

| # | Skill | Repo | Stjärnor | Beskrivning |
| --- | --- | --- | --- | --- |
| 1 | **anthropics/skills** | `anthropics/skills` | ~73k | Anthropics officiella skills-samling (frontend-design, owasp-security, playwright m.fl.) |
| 2 | **superpowers** | `obra/superpowers` | ~58k | Strukturerat senior-utvecklar-arbetsflöde med planering, TDD och kodgranskning |
| 3 | **ui-ux-pro-max-skill** | `nextlevelbuilder/ui-ux-pro-max-skill` | ~33k | AI-driven designintelligens med 57 UI-stilar, 95 färgpaletter, 56 fontpar |
| 4 | **planning-with-files** | `OthmanAdi/planning-with-files` | ~14k | Manus-liknande planering med persistenta markdown-filer |
| 5 | **obsidian-skills** | `kepano/obsidian-skills` | ~10k | Officiella agent-skills för Obsidian |
| 6 | **claude-scientific-skills** | `K-Dense-AI/claude-scientific-skills` | ~9k | 140+ vetenskapliga skills |
| 7 | **marketingskills** | `coreyhaines31/marketingskills` | ~9k | 26 marketing-skills: CRO, copywriting, SEO, analytics |
| 8 | **context-engineering** | `muratcankoylan/Agent-Skills-for-Context-Engineering` | ~9k | Context engineering, multi-agent-arkitekturer |
| 9 | **antfu/skills** | `antfu/skills` | ~4k | Anthony Fu:s kurerade skills med best practices |
| 10 | **dev-browser** | `SawyerHood/dev-browser` | ~4k | Webbläsarautomation — ger agenten kontroll över Chrome-flikar |
| 11 | **trailofbits/skills** | `trailofbits/skills` | ~3k | Säkerhetsforsknings-skills: sårbarhetsdetektering, audit-workflows |

## Installationskommando

```bash
declare -A SKILL_REPOS=(
  [anthropics-skills]="anthropics/skills"
  [superpowers]="obra/superpowers"
  [ui-ux-pro-max-skill]="nextlevelbuilder/ui-ux-pro-max-skill"
  [planning-with-files]="OthmanAdi/planning-with-files"
  [obsidian-skills]="kepano/obsidian-skills"
  [claude-scientific-skills]="K-Dense-AI/claude-scientific-skills"
  [marketingskills]="coreyhaines31/marketingskills"
  [context-engineering]="muratcankoylan/Agent-Skills-for-Context-Engineering"
  [antfu-skills]="antfu/skills"
  [dev-browser]="SawyerHood/dev-browser"
  [trailofbits-skills]="trailofbits/skills"
)

for skill in "${!SKILL_REPOS[@]}"; do
  if [ ! -d "$HOME/.claude/skills/$skill" ]; then
    echo "Installerar skill: $skill"
    git clone "https://github.com/${SKILL_REPOS[$skill]}.git" "$HOME/.claude/skills/$skill"
  fi
done
```

## Rekommenderade plugins

Installera LSP-plugins för kodnavigering (~50ms istället för ~45s textsök). Kör dessa kommandon vid projektstart:

```bash
# .NET-projekt — installera C# LSP
dotnet tool install --global csharp-ls 2>/dev/null || true
claude --print-only 2>/dev/null || /plugin install csharp-lsp@claude-plugins-official 2>/dev/null || true

# Om projektet har TypeScript/JavaScript
npm i -g typescript-language-server typescript 2>/dev/null || true
claude --print-only 2>/dev/null || /plugin install typescript-lsp@claude-plugins-official 2>/dev/null || true

# GitHub-integration
claude --print-only 2>/dev/null || /plugin install github@claude-plugins-official 2>/dev/null || true
```

Se @.claude/docs/workflows.md för fullständig plugin-dokumentation.
