# Bahnpuls

Verspätungs-Analytics für den Schienenverkehr (VRN + RMV). Datenpipeline- und
Analyseprojekt — kein CRUD, kein PWA, kein n8n.

Dashboard: **[bahnpuls.dasdann.jetzt](https://bahnpuls.dasdann.jetzt)**

Projektregeln: [CLAUDE.md](./CLAUDE.md). Vollständiger fachlicher und architektonischer
Kontext liegt im Vault, nicht hier:

```
C:\Users\bades\OneDrive\Desktop\Ideen\02 Projekte\Bahnpuls\
```

Stand: der Collector sammelt seit dem 19.08.2026 durchgehend GTFS-RT-Daten für VRN und
RMV auf ein Persistent Volume; dbt baut daraus die Marts, Evidence rendert daraus das
Dashboard, beides stündlich auf demselben Server. Die Schweizer Zweige der Pipeline
laufen weiterhin gegen synthetische Fixtures — echte CH-Ist-Daten sind noch nicht
eingespielt (siehe `transform/README.md`).

## Stack

Go (Collector) · Parquet + ZSTD · DuckDB · dbt-duckdb · Evidence.dev · Docker/Coolify auf
eigenem VPS.

## Struktur

```text
cmd/collector/      Poll-Loop, Signal-Handling
cmd/statictool/     GTFS-Static laden & versionieren
internal/gtfsrt/    Protobuf-Decode
internal/scope/     Zielgebiets-Filter
internal/dedup/     Änderungserkennung, State
internal/writer/    Parquet-Writer, Partitionierung, Flush
internal/health/    Heartbeat, Feed-Alter, Metriken
internal/static/    Fahrplan-Archive laden, versioniert ablegen
data/               Rohdaten (nicht in Git)
transform/          dbt-duckdb-Projekt, siehe transform/README.md
dashboard/          Evidence.dev-Seiten, siehe dashboard/README.md
deploy/             Betrieb: Healthcheck, Prüfskripte, Coolify-Hinweise
```

## Lizenz

**Code:** [MIT](./LICENSE).

**Daten:** eigene Lizenzen der jeweiligen Herausgeber, nicht MIT. Die Echtzeitdaten von
[gtfs.de](https://gtfs.de) stehen unter
[CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/) — daraus abgeleitete
Datenbestände erben die Share-Alike-Pflicht —, die statischen Fahrplandaten unter
[CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Vollständige Attribution und
Weitergabebedingungen: [bahnpuls.dasdann.jetzt/lizenz](https://bahnpuls.dasdann.jetzt/lizenz).

Dieses Repo enthält **keine Rohdaten**.
