---
paths:
  - "**/appsettings*.json"
  - "**/docker-compose*.yml"
  - "**/Program.cs"
  - "**/*Db*.cs"
  - "**/*Sqlite*.cs"
---

# SQLite rules

SQLite is the default database for this project's stack. Misconfiguring it on Docker Swarm with shared storage causes silent corruption that surfaces as `SQLITE_IOERR (10)` during rolling restarts or spot eviction. The rules below are mandatory.

## Volume placement (BLOCKING)

| Storage type                                         | SQLite write workload? |
|------------------------------------------------------|------------------------|
| Local bind mount on a non-spot node                  | Yes                    |
| Azure managed disk attached to a non-spot node       | Yes                    |
| Local bind mount on a spot node                      | **No** — disk dies with the node |
| NFS (any version, including v4 with locking)         | **No** — `mmap`/locking unsafe |
| SMB / Azure Files (any tier)                         | **No** — same `mmap`/locking issues |
| Blob via `blobfuse2` or any object-store FUSE        | **No** — eventual consistency |

The SQLite docs are explicit: WAL mode requires `mmap`'d shared memory (`-shm` file), and network filesystems do not provide cross-host `mmap` consistency. Two containers on different nodes that both open a WAL DB on NFS will eventually corrupt it. No flag, lock, or protocol version fixes this.

If the existing project has SQLite on NFS, treat it as a P0 architecture defect. Move the DB to a pinned non-spot node (see `.claude/docs/spot-architecture.md`) before adding any new feature that writes to it.

## Required pragmas (run once at startup)

```csharp
await conn.ExecuteAsync("PRAGMA journal_mode=WAL;");      // ONLY when on local disk
await conn.ExecuteAsync("PRAGMA synchronous=NORMAL;");    // WAL's correct partner
await conn.ExecuteAsync("PRAGMA busy_timeout=5000;");     // mandatory — non-zero
await conn.ExecuteAsync("PRAGMA foreign_keys=ON;");
await conn.ExecuteAsync("PRAGMA temp_store=MEMORY;");
await conn.ExecuteAsync("PRAGMA mmap_size=268435456;");   // 256 MB, local disk only
```

If the volume is forced to be a network filesystem (only valid for read-only DBs):

```csharp
await conn.ExecuteAsync("PRAGMA journal_mode=DELETE;");   // no -wal/-shm files
await conn.ExecuteAsync("PRAGMA synchronous=FULL;");      // pay full fsync cost
```

`busy_timeout=0` (the default) is forbidden. Concurrent writes will throw `SQLITE_BUSY` instead of waiting.

## Connection string

```csharp
var cs = new SqliteConnectionStringBuilder
{
    DataSource     = dbPath,
    Mode           = SqliteOpenMode.ReadWriteCreate,
    Cache          = SqliteCacheMode.Shared,
    Pooling        = true,
    DefaultTimeout = 30,
}.ToString();
```

`Cache = Shared` enables the in-process shared cache so multiple connections in the same app share locks coherently. Pooling is on by default in `Microsoft.Data.Sqlite` ≥ 6.0; keep it that way.

## Lifecycle: graceful shutdown is mandatory

Every service that writes to SQLite must register a hosted service that checkpoints the WAL on shutdown. Without it, a hard kill leaves the WAL un-merged and the next container that opens the DB has to recover, which is the failure window where corruption happens on a network FS.

```csharp
public sealed class SqliteCheckpointOnStop(string connectionString) : IHostedService
{
    public Task StartAsync(CancellationToken _) => Task.CompletedTask;

    public Task StopAsync(CancellationToken _)
    {
        using var conn = new SqliteConnection(connectionString);
        conn.Open();
        conn.Execute("PRAGMA wal_checkpoint(TRUNCATE);");
        return Task.CompletedTask;
    }
}
```

Register early in DI so it runs during the `IHostedService` shutdown phase. Pair with `stop_grace_period: 30s` in compose so the container actually has time to finish the checkpoint.

## Retry on transient errors

SQLite throws `SQLITE_BUSY (5)`, `SQLITE_LOCKED (6)`, and `SQLITE_IOERR (10)` under contention or transient I/O issues. Wrap writes with a small retry policy:

```csharp
var retry = Policy
    .Handle<SqliteException>(e => e.SqliteErrorCode is 5 or 6 or 10)
    .WaitAndRetryAsync(5, attempt => TimeSpan.FromMilliseconds(100 * Math.Pow(2, attempt)));
```

Do not retry `SQLITE_CORRUPT (11)` — that is a permanent failure and must surface as a fatal error so the service is restarted and a fresh DB is restored from backup.

## Backups

- For dev / small DBs: `VACUUM INTO '/backup/app-{timestamp}.db';` on a schedule.
- For production: [Litestream](https://litestream.io) for continuous WAL streaming to Azure Blob, or [LiteFS](https://github.com/superfly/litefs) for replication if reads need to scale across nodes. See `.claude/docs/spot-architecture.md` for the architecture-level decision.

## Forbidden patterns

- `journal_mode=WAL` on a service whose volume is NFS, SMB, or any FUSE-backed storage.
- A SQLite-using service without a placement constraint pinning it to a specific node.
- A SQLite-using service with `replicas > 1`.
- `busy_timeout=0` or omitting `busy_timeout` entirely.
- Catching `SqliteException` and continuing without re-throwing on `SQLITE_CORRUPT`.
- Opening a fresh `SqliteConnection` per query in a hot path without pooling.
