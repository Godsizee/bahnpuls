# Deploy

Läuft über Coolify (Docker), nicht systemd — siehe ADR-009 in `Decisions.md` im Vault.
Details zu Persistent Volumes, Scheduled Tasks und Healthcheck stehen in
`Referenz/Bahnpuls_Betrieb_und_Deployment.md` im Vault, nicht hier (keine Redundanz).

Dockerfile liegt im Repo-Root (BPULS-008). Lokal noch nicht gebaut/getestet — kein
Docker auf diesem Rechner, Build-Test steht aus.

## Collector-Konfiguration (Environment Variables)

Alle Defaults sind auf lokale Entwicklung ausgelegt (relative Pfade). Im Container per
Coolify Environment Variables überschreiben, sobald das Persistent Volume unter `/data`
gemountet ist:

| Variable | Default | Produktiv (Beispiel) |
|---|---|---|
| `BAHNPULS_FEED_URL` | `https://realtime.gtfs.de/realtime-free.pb` | unverändert |
| `BAHNPULS_SCOPE_CONFIG` | `config/scope_stops.csv` | unverändert (liegt im Image) |
| `BAHNPULS_DATA_DIR` | `data/raw` | `/data/raw` |
| `BAHNPULS_HEARTBEAT_PATH` | `data/heartbeat.json` | `/data/heartbeat.json` |

`-poll-interval` und `-fetch-timeout` sind reine Flags (kein Env-Fallback bisher), Default
30 s bzw. 15 s.
