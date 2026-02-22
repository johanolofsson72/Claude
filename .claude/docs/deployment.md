# CI/CD och deployment

## Klusterinfrastruktur (live4.se)

Alla projekt driftas på ett Docker Swarm-kluster på Azure:

| Nod            | Publik IP      | Intern IP | Roll    |
| -------------- | -------------- | --------- | ------- |
| live4-mgr-01   | 51.12.246.54   | 10.2.0.4  | Manager |
| live4-wkr-01   | 51.12.246.201  | 10.2.0.5  | Worker  |
| live4-wkr-02   | 51.12.247.158  | 10.2.0.6  | Worker  |
| live4-wkr-03   | 51.12.247.189  | 10.2.0.7  | Worker  |

**SSH-åtkomst:**

```bash
ssh -i ~/ubuntu/ubuntu ubuntu@51.12.246.54     # Manager (port 22 eller 7222)
```

**Privat Docker Registry:** `10.2.0.4:5000`
**NFS-mount:** `/mnt/nfs/` (delad storage mellan alla noder)
**Reverse proxy:** Nginx Proxy Manager (extern overlay-nätverket `nginx_npm_network`)

## Pipeline-arkitektur

```text
GitHub Actions (workflow_dispatch med bekräftelse)
         │
    Build & Test (.NET)
         │
    Docker Build (multi-stage: sdk → aspnet runtime)
         │
    Spara images som TAR → SCP till manager (port 7222)
         │
    Load images → Push till privat registry (10.2.0.4:5000)
         │
    Deploy via docker stack deploy (Swarm)
         │
    Verifiering + Mailjet email-notifikation
```

## GitHub Actions workflow

- **Workflow-fil**: `.github/workflows/deploy-[projektnamn].yml`
- **Trigger**: `workflow_dispatch` med `confirm_deploy: "deploy"` som säkerhetsmekanism
- **Runner**: `ubuntu-latest`
- **Image-tagg**: `YYYY.MM.DD-HHMM` (datetime-baserad)

## Docker

- **Dockerfiler**: Multi-stage builds med `mcr.microsoft.com/dotnet/sdk:10.0` (build) och `aspnet:10.0` (runtime)
- **Registry**: Privat på `10.2.0.4:5000`
- **Image-namngivning**: `10.2.0.4:5000/2154/[projektnamn]_[service]:TAG`
- **Exponerade portar**: Konfigureras per projekt i docker-compose-stack

## Deploy-konfiguration

- **Docker Compose/Stack**: `deploy/docker-compose-stack-[projektnamn].yml`
- **Deploy-script**: `deploy/deploy_[projektnamn].sh` (ersätter image-placeholders, deployar stack, skickar email)
- **Persistent storage**: `/mnt/nfs/[projektnamn]/` (databaser, seed-data, compose-filer)
- **Nätverk**: Projekt-internt overlay-nätverk + `nginx_npm_network` (extern, för reverse proxy)

## Miljövariabler och secrets

**GitHub Secrets (konfigureras i repo-settings):**

- `LIVE4_SSH_KEY` — SSH-nyckel för deployment till manager-noden
- `MAILJET_APIKEY` / `MAILJET_SECRET` — Email-notifikationer vid deploy

**Produktionsmiljö (i appsettings.Production.json):**

- `ASPNETCORE_ENVIRONMENT=Production`
- `ConnectionStrings` pekar på `/data/` (monterad via NFS)

## NFS-struktur per projekt

```text
/mnt/nfs/[projektnamn]/
├── app.db (+ shm, wal)          # Huvuddatabas
├── tenants/                     # Per-tenant databaser (om tillämpligt)
│   └── {tenantId}/tenant.db
├── seed-data/                   # Initial seed-data
├── temp/                        # Staging för Docker images
└── docker-compose-stack-*.yml   # Resolved compose-fil
```

## Docker Swarm-kommandon

```bash
docker stack ls                                          # Lista alla stacks
docker stack services [projektnamn]                      # Status för services
docker stack ps [projektnamn]                            # Detaljerad status
docker service logs [projektnamn]_[service]              # Visa loggar
docker service update --image [ny_image] [service]       # Uppdatera image
docker service rollback [projektnamn]_[service]          # Rollback
docker stack rm [projektnamn]                            # Ta bort stack
```

## Nytt projekt — serverförberedelser

När CI/CD sätts upp för ett nytt projekt, informera utvecklaren om att följande måste skapas på servern:

**NFS-kataloger (på manager-noden):**

```bash
sudo mkdir -p /mnt/nfs/[projektnamn]
sudo mkdir -p /mnt/nfs/[projektnamn]/seed-data
sudo mkdir -p /mnt/nfs/[projektnamn]/temp
sudo mkdir -p /mnt/nfs/[projektnamn]/tenants    # Om multi-tenant
sudo chmod -R 777 /mnt/nfs/[projektnamn]
```

**Projektfiler som måste skapas:**

- `deploy/docker-compose-stack-[projektnamn].yml` — Docker Swarm stack-definition
- `deploy/deploy_[projektnamn].sh` — Deploy-script med image-placeholder-ersättning och email-notifikation
- `deploy/update-seed-data.sql` — SQL för initial seed-data (om tillämpligt)
- `.github/workflows/deploy-[projektnamn].yml` — GitHub Actions workflow
- `src/[Service]/Dockerfile` — Multi-stage Dockerfile per service
- `.dockerignore` — Exkludera `.git/`, `bin/`, `obj/`, `*.db`, `tests/` etc.
- `src/[Service]/appsettings.Production.json` — Produktionskonfiguration med `/data/`-sökvägar

**GitHub repo-settings:**

- Lägg till secret `LIVE4_SSH_KEY` (SSH-nyckel för manager-noden)
- Lägg till secrets för email-notifikationer (`MAILJET_APIKEY`, `MAILJET_SECRET`)

## Deployment-checklista

1. Alla tester passerar lokalt
2. Koden är pushad till rätt branch
3. Workflow triggad manuellt med `confirm_deploy: "deploy"`
4. Verifiera att images byggts och pushats till registry
5. Kontrollera Docker Swarm services: `docker stack services [projektnamn]`
6. Verifiera email-notifikation (Mailjet)
7. Testa applikationen via dess publika URL
