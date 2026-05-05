# Spot architecture (Azure spot workers + stateful workloads)

This doc covers how to deploy stateful services (SQLite, Redis with persistence, anything with local files) on a Docker Swarm cluster where the workers are Azure Spot VMs. Spot eviction can take a worker down with ~30 seconds notice, so the architecture has to assume any node can vanish.

The companion rules are `.claude/rules/sqlite.md` (DB pragmas and lifecycle) and `.claude/rules/spot-resilience.md` (eviction watcher, drain, idempotency, outbox). Read those first if you have not.

## The three reference architectures

Pick one based on cost and HA needs. Every project must be classified into one of these three.

### Architecture A — Reserved DB node + spot app tier

The cheapest viable option and the default for new live4 projects. One reserved (non-spot) worker is labeled `tier=stateful`. All SQLite-using services pin there. Stateless services run on the spot fleet.

**Cost:** roughly +$70/mo for one reserved D2s_v5 vs all-spot. Trivial compared to a corruption outage.

**When to use:** RPO/RTO of "a few minutes of restart" is acceptable. Single-region site. Read and write traffic both modest.

**Compose template:**

```yaml
# Stateful service — pinned to the reserved node
services:
  api:
    image: 10.2.0.4:5000/2154/myproject_api:${TAG}
    deploy:
      replicas: 1
      placement:
        constraints:
          - node.labels.tier == stateful
          - node.labels.spot == false
      update_config:
        order: stop-first
        parallelism: 1
        failure_action: rollback
      rollback_config:
        order: stop-first
      restart_policy:
        condition: any
        delay: 5s
        max_attempts: 3
    stop_grace_period: 30s
    volumes:
      - type: bind
        source: /var/lib/myproject/db
        target: /data
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://localhost:8080/health/db"]
      interval: 10s
      timeout: 3s
      start_period: 20s
      retries: 3
    networks: [internal, nginx_npm_network]

  # Stateless service — runs on spot
  worker:
    image: 10.2.0.4:5000/2154/myproject_worker:${TAG}
    deploy:
      replicas: 3
      placement:
        preferences:
          - spread: node.hostname
      update_config:
        order: start-first
        parallelism: 1
        failure_action: rollback
    stop_grace_period: 20s
    networks: [internal]

networks:
  internal:
  nginx_npm_network:
    external: true
```

**Node setup (one-time on the reserved worker):**

```bash
docker node update --label-add tier=stateful --label-add spot=false live4-wkr-01
```

For the spot workers:

```bash
docker node update --label-add spot=true live4-wkr-02
docker node update --label-add spot=true live4-wkr-03
```

**Volume:** `/var/lib/myproject/db` is a bind to the local filesystem of the reserved node, NOT NFS. The Azure managed disk attached to the VM provides durability across VM restarts. Snapshots run via Azure Backup, not via the application.

### Architecture B — LiteFS for read-heavy workloads

[LiteFS](https://github.com/superfly/litefs) is a FUSE filesystem that replicates SQLite. The primary runs on the reserved node, replicas run on spot nodes and serve read traffic locally. Writes are forwarded to the primary via LiteFS proxy.

**When to use:** read:write ratio heavily skewed to reads (typical CMS, marketing sites with mostly cached content), and you want read scaling across the spot fleet without splitting the DB.

**Tradeoffs:** writes still depend on the primary node being up. Lose the primary and writes fail until LiteFS election picks a new primary (Consul-backed, ~10 seconds). Reads keep working on replicas.

**Setup pointers:** the LiteFS sidecar container runs alongside the app container, mounts FUSE at `/litefs`, and the app opens `/litefs/app.db` exactly as it would a local SQLite file. Replication is asynchronous; the app does not need to know.

For full compose examples see the [LiteFS Docker guide](https://fly.io/docs/litefs/getting-started-docker/).

### Architecture C — State out of the cluster

Move the database to [Azure Database for PostgreSQL Flexible Server](https://learn.microsoft.com/en-us/azure/postgresql/flexible-server/). The cluster becomes pure stateless and can lose 100% of its workers without data loss.

**Cost:** B1ms (1 vCPU, 2 GB RAM) is ~$13/mo without HA, ~$30/mo with zone-redundant HA.

**When to use:** the project does not have a hard SQLite-specific requirement (embedded analytics, plugin ecosystems, single-file portability). For "we picked SQLite because it was easy", this is usually the right answer.

**Migration cost:** EF Core change provider, regenerate migrations, update connection string. Two days of work for a typical project. Saves indefinitely on operational complexity.

## Volume rules of thumb

| Volume                                   | Spot-safe | OK for SQLite writes |
|------------------------------------------|-----------|----------------------|
| Local bind on a reserved (non-spot) node | Yes       | Yes                  |
| Local bind on a spot node                | No        | Never                |
| Azure managed disk on a reserved node    | Yes       | Yes                  |
| Azure Files (SMB, any tier)              | Yes       | No (`mmap` unsafe)   |
| NFS (any version)                        | Yes       | No (`mmap` unsafe)   |
| Blob via `blobfuse2`                     | Yes       | No (eventual)        |
| Postgres / managed DB                    | Yes       | N/A                  |

The cardinal rule: **any network filesystem is unsafe for SQLite write workloads.** No flag, no version, no clever lock fixes this. The failure mode is silent corruption discovered later.

## Required application components

Every service deployed to the cluster must include the following. Code is in `.claude/rules/spot-resilience.md`; this section explains why each piece exists.

### Spot eviction watcher

Polls the Azure IMDS scheduled-events endpoint every 10 seconds. When a `Preempt` event appears, it triggers application shutdown immediately instead of waiting for `SIGTERM`. The eviction notice usually arrives 20-30 seconds before the kill, so this gives the drain pipeline a head start.

Outside Azure (dev, CI), the IMDS call fails quietly and the watcher is a no-op.

### Graceful drain

The shutdown order matters:

1. **Mark readiness as unready.** The load balancer notices on its next health probe (~3 seconds) and stops sending new requests.
2. **Wait for in-flight requests to finish.** Kestrel's shutdown timeout (configured to 20s) handles this automatically.
3. **Checkpoint the SQLite WAL.** This is what prevents the next container from opening a half-written WAL.
4. **Exit.**

Reverse this order and you will serve `502 Bad Gateway` to clients during shutdown because the LB does not know to stop sending traffic.

### Idempotent mutation endpoints

Every POST/PUT/PATCH/DELETE accepts an `Idempotency-Key` header. The server stores `(key, response_hash, expires_at)` for 24 hours. A retry with the same key returns the cached response.

Without this, a client that retries after a spot kill mid-write will double-process the operation. For payments and "send email" actions, this is a P0 user-facing bug.

### Outbox pattern for side effects

State changes that trigger external side effects (email, webhook, queue publish) write the *intent* to an `outbox` table inside the same DB transaction. A separate worker drains the outbox. If a spot kill cuts off the publish, the next worker run picks up the unsent row.

Schema sketch:

```sql
CREATE TABLE outbox (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    occurred_at   TEXT NOT NULL,
    type          TEXT NOT NULL,
    payload       BLOB NOT NULL,
    processed_at  TEXT,
    attempt_count INTEGER NOT NULL DEFAULT 0,
    next_attempt  TEXT NOT NULL
);
CREATE INDEX idx_outbox_pending ON outbox(next_attempt) WHERE processed_at IS NULL;
```

Worker drains rows where `processed_at IS NULL AND next_attempt <= now()`, exponential backoff on failure, mark `processed_at = now()` on success.

## Healthcheck strategy

Three separate endpoints, each answering one question:

| Endpoint          | Question                          | Used by                              |
|-------------------|-----------------------------------|--------------------------------------|
| `/health/live`    | Is the process alive?             | Container restart policy             |
| `/health/ready`   | Should the LB send me traffic?    | Load balancer / ingress              |
| `/health/db`      | Is the DB connection working?     | Swarm `HEALTHCHECK` for replacement  |

`/health/ready` flips to `503` immediately on shutdown via the readiness gate so the LB drains. `/health/live` keeps returning `200` until the process is truly dead. `/health/db` runs `SELECT 1` against the actual connection pool. A process that holds a broken DB connection but a healthy HTTP listener is the worst kind of zombie.

Implementation:

```csharp
app.MapHealthChecks("/health/live", new HealthCheckOptions
{
    Predicate = _ => false  // no checks, just confirms process is alive
});

app.MapHealthChecks("/health/ready", new HealthCheckOptions
{
    Predicate = check => check.Tags.Contains("ready")
});

app.MapHealthChecks("/health/db", new HealthCheckOptions
{
    Predicate = check => check.Tags.Contains("db")
});
```

Register the DB check with EF Core or `Microsoft.Data.Sqlite`:

```csharp
builder.Services
    .AddHealthChecks()
    .AddCheck<ReadinessCheck>("readiness", tags: ["ready"])
    .AddSqlite(connectionString, name: "sqlite", tags: ["db"]);
```

## Migration path for existing projects

If an existing project currently has SQLite on `/mnt/nfs/...`, run the migration in this order:

1. **Inventory the writes.** Find every endpoint and worker that writes to the DB. List them.
2. **Decide on architecture A or C.** B (LiteFS) is rarely the right first move during a migration.
3. **Provision the target.** For A: label one worker as `tier=stateful, spot=false` and create `/var/lib/<project>/db`. For C: provision the Postgres flexible server.
4. **Snapshot the current DB.** `cp /mnt/nfs/<project>/app.db /backup/...` while the service is down.
5. **Update the compose file** with placement constraints, `stop_grace_period`, and the new volume.
6. **Add the eviction watcher and graceful drain** to the service if missing.
7. **Deploy with `order: stop-first`** so the old container fully exits before the new one opens the DB.
8. **Remove the NFS mount** from the deployment manifest. Leaving it as a fallback invites someone to point the connection string at it again.

Do not run both architectures in parallel "just in case". Pick one, switch, verify, delete the other.
