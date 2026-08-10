# Bahnpuls

Verspätungs-Analytics für den Schienenverkehr (VRN + Rhein-Main). Datenpipeline- und
Analyseprojekt — kein CRUD, kein PWA, kein n8n.

Projektregeln: [CLAUDE.md](./CLAUDE.md). Vollständiger fachlicher und architektonischer
Kontext liegt im Vault, nicht hier:

```
C:\Users\bades\OneDrive\Desktop\Ideen\02 Projekte\Bahnpuls\
```

Stand: M0 — Collector läuft (gegen den echten Feed getestet), Dockerfile steht aber noch
ungebaut. Offen: 24h-Messlauf (BPULS-006), Haltestellenliste fachlich prüfen, Docker-Build
verifizieren. M1 begonnen: dbt-duckdb-Projekt steht, `stg_ch_istdaten` normalisiert
CH-Ist-Daten auf das gemeinsame Schema (BPULS-010/011, gegen synthetische Fixture
getestet, echte Datei noch offen — siehe `transform/README.md`).

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
transform/           dbt-duckdb-Projekt, siehe transform/README.md
deploy/              Coolify-Hinweise
```

`dashboard/` (Evidence.dev) kommt erst mit BPULS-014.
