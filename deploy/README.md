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

| `BAHNPULS_POLL_INTERVAL` | `30s` | unverändert |
| `BAHNPULS_FETCH_TIMEOUT` | `25s` | unverändert |

`-poll-interval` und `-fetch-timeout` gibt es weiterhin als Flags; die Env-Variablen setzen
nur deren Default, damit sich der Wert in Coolify ändern lässt, ohne das Image neu zu bauen
(BPULS-058). Angaben im Go-Format (`25s`, `1m30s`). Ein unlesbarer oder nicht positiver Wert
wird geloggt und ignoriert — der Collector startet trotzdem, statt in eine Restart-Schleife
zu laufen (Regel 3). Der Fetch-Timeout deckt **das Lesen des Bodys** mit ab, nicht nur den
Verbindungsaufbau: mit 15 s liefen im ersten 24 h-Lauf 1,96 % der Polls in einen Timeout.

Gesammelt wird **ausschließlich der Scope VRN + RMV** (ADR-008, ADR-010). Der zweite
Scope-Filter für eine bundesweite Vergleichsmessung wurde am 2026-08-19 wieder ausgebaut —
Q12 ist ohne Messung gegen „bundesweit" entschieden, siehe ADR-010 in `Decisions.md`.

---

## Runbook: Erststart und 24 h-Testlauf auf Coolify

Der Lauf ist der **erste produktive Start des Collectors**: er schreibt ab Schritt 6 echte
Historie nach `/data/raw`. Deshalb wird er nicht als Wegwerf-Deployment aufgesetzt, sondern
gleich richtig — und danach nicht abgeschaltet (CLAUDE.md Regel 3).

Er beantwortet drei Dinge auf einmal:

- **BPULS-020** — überlebt das Persistent Volume einen Redeploy?
- **BPULS-021** — flusht `SIGTERM` den Stundenpuffer wirklich? (auf Windows nicht prüfbar)
- **BPULS-006** — wie viel Volumen erzeugt der Scope pro Tag tatsächlich?

### 0. Voraussetzung: der Stand muss auf GitHub sein

Coolify baut aus dem Git-Repository, nicht aus dem Arbeitsverzeichnis. Ohne Push baut
Coolify einen Stand ohne Collector-Verdrahtung.

Vor dem Push prüfen, dass nichts Sensibles mitgeht (CLAUDE.md Regel 14) — die Scope-Liste
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

Vor dem Start auf dem Host prüfen, ob Platz da ist. Erwartung für den regionalen Scope:
niedriger dreistelliger MB-Bereich pro Tag (`Bahnpuls_Datenquellen.md`) — genau das
bestätigt oder widerlegt dieser Lauf. Achtung: die Haltestellenliste ist am 2026-08-19 von
836 auf 1.916 Halte gewachsen und trifft jetzt rund 2,3-mal so viele Fahrten wie in den
älteren Schätzungen (BPULS-005) — die alte Zahl unterschätzt das Volumen entsprechend.

```bash
df -h
```

### 3. Environment Variables

```ini
BAHNPULS_DATA_DIR=/data/raw
BAHNPULS_HEARTBEAT_PATH=/data/heartbeat.json
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

1. Deployen, im Log auf zwei bis drei `collector: poll ok …`-Zeilen warten. Die Zahl hinter
   `in scope` muss bei **rund 2.000 von ~78.000 Trips** liegen (Stand 2026-08-19, gemessen
   gegen den echten Feed). Deutlich weniger heißt: die Haltestellenliste greift nicht mehr,
   die `stop_id`s sind weitergerotiert — siehe Q6 im Vault. Das ist der billigste
   Frühwarnkanal, den es hier gibt.
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
   find /data/raw -name '*.parquet' | head
   ```

5. **Redeploy** auslösen (nicht nur Start — ein Redeploy ersetzt das Container-Dateisystem,
   genau darum geht es).
6. Erneut ins Terminal: `cat /data/redeploy-test.txt` und die Parquet-Dateien müssen noch da
   sein. Sind sie weg, ist das Volume nicht korrekt gemountet — **hier abbrechen**, bis das
   stimmt.
7. `rm /data/redeploy-test.txt`, danach ist der Marker erledigt.

### 6. Testlauf

Startzeitpunkt notieren. An einem **normalen Werktag** starten, nicht am Wochenende — die
Änderungsrate im Feed hängt am Verkehrsaufkommen, und ein Sonntag unterschätzt das Volumen
systematisch.

Mindestens **26 Stunden** laufen lassen, ausgewertet werden die 24 vollständigen
Stundenpartitionen dazwischen. Grund: die erste Stunde enthält den **Kaltstart** — der
Dedup-Tracker ist leer, der erste Poll schreibt jede Zeile jeder Fahrt im Scope (im lokalen
Rauchtest 10.012 Zeilen gegenüber 230 im eingeschwungenen Zustand). Diese Stunde verfälscht
jede Hochrechnung und wird verworfen, ebenso die angebrochene letzte.

Währenddessen einmal den Speicherbedarf mitnehmen — der Dedup-Tracker wächst mit jeder
gesehenen Fahrt, das ist der Hintergrund von BPULS-028:

```bash
docker stats --no-stream
```

**Der Lauf ist unbewacht.** Healthcheck (BPULS-022) und fachliche Prüfung (BPULS-026) sind
zu diesem Zeitpunkt noch nicht eingerichtet — stürzt der Container nachts ab, merkt es
niemand. Einmal zwischendurch ins Log sehen: frische `poll ok`-Zeilen mit einer plausiblen
`in scope`-Zahl genügen als Lebenszeichen.

> [!warning] Freien Plattenplatz selbst prüfen
> Coolifys eigene Warnschwelle ist kein Sicherheitsnetz — auf `strato` stand sie auf 80 %,
> während die Platte bei 99 % lag, ohne dass etwas passiert wäre. Vor dem Start und nach
> dem Lauf `df -h` fahren. Läuft die Platte voll, schlägt der Parquet-Flush fehl, und die
> Lücke ist nicht nachlieferbar.
>
> Beim Aufräumen: `docker image prune -a` **immer** mit `--filter "until=168h"`, sonst
> verschwinden Coolifys Rollback-Images aller Apps auf dem Server. `docker volume prune`
> nur nach Sichtprüfung — Volumes gestoppter Apps gelten als ungenutzt und sind danach
> endgültig weg.

### 7. Auswertung

Volume-Pfad auf dem Host ermitteln:

```bash
docker inspect <container> --format '{{ json .Mounts }}'
```

**Bytes je Stunde** (`date=…/hour=…` sind die Partitionsebenen):

Auf dem Host (GNU-Coreutils):

```bash
MOUNT=<mountpoint aus dem inspect>
du -b --max-depth=2 "$MOUNT/raw" | sort -k2
```

**Im Container geht das nicht so** — Alpine bringt BusyBox mit, `--max-depth` kennt es
nicht, und `df /` zeigt das Overlay statt des Volumes:

```sh
du -b -s /data/raw
du -b -s /data/raw/date=*/hour=* | sort -k2
df -h /data
```

**Zeilen je Stunde** — die DuckDB-CLI ist ein einzelnes Binary, es muss nichts installiert
werden:

```sql
select regexp_extract(filename, 'date=([0-9-]+)', 1) as tag,
       regexp_extract(filename, 'hour=([0-9]+)', 1)  as stunde,
       count(*)                                      as zeilen,
       count(distinct trip_id)                       as fahrten
from read_parquet('MOUNT/raw/**/*.parquet', filename = true)
group by all
order by tag, stunde;
```

Daraus die Zahlen, die den Betrieb planbar machen:

Ergebnis des ersten Laufs (2026-08-19 08:03 UTC bis 2026-08-20; 23 volle Stunden
ausgewertet — `hour=09` enthält den Kaltstart und wird verworfen, verwertbar ab `hour=10`):

| Kennzahl | Wert |
|---|---|
| Bytes/Tag (ohne Kaltstartstunde) | **offen** — braucht `du -b` auf dem Host, die Coolify-API (4.3.9) hat keinen Exec-Endpoint |
| Zeilen/Tag | ~2,45 Mio (2.349.734 in 23 h), im Mittel ~102.000/h |
| Hochrechnung 1 Monat / 1 Jahr | ~74 Mio / ~895 Mio Zeilen; in Bytes offen, s. o. |
| Freier Plattenplatz danach (`df -h`) | offen, zusammen mit der Byte-Messung |
| RSS des Collectors (`docker stats`) | offen — über die API nicht auslesbar (BPULS-028) |
| Feed-Ausfälle im Log (`fetch failed`) | 57 von 2.901 Versuchen (1,96 %), alle `read body: context deadline exceeded` → BPULS-058 |

Die Zeilenzahlen lassen sich **ohne Shell** gewinnen: jede `poll ok`-Zeile trägt den
Pufferstand, und der Wert unmittelbar vor einem `flushed …`-Eintrag ist der Inhalt genau
dieser Stundenpartition. Für Bytes gilt das nicht — die stehen nur auf dem Volume.

Tagesgang prüfen: die Änderungsrate muss nachts einbrechen und in den Spitzenstunden
steigen. Eine flache Kurve wäre ein Hinweis darauf, dass etwas anderes gemessen wird als
Verkehr. Im ersten Lauf erfüllt: 4.540 Zeilen um 01 Uhr gegenüber 161.002 um 15 Uhr — Faktor
35. Wer aus einer einzelnen Tagesstunde hochrechnet, misst den Tagesgang mit und liegt um
mehr als das Doppelte daneben.

### 8. Danach

1. Ergebnis in `Backlog.md` (BPULS-006) festhalten, bei Auffälligkeiten in `Decisions.md`.
2. **Collector weiterlaufen lassen.** Ab hier zählt jeder Tag Historie.
3. Nächste Betriebsaufgaben: Healthcheck auf den Heartbeat (BPULS-022), fachliche Prüfung
   als Scheduled Task (BPULS-026), Backup (BPULS-025).

---

## Monitoring: Healthcheck und fachliche Prüfung

Zwei Ebenen, bewusst getrennt — ein Container kann laufen und trotzdem nichts Sinnvolles
schreiben, und umgekehrt darf ein Feed-Ausfall keinen Neustart auslösen.

| | `deploy/healthcheck.sh` (BPULS-022) | `deploy/pruefung.sh` (BPULS-026) |
|---|---|---|
| Frage | Lebt der Prozess? | Kommt Sinnvolles an? |
| Läuft als | Docker-`HEALTHCHECK`, alle 60 s | Coolify Scheduled Task |
| Prüft | Alter der `heartbeat.json` | Feed-Alter, Scope-Anteil, jüngste Parquet-Datei, Plattenplatz |
| Reaktion | Container gilt als unhealthy | Task schlägt fehl → Coolify-Notification |

### Healthcheck

Steckt im Image (`HEALTHCHECK`-Instruktion im Dockerfile), es ist in Coolify **nichts
einzustellen** — insbesondere weiterhin **kein HTTP-Healthcheck**: der Collector hat keinen
Port, ein HTTP-Check meldet ihn dauerhaft unhealthy und erzeugt genau die Restart-Schleife
aus Schritt 1.

Der Check prüft ausschließlich das Alter des Heartbeats (Grenze 300 s, über
`BAHNPULS_HEARTBEAT_MAX_AGE` verstellbar). Er schlägt **nicht** bei einem Feed-Ausfall an,
denn der Heartbeat wird bei jedem Poll geschrieben, auch bei Fehlern. Das ist Absicht: ein
Neustart behebt keinen Feed-Ausfall, kostet aber den offenen Stundenpuffer (Regel 3 und 4).

### Fachliche Prüfung

In Coolify unter der Application → **Scheduled Tasks** anlegen:

- Name `fachliche-pruefung`
- Command `/bin/sh /app/deploy/pruefung.sh`
- Frequency `0 * * * *` (stündlich; seltener verzögert nur den Befund)

Schwellwerte stehen als Konstanten oben im Skript, jede mit Begründung. Der wichtigste ist
der **Scope-Anteil in Promille**, nicht die absolute Zahl: nachts schrumpft der ganze Feed
(~5.000 statt ~76.000 Fahrten), der Anteil bleibt aber stabil — im 24 h-Lauf zwischen 21,5
und 53,3 Promille über alle Tageszeiten. Ein absoluter Schwellwert auf `in_scope_count`
würde jede Nacht falsch anschlagen; die Grenze von 10 Promille fängt dagegen den Fall ab, um
den es fachlich geht: rotierende `stop_id`s, die den Scope stillschweigend gegen null laufen
lassen (Q6 im Vault).

Vor dem ersten scharfen Einsatz einmal von Hand laufen lassen und die Ausgabe ansehen —
`pruefung ok` plus je eine Zeile zu Scope, jüngster Datei und Plattenplatz.

