---
paths:
  - "**/Program.cs"
  - "**/docker-compose*.yml"
  - "**/Controllers/**/*.cs"
  - "**/Endpoints/**/*.cs"
  - "**/Services/**/*.cs"
  - "**/Workers/**/*.cs"
---

# Spot resilience rules

Production sites run on Azure Spot VMs as Swarm workers. Any worker can be evicted with ~30 seconds notice, so containers must assume they will be killed mid-operation. The rules below are non-negotiable for any service deployed to the live4 cluster.

## Architecture (BLOCKING)

Stateful workloads (SQLite, Redis with persistence, anything with local files) must NOT run on a spot node. The volume dies with the node. Every project must either:

1. Pin stateful services to a reserved (non-spot) node via `node.labels.tier == stateful`, or
2. Replicate state via LiteFS / Litestream / managed Postgres.

See `.claude/docs/spot-architecture.md` for the three reference architectures and full compose templates.

## Required components in every service

### 1. Spot eviction watcher

Polls Azure's Instance Metadata Service (IMDS) for `Preempt` / `Terminate` / `Reboot` events and triggers `IHostApplicationLifetime.StopApplication()` so the drain starts ~20 seconds earlier than waiting for `SIGTERM`.

```csharp
public sealed class SpotEvictionWatcher(
    IHostApplicationLifetime lifetime,
    ILogger<SpotEvictionWatcher> log,
    HttpClient http) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken ct)
    {
        http.DefaultRequestHeaders.Add("Metadata", "true");
        const string url = "http://169.254.169.254/metadata/scheduledevents?api-version=2020-07-01";

        while (!ct.IsCancellationRequested)
        {
            try
            {
                var doc = await http.GetFromJsonAsync<JsonElement>(url, ct);
                if (doc.TryGetProperty("Events", out var events))
                {
                    foreach (var ev in events.EnumerateArray())
                    {
                        var type = ev.GetProperty("EventType").GetString();
                        if (type is "Preempt" or "Terminate" or "Reboot")
                        {
                            log.LogWarning("Spot eviction notice received: {Type}. Draining.", type);
                            lifetime.StopApplication();
                            return;
                        }
                    }
                }
            }
            catch (Exception ex) { log.LogDebug(ex, "IMDS poll failed"); }

            await Task.Delay(TimeSpan.FromSeconds(10), ct);
        }
    }
}
```

Register in DI:

```csharp
builder.Services.AddHttpClient<SpotEvictionWatcher>();
builder.Services.AddHostedService<SpotEvictionWatcher>();
```

The watcher is a no-op outside Azure (IMDS calls fail and are caught), so it is safe to keep in dev environments.

### 2. Graceful drain

Order matters. The first thing to do on shutdown is fail readiness so the load balancer drains traffic, then finish in-flight requests, then flush state. Reverse this order and you serve errors during shutdown.

```csharp
public sealed class GracefulDrain(
    IReadinessGate readiness,
    ILogger<GracefulDrain> log) : IHostedService
{
    public Task StartAsync(CancellationToken _) => Task.CompletedTask;

    public async Task StopAsync(CancellationToken _)
    {
        readiness.MarkUnready();
        log.LogInformation("Readiness flipped to unready — waiting for LB drain");
        await Task.Delay(TimeSpan.FromSeconds(3));
    }
}
```

Configure Kestrel to allow in-flight work to finish:

```csharp
builder.WebHost.UseShutdownTimeout(TimeSpan.FromSeconds(20));
```

In compose, give the container time to checkpoint and drain:

```yaml
deploy:
  update_config:
    order: stop-first
  stop_grace_period: 30s
```

### 3. Idempotent writes

Every endpoint that mutates state must accept an `Idempotency-Key` header (UUID v4, client-generated). The server stores `(key, response_hash, expires_at)` and returns the cached response on replay.

```csharp
app.MapPost("/orders", async (
    Order order,
    [FromHeader(Name = "Idempotency-Key")] Guid key,
    IIdempotencyStore store) =>
{
    if (await store.TryReplay(key) is { } cached) return cached;
    var result = await CreateOrder(order);
    await store.Save(key, result);
    return result;
});
```

Without idempotency, retries from the LB or the client after a spot kill silently double-charge users.

### 4. Outbox for reliable side effects

Anything that triggers a side effect (email, webhook, message queue publish) must be written to an `outbox` table in the same DB transaction as the state change. A separate worker drains the outbox. Spot kills mid-publish? The next worker run picks up the unsent row. No "fire and forget" calls allowed.

## Forbidden patterns

- A service running on the spot tier that holds authoritative state in `IMemoryCache` or in-process buffers without a persistent backing store. Recoverable cache (read-through, derivable) is fine; authoritative is not.
- A POST/PUT/PATCH/DELETE endpoint without idempotency support.
- A side-effect call (email, webhook, queue publish) outside the outbox.
- A `docker-compose*.yml` with a stateful service but no `placement.constraints` block.
- A `docker-compose*.yml` without `stop_grace_period: 30s` on services that write to SQLite.
- `update_config.order: start-first` on a stateful service. Use `stop-first` so the old container fully exits and checkpoints before the new one opens the DB file.

## Healthchecks

Healthchecks must hit the actual dependency, not just `/health`. A process that returns HTTP 200 while its DB connection is broken lies to Swarm and gets traffic it cannot serve.

```dockerfile
HEALTHCHECK --interval=10s --timeout=3s --start-period=20s --retries=3 \
  CMD wget -qO- http://localhost:8080/health/db || exit 1
```

`/health/db` runs `SELECT 1 FROM sqlite_master LIMIT 1` (or equivalent) against the connection pool. `/health/live` (process is alive) and `/health/ready` (ready to receive traffic, flips on drain) are separate endpoints.
