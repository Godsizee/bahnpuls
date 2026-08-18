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

### Q12-Volumenmessung (temporär, BPULS-029)

Zwei zusätzliche, optionale Env-Vars aktivieren einen zweiten Scope-Filter + Writer im
selben Prozess — verarbeitet denselben Feed-Abruf, kostet also keine zusätzliche
Bandbreite. Leer/unset (Default) heißt: deaktiviert, kein Verhaltensunterschied zur
Produktion.

| Variable | Beispiel (24h-Testlauf) |
|---|---|
| `BAHNPULS_MEASURE_SCOPE_CONFIG` | `config/scope_stops_bundesweit.csv` |
| `BAHNPULS_MEASURE_DATA_DIR` | `/data/measure_raw` |

Beide Pfade müssen auf dem Persistent Volume liegen, sonst geht die Messung beim nächsten
Redeploy verloren wie jede andere Rohdatei auch (CLAUDE.md Regel 2). Nach der Auswertung
beide Env-Vars wieder entfernen und `measurePipeline` in `cmd/collector/main.go`
zurückbauen — das ist Wegwerf-Code für genau diese eine Messung, nicht Teil der
Dauerarchitektur.

**`/data/measure_raw` dabei nicht löschen, solange Q12 offen ist.** Fällt die Entscheidung
auf „bundesweit sammeln", ist dieses Verzeichnis der erste Tag der neuen Historie — und
ein gelöschter Tag ist endgültig weg (ADR-008).

---

## Runbook: 24 h-Messlauf auf Coolify (BPULS-006 → BPULS-029)

Der Lauf beantwortet Q12 (regional oder bundesweit sammeln) und ist gleichzeitig der
**erste produktive Start des Collectors**: der reguläre Pfad schreibt ab Schritt 6 echte
Historie nach `/data/raw`. Deshalb wird er nicht als Wegwerf-Deployment aufgesetzt,
sondern gleich richtig — und nach der Messung nicht abgeschaltet, sondern nur um die
beiden Mess-Env-Vars erleichtert (CLAUDE.md Regel 3).

### 0. Voraussetzung: der Stand muss auf GitHub sein

Coolify baut aus dem Git-Repository, nicht aus dem Arbeitsverzeichnis. Ohne diesen Schritt
baut Coolify einen Stand ohne Collector-Verdrahtung, und der Messpfad bricht beim Start
mit `log.Fatalf` ab, weil `config/scope_stops_bundesweit.csv` im Image fehlt.

Vor dem Push prüfen, dass nichts Sensibles mitgeht (CLAUDE.md Regel 14) — die Scope-Listen
sind abgeleitete GTFS-Haltestellendaten, unkritisch.

### 1. Application in Coolify anlegen

- **New Resource → Application → Git Repository**, Repo `Godsizee/bahnpuls`, Branch `master`
- **Build Pack: Dockerfile** (Base Directory `/`, Dockerfile `Dockerfile`)
- **Kein Port veröffentlichen.** Der Collector ist kein Webdienst. Falls Coolify einen Port
  oder einen HTTP-Healthcheck erwartet: beides leeren bzw. deaktivieren — sonst hält
  Coolify den Container für unhealthy und startet ihn in einer Schleife neu. Der richtige
  Healthcheck auf den Heartbeat kommt mit BPULS-022, nicht jetzt.
- Restart-Policy auf `unless-stopped` (Coolify-Default).

### 2. Persistent Volume — der Schritt, der das Projekt sonst kostet

**Storages → Add → Volume Mount**, Name z. B. `bahnpuls-data`, Mount Path **`/data`**.

Vor dem Start auf dem Host prüfen, ob überhaupt Platz da ist. Der bundesweite Pfad schreibt
grob die 19-fache Menge des regionalen (40-Sekunden-Rauchtest, BPULS-006):

```bash
df -h
```

### 3. Environment Variables

```ini
BAHNPULS_DATA_DIR=/data/raw
BAHNPULS_HEARTBEAT_PATH=/data/heartbeat.json
BAHNPULS_MEASURE_SCOPE_CONFIG=config/scope_stops_bundesweit.csv
BAHNPULS_MEASURE_DATA_DIR=/data/measure_raw
```

`BAHNPULS_SCOPE_CONFIG` und `BAHNPULS_FEED_URL` bleiben auf Default — die Scope-Liste liegt
im Image, der Feed ändert sich nicht. Verzeichnisse legt der Writer selbst an
(`os.MkdirAll`), sie müssen nicht vorbereitet werden.

### 4. Stop-Grace-Period setzen (BPULS-021)

Der `SIGTERM`-Handler flusht den offenen Stundenpuffer vor dem Exit. Docker gibt dafür per
Default nur 10 s, bevor `SIGKILL` kommt. In Coolify unter den Docker-Optionen der
Application `--stop-timeout=60` setzen (das Label unterscheidet sich je nach
Coolify-Version — entscheidend ist, dass die Option im `docker run`/Compose-Aufruf landet).

Ob es wirkt, wird in Schritt 5 gemessen, nicht angenommen.

### 5. Redeploy-Test — 10 Minuten, nicht überspringen (BPULS-020)

Dieser Test ist gleichzeitig der **erste echte SIGTERM-Beweis**: lokal auf Windows war er
nicht führbar, weil `TerminateProcess` sich nicht abfangen lässt.

1. Deployen, im Log auf zwei bis drei `collector: poll ok …`-Zeilen warten. Direkt daneben
   muss `collector: measure poll ok …` stehen — sonst greift der Messpfad nicht.
2. Terminal in den Container (Coolify → Terminal, oder `docker exec -it <container> sh`):

   ```sh
   ls -la /data
   cat /data/heartbeat.json
   date > /data/redeploy-test.txt
   ```

3. Container über Coolify **stoppen** und das Log prüfen. Es müssen
   `shutdown signal received, flushing buffer before exit` **und** `shutdown complete`
   erscheinen. Fehlt die zweite Zeile, war die Grace-Period zu kurz → Schritt 4 korrigieren
   und wiederholen.
4. Prüfen, dass der Flush Dateien erzeugt hat:

   ```sh
   find /data/raw /data/measure_raw -name '*.parquet' | head
   ```

5. **Redeploy** auslösen (nicht nur Start — ein Redeploy ersetzt das Container-Dateisystem,
   genau darum geht es).
6. Erneut ins Terminal: `cat /data/redeploy-test.txt` und die Parquet-Dateien müssen noch da
   sein. Sind sie weg, ist das Volume nicht korrekt gemountet — **hier abbrechen**, bis das
   stimmt.
7. `rm /data/redeploy-test.txt`, danach ist der Marker erledigt.

### 6. Messlauf

Startzeitpunkt notieren. An einem **normalen Werktag** starten, nicht am Wochenende — die
Änderungsrate im Feed hängt am Verkehrsaufkommen, und ein Sonntag unterschätzt das Volumen
systematisch.

Mindestens **26 Stunden** laufen lassen, ausgewertet werden die 24 vollständigen
Stundenpartitionen dazwischen. Grund: die erste Stunde enthält den **Kaltstart** — der
Dedup-Tracker ist leer, der erste Poll schreibt jede Zeile jeder Fahrt im Scope (im lokalen
Rauchtest 10.012 Zeilen gegenüber 230 im eingeschwungenen Zustand). Diese Stunde verfälscht
jede Hochrechnung und wird verworfen, ebenso die angebrochene letzte.

Währenddessen einmal den Speicherbedarf mitnehmen — der Dedup-Tracker hält bundesweit rund
19-mal so viele Einträge, und das ist neben der Platte der zweite Kostenfaktor der
Q12-Entscheidung (BPULS-028):

```bash
docker stats --no-stream
```

### 7. Auswertung

Volume-Pfad auf dem Host ermitteln:

```bash
docker inspect <container> --format '{{ json .Mounts }}'
```

**Bytes je Stunde** (`date=…/hour=…` sind die Partitionsebenen):

```bash
MOUNT=<mountpoint aus dem inspect>
du -b --max-depth=2 "$MOUNT/raw" "$MOUNT/measure_raw" | sort -k2
```

**Zeilen je Stunde**, beide Pfade nebeneinander — die DuckDB-CLI ist ein einzelnes Binary,
es muss nichts installiert werden:

```sql
select 'regional' as pfad,
       regexp_extract(filename, 'date=([0-9-]+)', 1) as tag,
       regexp_extract(filename, 'hour=([0-9]+)', 1)  as stunde,
       count(*) as zeilen
from read_parquet('MOUNT/raw/**/*.parquet', filename = true)
group by all
union all
select 'bundesweit',
       regexp_extract(filename, 'date=([0-9-]+)', 1),
       regexp_extract(filename, 'hour=([0-9]+)', 1),
       count(*)
from read_parquet('MOUNT/measure_raw/**/*.parquet', filename = true)
group by all
order by tag, stunde, pfad;
```

Daraus die Zahlen, die Q12 tatsächlich entscheiden:

| Kennzahl | regional | bundesweit |
|---|---|---|
| Bytes/Tag (ohne Kaltstartstunde) |   |   |
| Zeilen/Tag |   |   |
| Hochrechnung 1 Monat / 1 Jahr |   |   |
| Freier Plattenplatz danach (`df -h`) |   |   |
| RSS des Collectors (`docker stats`) |   |   |

Faktor bundesweit/regional aus beiden Zeilen bilden und gegen die Erwartung aus dem
Rauchtest halten (~19×). Weicht er stark ab, erst die Ursache klären, bevor entschieden
wird — ein Ausreißer in einer einzelnen Stunde (Störungslage) ist kein Tagesmittel.

### 8. Danach

1. Ergebnis als ADR zu Q12 in `Decisions.md` festhalten, BPULS-029 schließen.
2. Beide `BAHNPULS_MEASURE_*`-Env-Vars entfernen, Redeploy.
3. `measurePipeline` aus `cmd/collector/main.go` zurückbauen (Wegwerf-Code).
4. **Collector weiterlaufen lassen.** Ab hier zählt jeder Tag Historie.
5. `/data/measure_raw` erst löschen, wenn Q12 gegen „bundesweit" entschieden ist.
