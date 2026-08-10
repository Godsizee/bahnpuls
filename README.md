# Bahnpuls

Verspätungs-Analytics für den Schienenverkehr (VRN + Rhein-Main). Datenpipeline- und
Analyseprojekt — kein CRUD, kein PWA, kein n8n.

Projektregeln: [CLAUDE.md](./CLAUDE.md). Vollständiger fachlicher und architektonischer
Kontext liegt im Vault, nicht hier:

```
C:\Users\bades\OneDrive\Desktop\Ideen\02 Projekte\Bahnpuls\
```

Stand: M0 (Fundament) — Repo-Skeleton steht, Collector folgt (BPULS-002 ff.).

## Stack

Go (Collector) · Parquet + ZSTD · DuckDB · dbt-duckdb · Evidence.dev · Docker/Coolify ·
Cloudflare Pages (Dashboard).

## Struktur

```text
cmd/collector/     Poll-Loop, Signal-Handling
cmd/statictool/     GTFS-Static laden & versionieren
internal/gtfsrt/    Protobuf-Decode
internal/scope/     Zielgebiets-Filter
internal/dedup/     Änderungserkennung, State
internal/writer/    Parquet-Writer, Partitionierung, Flush
internal/health/    Heartbeat, Feed-Alter, Metriken
data/                Rohdaten (nicht in Git)
deploy/              Coolify-Hinweise
```

`transform/` (dbt) und `dashboard/` (Evidence.dev) kommen erst in M1 (BPULS-010, BPULS-014).
