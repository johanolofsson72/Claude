---
name: deploy-checklist
description: Pre-deployment verification checklist for Docker Swarm deployments to Azure. Use before deploying to production. Trigger words include deploy, driftsätt, release, produktion, go live.
disable-model-invocation: true
allowed-tools: Bash, Read, Grep, Glob
---

# Deploy Checklist

Pre-deployment verification for Docker Swarm on Azure (live4.se).

## Verification steps

Run each step and report pass/fail:

### 1. Build verification
```bash
dotnet build --configuration Release
```

### 2. Test verification
```bash
dotnet test --configuration Release
```

### 3. Git status
- All changes committed?
- On correct branch?
- Up to date with remote?

### 4. Configuration check
- No secrets in appsettings.json (only in environment variables)
- Connection strings use production values via env vars
- HTTPS enforced
- CORS configured correctly

### 5. Docker verification
```bash
docker build -t app:test .
```

### 6. Migration check
- Any pending EF Core migrations?
- Migration reviewed (Up and Down methods)?

## Report

| Step | Status | Notes |
|------|--------|-------|
| Build | PASS/FAIL | |
| Tests | PASS/FAIL | X passed, Y failed |
| Git | PASS/FAIL | |
| Config | PASS/FAIL | |
| Docker | PASS/FAIL | |
| Migrations | PASS/FAIL/N/A | |

**Recommendation**: READY TO DEPLOY / NOT READY (with blocking issues)

For deployment commands and infrastructure details, read `${CLAUDE_SKILL_DIR}/../../docs/deployment.md`.
