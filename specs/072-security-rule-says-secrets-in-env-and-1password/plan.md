# Plan — 072

1. Guard first: scripts/test-doc-secrets-guidance.sh, confirm red at HEAD naming the five files.
2. docs/security.md: fix the fundamental-rules line; add § Secrets (why, local with op run, pipe into docker secret create, stack-file secrets:, KeyPerFile, *_FILE for images, no ENV/ARG, rotation).
3. rules/security.md, deploy-checklist, deployment.md, project-wizard Q39: one line each, pointing at § Secrets.
4. List the guard in TEMPLATE_ONLY_SCRIPTS; verify guard green, sabotage arms, --unlisted tests, humanizer pass on the prose.
