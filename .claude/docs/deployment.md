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
**NFS mount:** `/mnt/nfs/` (shared storage across all nodes)
**Reverse proxy:** Nginx Proxy Manager (external overlay network `nginx_npm_network`)

## Pipeline architecture

```text
GitHub Actions (workflow_dispatch with confirmation)
         │
    Build & Test (.NET)
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
- `ConnectionStrings` point to `/data/` (mounted via NFS)

## NFS structure per project

```text
/mnt/nfs/[projectname]/
├── app.db (+ shm, wal)          # Main database
├── tenants/                     # Per-tenant databases (if applicable)
│   └── {tenantId}/tenant.db
├── seed-data/                   # Initial seed data
├── temp/                        # Staging for Docker images
└── docker-compose-stack-*.yml   # Resolved compose file
```

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

**NFS directories (on the manager node):**

```bash
sudo mkdir -p /mnt/nfs/[projectname]
sudo mkdir -p /mnt/nfs/[projectname]/seed-data
sudo mkdir -p /mnt/nfs/[projectname]/temp
sudo mkdir -p /mnt/nfs/[projectname]/tenants    # If multi-tenant
sudo chmod -R 777 /mnt/nfs/[projectname]
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
2. Code is pushed to the correct branch
3. Workflow triggered manually with `confirm_deploy: "deploy"`
4. Verify that images were built and pushed to registry
5. Check Docker Swarm services: `docker stack services [projectname]`
6. Verify email notification (Mailjet)
7. Test the application via its public URL
