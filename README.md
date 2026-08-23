# Bahnpuls

**Wo entsteht Verspätung im Schienenverkehr — auf der Strecke oder im Bahnhof?**

Ein Zug kommt zwölf Minuten zu spät an. Das steht in jeder Statistik. Was nirgends steht:
wo diese zwölf Minuten entstanden sind. Standen sie schon beim Start? Kamen sie auf einem
bestimmten Abschnitt dazu? Oder sammelten sie sich in kleinen Portionen an sechs
Bahnhöfen, weil überall der Aufenthalt zu knapp bemessen ist? Drei verschiedene Probleme
mit drei verschiedenen Antworten — und aus der Ankunftsverspätung allein nicht zu
unterscheiden.

Bahnpuls rechnet das aus. Aus eigener Mitschrift, weil es die Daten dafür sonst nirgends
gibt.

**→ [bahnpuls.dasdann.jetzt](https://bahnpuls.dasdann.jetzt)**

## Warum eigene Mitschrift

Echtzeitdaten im Nahverkehr sind **Prognosen**, keine Aufzeichnungen. Eine Stunde vor
Abfahrt sagt der Feed etwas anderes als fünf Minuten vorher, und wenn der Zug durch ist,
verschwindet der Eintrag. Ein Archiv führt niemand.

Deshalb steht am Anfang dieses Projekts kein Datensatz, sondern ein Sammler: Alle 30
Sekunden fragt ein Go-Dienst den GTFS-Realtime-Feed ab und schreibt fest, was sich seit
dem letzten Mal geändert hat. Was daraus entsteht, ist der eigentliche Wert des
Projekts — ein Bestand, den es sonst nicht gibt und der sich nicht nachträglich herstellen
lässt. Ein Tag ohne laufenden Collector ist endgültig verlorene Historie.

## Wie es funktioniert

```text
GTFS-RT-Feed  ──30 s──▶  Collector (Go)  ──▶  Parquet auf Volume
                                                    │
                          GTFS-Static ──▶  dbt-duckdb: staging → intermediate → marts
                          (versioniert)              │
                                                     ▼
                                            Evidence.dev-Seiten
```

Für jeden Halt werden zwei Werte festgehalten: wie viel Verspätung ein Zug beim **Ankommen**
hatte und wie viel beim **Weiterfahren**. Aus der Differenz zum Vorhalt ergibt sich, ob die
Verspätung unterwegs entstand (Laufzeitanteil) oder während des Aufenthalts
(Haltezeitanteil) — oder ob der Zug eingebaute Reserve gezogen hat.

Der Rest sind Fallstricke, die man beim ersten Mal übersieht und die jede Kennzahl
verfälschen, wenn man sie übersieht:

| Fallstrick | Behandlung |
|---|---|
| Ein Ausfall ist keine Verspätung von 0 | Ausfälle stehen **neben** der Quote, nie darin — sonst verbessert jede Streichung die Statistik |
| Betriebstag ≠ Kalendertag | GTFS-Zeiten wie `25:30:00` sind Sekunden seit Betriebstagsbeginn; als Uhrzeit geparst verschwinden genau die Nachtfahrten |
| Die Nacht der Zeitumstellung | Eine Stunde gibt es zweimal; betroffene Halte sind **nicht bestimmbar** und werden entwertet — auch der Folgehalt, dessen Abschnitt gegen sie rechnet |
| Fahrpläne ändern sich | Ist-Daten werden gegen die zum Ereigniszeitpunkt **gültige** Fahrplanversion gejoint, nie gegen die aktuelle |
| Nicht bestimmbar ≠ null | Fehlende Werte bleiben `NULL`. Eine 0 wäre die Aussage „hat sich nicht verändert" |

Jede dieser Entscheidungen steht auf der [Methodik-Seite](https://bahnpuls.dasdann.jetzt/methodik)
offen — mit dem, was die Zahlen ausdrücklich **nicht** behaupten.

## Stack

**Go** (Collector, statisches Binary, `CGO_ENABLED=0`) · **Parquet + ZSTD** ·
**DuckDB** · **dbt-duckdb** · **Evidence.dev** · **Docker/Coolify** auf eigenem VPS.

Bewusst nicht im Stack: Kafka, Airflow, Kubernetes, ein Message Broker. Ein Feed, ein
Container, ein Volume, eine eingebettete Datenbank, eine statische Seite — die
Architekturentscheidungen dahinter stehen als ADRs im Projektvault.

## Betrieb

Der Dienst läuft unbeaufsichtigt und muss das über Monate tun. Was dafür gebaut ist:

- **Sauberes `SIGTERM`-Shutdown**, das den offenen Stundenpuffer vor dem Prozessende auf
  das Volume schreibt — sonst kostet jedes Deployment bis zu einer Stunde Daten.
- **Dedup mit begrenztem State**: der Tracker vergisst einen Schlüssel, sobald er zwei
  Beobachtungsgenerationen lang nicht mehr im Feed stand. In Produktion belegt: der
  Schlüsselzähler steigt an und fällt wieder.
- **Panic-Recovery nur im äußeren Poll-Loop** — ein Absturz darf höchstens den aktuellen
  Stundenpuffer kosten, nie als Fehlerkanal dienen.
- **Stündliche fachliche Prüfung** als Scheduled Task: Heartbeat-Alter, Feed-Alter,
  Scope-Anteil, Alter der neuesten Datei, Plattenplatz. Ein laufender Container, der
  nichts Sinnvolles schreibt, ist der Fehler, den ein Healthcheck nicht sieht.
- **Prüfung der Seitenabfragen gegen die ausgelieferten Quelldateien.** Eine
  Evidence-Seite mit fehlender Bindung antwortet von außen mit HTTP 200, richtigem Titel
  und richtiger Größe — der Fehler zeigt sich erst im Browser des Lesers.

## Tests

`dbt build` gegen die Fixtures: **214 Tests**, davon vier gewollte Warnungen, die
Eigenschaften der Quelle beschreiben statt Modellfehler. Abgedeckt sind vor allem die
Fälle, die in echten Daten nicht verlässlich vorkommen und trotzdem jede Kennzahl still
verschieben würden: Fahrt über Mitternacht, Ausfall, ausgelassener Halt, Sequenzlücke,
Ringlauf über denselben Bahnhof, unplausible Verspätung — und die Rücksprungnacht der
Zeitumstellung.

Table-driven Tests decken die Go-Seite ab (Decode, Scope-Filter, Dedup, Writer, Static).

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
transform/          dbt-duckdb-Projekt, siehe transform/README.md
dashboard/          Evidence.dev-Seiten, siehe dashboard/README.md
deploy/             Betrieb: Healthcheck, Prüfskripte, Coolify-Hinweise
data/               Rohdaten (nicht in Git)
```

Projektregeln und Nicht-verhandelbare Invarianten: [CLAUDE.md](./CLAUDE.md).

## Lizenz

**Code:** [MIT](./LICENSE).

**Daten:** eigene Lizenzen der jeweiligen Herausgeber, nicht MIT. Die Echtzeitdaten von
[gtfs.de](https://gtfs.de) stehen unter
[CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/) — daraus abgeleitete
Datenbestände erben die Share-Alike-Pflicht —, die statischen Fahrplandaten unter
[CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Vollständige Attribution und
Weitergabebedingungen: [bahnpuls.dasdann.jetzt/lizenz](https://bahnpuls.dasdann.jetzt/lizenz).

Dieses Repo enthält **keine Rohdaten**.
