# CI/CD and deployment

## Cluster infrastructure (live4.se)

All projects are hosted on a Docker Swarm cluster on Azure:

| Node           | Public IP      | Internal IP | Role    |
| -------------- | -------------- | ----------- | ------- |
| live4-mgr-01   | 51.12.246.54   | 10.2.0.4    | Manager |
| live4-wkr-01   | 51.12.246.201  | 10.2.0.5    | Worker  |
| live4-wkr-02   | 51.12.247.158  | 10.2.0.6    | Worker  |
| live4-wkr-03   | 51.12.247.189  | 10.2.0.7    | Worker  |

**SSH access:**

```bash
ssh -i ~/ubuntu/ubuntu ubuntu@51.12.246.54     # Manager (port 22 or 7222)
```

**Private Docker Registry:** `10.2.0.4:5000`
**NFS mount:** `/mnt/nfs/` (shared storage across all nodes — for static seed data, build artifacts, compose files, and read-only assets ONLY. **Never** for SQLite, Redis with persistence, or any write workload — see `.claude/docs/spot-architecture.md` and `.claude/rules/sqlite.md`.)
**Reverse proxy:** Nginx Proxy Manager (external overlay network `nginx_npm_network`)
**Worker fleet:** Workers are Azure Spot VMs and can be evicted with ~30 seconds notice. Stateful services MUST pin to a non-spot worker labeled `tier=stateful` — see `.claude/docs/spot-architecture.md`.

## Pipeline architecture

```text
GitHub Actions (workflow_dispatch with confirmation)
         │
    Build & Test (.NET)
         │
    Stress Test (API + Frontend) ← MANDATORY, blocks deploy on failure
         │
    Docker Build (multi-stage: sdk → aspnet runtime)
         │
    Save images as TAR → SCP to manager (port 7222)
         │
    Load images → Push to private registry (10.2.0.4:5000)
         │
    Deploy via docker stack deploy (Swarm)
         │
    Verification + Mailjet email notification
```

## GitHub Actions workflow

- **Workflow file**: `.github/workflows/deploy-[projectname].yml`
- **Trigger**: `workflow_dispatch` with `confirm_deploy: "deploy"` as safety mechanism
- **Runner**: `ubuntu-latest`
- **Image tag**: `YYYY.MM.DD-HHMM` (datetime-based)

## Docker

- **Dockerfiles**: Multi-stage builds with `mcr.microsoft.com/dotnet/sdk:10.0` (build) and `aspnet:10.0` (runtime)
- **Registry**: Private at `10.2.0.4:5000`
- **Image naming**: `10.2.0.4:5000/2154/[projectname]_[service]:TAG`
- **Exposed ports**: Configured per project in docker-compose-stack

## Deploy configuration

- **Docker Compose/Stack**: `deploy/docker-compose-stack-[projectname].yml`
- **Deploy script**: `deploy/deploy_[projectname].sh` (replaces image placeholders, deploys stack, sends email)
- **Persistent storage**: `/mnt/nfs/[projectname]/` (databases, seed data, compose files)
- **Networks**: Project-internal overlay network + `nginx_npm_network` (external, for reverse proxy)

## Environment variables and secrets

**GitHub Secrets (configured in repo settings):**

- `LIVE4_SSH_KEY` — SSH key for deployment to the manager node
- `MAILJET_APIKEY` / `MAILJET_SECRET` — Email notifications on deploy

**Production environment (in appsettings.Production.json):**

- `ASPNETCORE_ENVIRONMENT=Production`
- `ConnectionStrings` point to `/data/` — mounted as a **local bind on the reserved (non-spot) `tier=stateful` node**, NOT NFS. SQLite write workloads on NFS corrupt during rolling restart and spot eviction. See `.claude/docs/spot-architecture.md`.

## Storage layout per project

**Shared NFS (`/mnt/nfs/[projectname]/`)** — read-only or build-time only:

```text
/mnt/nfs/[projectname]/
├── seed-data/                   # Initial seed data (read-only at runtime)
├── temp/                        # Staging for Docker images during deploy
└── docker-compose-stack-*.yml   # Resolved compose file
```

**Local bind on the reserved (non-spot) `tier=stateful` node (`/var/lib/[projectname]/`)** — runtime DBs:

```text
/var/lib/[projectname]/
├── db/
│   ├── app.db (+ shm, wal)      # Main database — local disk, not NFS
│   └── tenants/                 # Per-tenant databases (if applicable)
│       └── {tenantId}/tenant.db
└── files/                       # User uploads, cached files
```

The split exists because SQLite's WAL mode requires `mmap`'d shared memory which network filesystems do not provide consistently. Putting `app.db` on NFS is what causes the `SQLITE_IOERR (10)` corruption stories during rolling restarts.

## Docker Swarm commands

```bash
docker stack ls                                          # List all stacks
docker stack services [projectname]                      # Status for services
docker stack ps [projectname]                            # Detailed status
docker service logs [projectname]_[service]              # View logs
docker service update --image [new_image] [service]       # Update image
docker service rollback [projectname]_[service]          # Rollback
docker stack rm [projectname]                            # Remove stack
```

## New project — server preparation

When CI/CD is set up for a new project, inform the developer that the following must be created on the server:

**NFS directories (on the manager node) — read-only / build-time only:**

```bash
sudo mkdir -p /mnt/nfs/[projectname]
sudo mkdir -p /mnt/nfs/[projectname]/seed-data
sudo mkdir -p /mnt/nfs/[projectname]/temp
sudo chmod -R 777 /mnt/nfs/[projectname]
```

**Local DB directory on the reserved (non-spot) `tier=stateful` worker — for SQLite and other write workloads:**

```bash
# SSH into the reserved worker (the one labeled tier=stateful, spot=false)
sudo mkdir -p /var/lib/[projectname]/db
sudo mkdir -p /var/lib/[projectname]/db/tenants    # If multi-tenant
sudo mkdir -p /var/lib/[projectname]/files
sudo chown -R 1000:1000 /var/lib/[projectname]    # Match the container user
```

If no node is yet labeled `tier=stateful`, label one before continuing:

```bash
docker node update --label-add tier=stateful --label-add spot=false live4-wkr-01
```

**Project files that must be created:**

- `deploy/docker-compose-stack-[projectname].yml` — Docker Swarm stack definition
- `deploy/deploy_[projectname].sh` — Deploy script with image placeholder replacement and email notification
- `deploy/update-seed-data.sql` — SQL for initial seed data (if applicable)
- `.github/workflows/deploy-[projectname].yml` — GitHub Actions workflow
- `src/[Service]/Dockerfile` — Multi-stage Dockerfile per service
- `.dockerignore` — Exclude `.git/`, `bin/`, `obj/`, `*.db`, `tests/` etc.
- `src/[Service]/appsettings.Production.json` — Production configuration with `/data/` paths

**GitHub repo settings:**

- Add secret `LIVE4_SSH_KEY` (SSH key for the manager node)
- Add secrets for email notifications (`MAILJET_APIKEY`, `MAILJET_SECRET`)

## Deployment checklist

1. All tests pass locally
2. **Stress tests pass** — both API and frontend (see `.claude/docs/stress-testing.md`)
3. Code is pushed to the correct branch
4. Workflow triggered manually with `confirm_deploy: "deploy"`
5. Verify that images were built and pushed to registry
6. Check Docker Swarm services: `docker stack services [projectname]`
7. Verify email notification (Mailjet)
8. Test the application via its public URL
