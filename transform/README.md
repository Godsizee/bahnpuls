# Transform (dbt-duckdb)

Layer-Aufbau (`staging` → `intermediate` → `marts`) und das `fct_stop_events`-Zielschema
stehen in `Referenz/Bahnpuls_Datenmodell.md` im Vault, nicht hier (keine Redundanz).
`marts/` ist bislang ein leerer Ordner — erste Modelle folgen ab BPULS-014/016.

## Lokal ausführen

`profiles.yml` liegt bewusst im Projektordner statt unter `~/.dbt/` (Solo-Projekt, kein
Setup-Schritt auf einer zweiten Maschine nötig). dbt muss deshalb explizit auf dieses
Verzeichnis zeigen:

```bash
cd transform
python -m venv ../.venv          # einmalig
../.venv/Scripts/pip install dbt-core dbt-duckdb
export DBT_PROFILES_DIR="$(pwd)"
../.venv/Scripts/dbt deps         # installiert dbt_utils (siehe packages.yml)
../.venv/Scripts/dbt build
```

Die DuckDB-Datei landet unter `../data/bahnpuls.duckdb` — Build-Artefakt, nicht in Git.

Der Lauf braucht die dbt-Vars `de_gtfsrt_glob` und `de_static_dir`; ohne sie sucht er
unter `../data/raw` bzw. `../data/static` nach Dateien, die lokal niemand hat. Der
fertige Befehl steht unten unter „Lauf gegen die Fixtures".

## Die entfernte CH-Quelle (2026-08-23)

Bis zum 23.08.2026 hing an `fct_stop_events` ein zweiter Zweig: `stg_ch_istdaten`, das
Schweizer Ist-Daten-Archiv als **Spur A** — die Möglichkeit, Auswertungen zu entwickeln,
bevor eigene Sammelhistorie vorlag. Eingespielt wurden dort nie echte Daten (das Portal
blockt automatisierte Zugriffe mit HTTP 403), nur synthetische Fixtures.

Entfernt worden ist sie, sobald die eigene Aufzeichnung trug. Der Grund ist nicht
technisch: erfundene Zahlen standen im Dashboard neben gemessenen, und auf der Startseite
flossen sie sogar unbemerkt in dieselben Kennzahlen ein — die Blöcke dort hatten nie einen
Quellenfilter.

**Was das für die Testabdeckung hieß und wie sie ersetzt ist:** Die CH-Fixtures deckten
Fahrt über Mitternacht, Ausfall, ausgelassenen Halt und die Rücksprungnacht ab. Die ersten
drei deckte die DE-Fixture bereits mit ab (Fahrt `1007` fährt 23:50 → 25:10, `1004` fällt
aus, `1003` lässt einen Halt aus). Die Rücksprungnacht nicht — dafür ist
`tests/fixtures/de/2026-10-25_snapshots.parquet` samt Fahrplanversion
`v=2026-10-22` neu entstanden.

Zwei Tests sind mit der Quelle ersatzlos entfallen, weil sie ausdrücklich **nur** für sie
galten und nach dem Ausbau null Zeilen geprüft hätten — grün, aber ohne Aussage:
`assert_fct_stop_sequence_lueckenlos` (GTFS-RT sichert Lückenlosigkeit nicht zu, das trägt
`abschnitt_direkt`) und `assert_soll_zeit_im_betriebstag_fenster` (für GTFS-RT gilt
`assert_de_soll_zeit_im_fenster` als Warnung).

## Stand BPULS-012

`fct_stop_events` (intermediate, `table`) ist die **OCP-Nahtstelle** des Projekts: eine
neue Quelle wird ausschließlich dort als weiterer `union`-Zweig angehängt (nächster:
`stg_de_gtfsrt`, BPULS-030), Downstream bleibt unberührt. Die Spaltenliste ist deshalb
explizit ausgeschrieben statt `select *` — eine Quelle, die eine Spalte umbenennt, soll
dort laut auffallen. Aktuell hat das Modell genau einen Zweig, ist also fachlich ein
Pass-Through; es existiert wegen dieser Naht, nicht als Vorratsabstraktion.

`int_segment_delta` setzt A1 um (Laufzeit- vs. Haltezeitanteil). Drei Entscheidungen, die
nicht aus der Formel im Datenmodell folgen:

- **Eine Zeile je Halt-Ereignis**, nicht je Abschnitt. Nur so ist der Wasserfall eines
  Laufwegs vollständig lesbar: Startverspätung am ersten Halt, danach je Halt ein
  Laufzeit- und ein Haltezeitbeitrag.
- **Ausfälle und ausgelassene Halte werden nicht herausgefiltert, sondern entwertet.**
  Die Zeile bleibt in der Reihenfolge stehen und trägt `NULL`-Verspätungen. Würde sie
  herausfallen, spannte `lag()` den Abschnitt über sie hinweg und wiese zwei nicht
  benachbarte Betriebsstellen als direkte Fahrt aus — ein stiller Fehler. `NULL` heißt
  hier durchgehend „nicht bestimmbar", nie „keine Veränderung" (CLAUDE.md Regel 8,
  Fallstrick A1 in `Bahnpuls_Analysen.md`).
- **`abschnitt_direkt`** markiert, ob der Vorhalt unmittelbar vorausgeht. Für CH per
  Konstruktion immer wahr (`row_number()` im Staging), für eine Quelle mit echter
  `stop_sequence` nicht garantiert.

Zwei Custom-Tests sichern die Fensterlogik ab, weil eine falsche Partition/Sortierung
weiterhin plausible Zahlen liefern und jeden Wasserfall still verschieben würde:
`assert_segment_delta_kette_konsistent` (Laufzeitanteil bezieht sich auf genau den
Vorhalt derselben Fahrt) und `assert_segment_delta_erster_halt_ohne_vorhalt`. Dazu
`assert_fct_stop_sequence_lueckenlos` als Pflichttest aus dem Datenmodell.

Verifiziert gegen die Fixtures unter `tests/fixtures/`, siehe Abschnitt „Fixtures" unten.

## Fixtures und Testlauf

Die Fixtures liegen unter `tests/fixtures/` — im Repo, weil sie Testdaten sind und keine
Rohdaten. `data/raw/` bleibt echten Rohdaten vorbehalten, damit sich Konstruiertes und
Gemessenes dort nie vermischen. Der Aufruf steht unten unter „Lauf gegen die Fixtures".

`de/2026-08-13_snapshots.parquet` deckt ab: mehrere Snapshots je Halt (Dedup), einen
ausgelassenen Halt (`1003`), einen Ausfall (`1004`), eine Fahrt mit Sequenzlücke (`1002`,
Halte 5 und 7 — `abschnitt_direkt`), eine Nachtfahrt über Mitternacht (`1007`, 23:50 →
25:10, Betriebstag bleibt der Vortag), eine unplausible Abfahrt (`1008`, −83.050 s), einen
Pufferabbau (`1009`), zwei durchweg ausgelassene Fahrten (`1010`, `1011`), eine verdrehte
Soll-Zeit (`1012`) und eine gebietsfremde Fahrt über Nahverkehrshalte (`1013`).

**Die Halte der Fixture liegen in VRN + RMV** (seit BPULS-075). Das ist keine Kosmetik:
Halte außerhalb gehen in kein Aggregat mehr ein, und eine Fixture mit erfundenen Namen
(`Vorderpfalz Nord`, `Doppelstunden-Halt`) wäre nach der Umstellung grün gewesen, **weil
sie leer ist**. Ausgenommen ist Halt `C` — er ist der gebietsfremde Fall: Fahrt `1001`
fährt Mannheim → Heidelberg → Stuttgart, wie ein IC, der das Gebiet verlässt. Er trägt in
zwei Fahrplanversionen zwei Schreibweisen (`Stuttgart Hbf`, `Stuttgart Hbf (tief)`) und
bleibt damit zugleich der Fall für `assert_de_static_namen_eindeutig`.

`de/2026-10-25_snapshots.parquet` ist die **Rücksprungnacht** (Fahrt `1020`, Fahrplan
`v=2026-10-22`): Halt `S2` liegt mit 02:30/02:32 in der Stunde, die es in dieser Nacht
zweimal gibt, `S3` mit 03:20 sauber dahinter. Beide müssen entwertet werden — `S2`, weil
seine eigene Zeit mehrdeutig ist, `S3`, weil sein **Laufzeitanteil** gegen `S2` rechnet.
Der Folgehalt behält dabei seine eigene Ankunftsverspätung; nur der Abschnittswert fällt
weg. Genau dieser zweite Teil ist der Fall, den ein Blick auf `S2` allein nicht findet.

Die Soll-Zeiten der Fixture sind **rückwärts** gebaut: GTFS-RT liefert keine Soll-Zeit,
`stg_de_gtfsrt` rechnet sie als `time - delay`. Wer die Snapshot-Zeitstempel frei wählt,
bekommt andere Soll-Zeiten als die im Fahrplan — in der Umstellungsnacht mit einem
Stundenversatz, der genau den Testfall zerstört, den die Fixture herstellen soll.

## Stand BPULS-013

Testabdeckung nach der Minimum-Liste aus `Bahnpuls_Datenmodell.md` vervollständigt.
Zwei Befunde, die über reines Testschreiben hinausgehen:

**Betriebstag-Fenster statt Kalendertag-Gleichheit.** `assert_soll_zeit_im_betriebstag_fenster`
prüft, dass jede Soll-Zeit zwischen `betriebstag 00:00` und `betriebstag + 30 h` liegt.
Ein Betriebstag ist länger als 24 h (Nachtfahrten, und in der Rücksprungnacht 26 h) —
ein Test auf Kalendertag-Gleichheit wäre falsch, ein 30-h-Fenster fängt trotzdem jede
Verschiebung um einen Tag oder eine Zeitzone.

**Die Mehrdeutigkeit der Rücksprungnacht ist nicht wegrechenbar.** Soll und Ist sind
lokale Wanduhrzeiten ohne Offset. Liegen beide in der doppelten Stunde, ist aus den
Daten allein nicht entscheidbar, ob sie denselben Durchgang meinen. Geprüft: eine
Umrechnung über `AT TIME ZONE 'Europe/Zurich'` hilft **nicht** — sie wählt für beide
Werte denselben Durchgang und lässt die Differenz unverändert. In der Fixture zeigt
sich das als Zug, der real ~40 min verspätet ist und als −20 min ausgewiesen wird.
Konsequenz: `assert_keine_stille_zeitumstellung` markiert die betroffenen Halte mit
`severity: warn` — sie gehören auf die Methodik-Seite (BPULS-015) und später in
`mart_datenqualitaet` (BPULS-024), aber in keine Kennzahl. `warn` statt `error`, weil
der tägliche Lauf an einer Nacht im Jahr nicht scheitern darf. `Europe/Zurich` und
`Europe/Berlin` haben identische Umstellungsregeln, der Test gilt für beide Quellen.

**Unit-Tests statt Data-Tests für die Fensterlogik.** Die drei Fälle, die `int_segment_delta`
still verfälschen könnten (ausgelassener Halt mitten im Laufweg, Ausfall, `lag()` über
Fahrtgrenzen hinweg), stehen als dbt-Unit-Tests in
`models/intermediate/_intermediate__unit_tests.yml` — sie brauchen exakt konstruierte
Eingaben, die in echten Daten nicht verlässlich vorkommen. Für ein Staging-Modell auf
einer externen Datei sind Unit-Tests **nicht möglich**: dbt muss für eine gemockte Eingabe
die Spalten der Relation introspizieren, und eine über `external_location` eingebundene
Quelle ist nur ein Leseausdruck, keine Relation. Diese Ebene wird deshalb über die
Fixture-Dateien abgedeckt.

## Stand BPULS-016

Erste Marts, von Anfang an `materialized='incremental'` mit
`incremental_strategy='delete+insert'` auf `betriebstag` (CLAUDE.md Regel 10). Der
zuletzt geladene Betriebstag wird bei jedem Lauf neu gebaut (`>=` statt `>`), weil ein
Betriebstag bis zu 30 h reicht und beim ersten Durchlauf regelmäßig unvollständig ist —
`delete+insert` räumt ihn vorher weg, sonst stünden Nachtfahrten doppelt da.

- **`mart_zuglauf`** — eine Zeile je Halt-Ereignis, Grundlage der Laufweg-Seite im
  Dashboard. Existiert als eigener Mart, weil Evidence `int_segment_delta` nicht sehen
  darf (Regel 11).
- **`mart_verspaetungsentstehung`** — Laufzeit- und Haltezeitanteil je Betriebstag und
  Abschnitt. Führt **Summe und Zähler getrennt**, nicht nur den Mittelwert: über mehrere
  Tage muss aus beiden neu gerechnet werden, ein Mittel von Tagesmitteln gewichtet einen
  Sonntag wie einen Werktag. Quelle ist bewusst `mart_zuglauf` und nicht
  `int_segment_delta` — die Entwertungsregeln dürfen nur einmal existieren, sonst zeigen
  Detail- und Aggregatsicht widersprüchliche Zahlen, ohne dass ein Test anschlägt.

Damit ist die offene Folgeaufgabe aus BPULS-013 erledigt: die Halte aus der
Umstellungsstunde fließen in **keine** Kennzahl mehr. Die Definition liegt im Makro
`ist_umstellungszeit` und wird von `assert_keine_stille_zeitumstellung` (meldet sie) und
den Marts (schließen sie aus) gemeinsam genutzt — zwei Formulierungen wären
auseinandergelaufen. `assert_marts_ohne_zeitumstellung` prüft das hart.

**Ein Fall, den nur der Unit-Test fängt:** ein Halt in der Umstellungsstunde entwertet
auch den **Laufzeitanteil des Folgehalts**, der gegen dessen Abfahrtsverspätung rechnet.
Die Folgezeile sieht sauber aus und trägt trotzdem einen um bis zu 3.600 s verschobenen
Wert. Die Fixtures decken das nicht ab (dort ist der Folgehalt selbst mehrdeutig) —
gegengeprüft, indem die Vorhalt-Bedingung testweise entfernt wurde: nur der Unit-Test
schlug an, kein Data-Test.

Neue Fixture `2026-08-12_istdaten.csv`: drei Fahrten über einen vollständigen Laufweg
(Basel–Interlaken Ost), zwei davon auf denselben Abschnitten, damit die je-Zug-Normierung
im Aggregat mit mehr als einer Fahrt rechnet. Enthält Pufferabbau, eine Abfahrt mit
Prognosestatus ≠ `REAL` (Haltezeitanteil und Folgeabschnitt nicht bestimmbar) und
Endhalte ohne Abfahrt.

## Fallstrick: eine neue Quelle braucht `--full-refresh`

Die Marts laden inkrementell und filtern mit `betriebstag >= max(betriebstag)`. Das ist
richtig für den Normalbetrieb — es lädt vorwärts und baut den Grenztag neu auf — aber es
lädt **nie rückwärts**.

Kommt eine Quelle mit älteren Betriebstagen dazu, als bereits in der Tabelle stehen,
passiert deshalb *nichts*, und zwar lautlos: kein Fehler, kein leerer Lauf, die Modelle
melden Erfolg. Beim Anschluss von `stg_de_gtfsrt` (BPULS-030) trat genau das auf — die
Fixture der Rücksprungnacht (2026-10-25) stand als `max(betriebstag)` in den Marts und
schluckte den Tag 2026-08-13 vollständig.

**Regel:** nach dem Anschluss einer Quelle oder beim Nachladen historischer Tage einmal

```bash
dbt build --full-refresh
```

Im laufenden Betrieb ist das nicht nötig und auch nicht erwünscht — dort ist genau das
Vorwärtsladen gewollt.

## Lauf gegen die Fixtures

```bash
dbt build --vars '{"de_gtfsrt_glob": "tests/fixtures/de/*.parquet", "de_static_dir": "tests/fixtures/de_static"}'
```

Ohne `de_static_dir` bricht `stg_de_static` ab — es sucht dann unter `../data/static/`
nach einem Fahrplanarchiv, das lokal niemand hat.

Erwartung: `PASS=235 WARN=4 ERROR=0` von 239 (Stand 2026-08-23 nach BPULS-075 — vorher
214 von 218: dazu kamen der Seed, `stg_de_gebietshalt`, vier Unit-Tests und der
Abschlusstest `assert_marts_ohne_gebietsfremde_abschnitte`). Alle vier Warnungen tragen
`severity: warn` und sind gewollt — sie beschreiben Eigenschaften der Quelle, keine
Modellfehler, und dürfen deshalb den Seitenbau nicht anhalten:

| Warnung | Treffer | Was sie meldet |
|---|---|---|
| `assert_keine_stille_zeitumstellung` | 2 | Ankunft und Abfahrt von Halt `S2` (`Schifferstadt`) der Rücksprungnacht |
| `dbt_utils_accepted_range … delay_ab_sek` | 1 | die −83.050-s-Abfahrt der DE-Fixture |
| `assert_de_static_namen_eindeutig` | 1 | derselbe Schlüssel mit zwei Namen im Fahrplanarchiv |
| `assert_de_soll_an_vor_soll_ab` | 1 | die verdrehte Soll-Zeit von Fahrt `1012` |

Produktiv sind es sechs: dort schlägt `accepted_range` auf **beide** Verspätungsspalten an
und `assert_de_soll_zeit_im_fenster` kommt dazu. Beides braucht Datenmengen, die eine
Fixture nicht nachstellt.

Der Fremdverkehrsfilter (BPULS-070) ist dagegen an der Fixture geprüft: Fahrt `1013` hält
viermal — `A` kennt der Bahnfahrplan (der Zufallstreffer, der sie in den Scope gebracht
hat), `N1` bis `N3` nur der Nahverkehrsfeed. Sie ist damit gebietsfremd (3 > 1) und steht
in keinem Mart; `mart_datenqualitaet` weist sie als `fahrten_gebietsfremd = 1` aus.
**Gegengeprüft in beide Richtungen:** nimmt man `tests/fixtures/de_static/v=2026-08-13/nv/stops.parquet`
beiseite, taucht die Fahrt mit ihren vier Halten wieder auf, die Spalte steht auf 0 — und
der Lauf trägt die Warnung von `stg_de_nahverkehrshalt`, dass die Liste fehlt.

Der Gebietsausschluss (BPULS-075) ist ebenso an der Fixture geprüft, und zwar an der
Stelle, an der er wirken muss: `Heidelberg Hbf → Stuttgart Hbf (tief)` steht in **keinem**
Aggregat, `Mannheim Hbf → Heidelberg Hbf` schon; `mart_datenqualitaet` weist den Halt als
`halte_gebietsfremd = 1` aus. **Gegengeprüft in beide Richtungen:** nimmt man
`abschnitt_im_gebiet` aus `mart_verspaetungsentstehung` heraus, schlagen drei Tests an —
`assert_marts_ohne_gebietsfremde_abschnitte` (mit der Stuttgarter Zeile),
`assert_verspaetungsentstehung_summen_stimmen` und `assert_engpassknoten_deckt_a1`, weil
Detail- und Aggregatsicht dann auseinanderlaufen. Der Unit-Test
`mart_verspaetungsentstehung_rechnet_nur_im_gebiet` meldet es noch davor.

### Der erste Produktionslauf hat die Regel widerlegt, nicht die Fixture

Am 2026-08-23 lief BPULS-075 gegen echte Daten, und
`assert_marts_ohne_gebietsfremde_abschnitte` meldete **63 Bezeichnungen**. Die Regel hatte
gelautet „stop_id **oder** Name" — gleichrangig. Damit standen `Klandorf` (Brandenburg,
988 Züge) und `Pernink` (Tschechien, 476) in der Engpass-Rangliste: Ihre Nummer kommt
zufällig in der Gebietsliste vor. Das ist dieselbe Kollision wie in BPULS-070, eine Ebene
tiefer — und keine Fixture konnte sie zeigen, weil ihre IDs erfunden und damit disjunkt
sind.

Die Regel ist jetzt gestuft: **wo ein Name bekannt ist, entscheidet der Name**, die
stop_id trägt nur die Halte, die keine Fahrplanversion benennt. Die Gegenrichtung kostet
nichts — ein Gebietshalt mit rotierter ID trägt weiterhin seinen Namen, und die Liste ist
aus denselben `stops.txt` gebaut, aus denen `stg_de_static` die Namen zieht. Der Fall
steht als vierter Halt im Unit-Test `int_de_der_name_entscheidet_die_gebietszugehoerigkeit`;
mit der alten Regel schlägt er fehl.

Die Zahl, um die es ging, ist an Produktionsdaten bestätigt: `halte_gebietsfremd` liegt am
19.–21.08. bei **43,1 / 42,4 / 42,3 %** — die Stichprobe hatte 43,3 % gemessen.

`assert_de_namensquote_bricht_nicht_ein` sieht sich lokal **keinen einzigen Tag** an: er
verlangt mindestens 1.000 Halte je Betriebstag, und so groß ist keine Fixture. Grün heißt
hier also „nichts angesehen", nicht „nichts gefunden" — der Beleg, dass er trifft, ist
deshalb die Gegenprobe am Produktionsstand (2026-08-22): über die vier ausgelieferten
Betriebstage meldet er genau den 22.08. (`namensquote` 0,1295 gegen 0,3125 am besten
Vortag), ohne diesen Tag und über die Tage davor bleibt er leer.

### Die DE-Fixture trägt jeden Fall, den ein Test behauptet zu finden

`2026-08-13_snapshots.parquet` ist keine Stichprobe, sondern eine Sammlung konstruierter
Fälle — eine Fahrtnummer je Fall, damit ein Fehlschlag sofort auf den Fall zeigt. `1010`
und `1011` sind die beiden Formen des unbedienten Laufs (vollständig beobachtet gegen
unterwegs aufgegriffen), `1008` und `1009` die unplausiblen Verspätungen.

**`1012` ist die verdrehte Soll-Zeit** (BPULS-065). Halt `Q` wird in zwei Meldungen
beschrieben: die erste nennt nur die Ankunft (Prognose 20:00, 300 s Verspätung → Soll
19:55), die zweite fügt die Abfahrt hinzu, mit 420 s Verspätung auf eine Prognose, die nur
60 s später liegt (→ Soll 19:54). Die zurückgerechnete Soll-Abfahrt liegt damit **60 s vor
der Soll-Ankunft**, ohne dass an der Transformation etwas falsch wäre — genau der Fall, den
der Test als Warnung zählt statt zu entwerten.

Der Fall war bis dahin nur in Produktion aufgetreten (5 Halte am 2026-08-22); der Test war
lokal grün, ohne dass seine Mechanik je geprüft worden wäre. **Gegengeprüft in beide
Richtungen** (Zahlen vom 2026-08-22, vor dem Ausbau der CH-Quelle — die Differenz zählt,
nicht der Absolutwert): ohne die drei Zeilen `PASS=212 WARN=3`, mit ihnen
`PASS=211 WARN=4`, und die gemeldete Zeile trägt `sekunden_verdreht = 60`.

## Ausfälle kommen anders, als dieses Projekt zunächst annahm

Am Produktionsstand vom 2026-08-21 wies die Auswertung über drei Betriebstage und
**54.236 Fahrten exakt null Ausfälle** aus. Zwei Marts unabhängig.

> [!warning] Die erste Erklärung dafür war falsch (nachgemessen 2026-08-21)
> Angenommen wurde: ein vollständiger Ausfall komme als Meldung über die ganze Fahrt ohne
> `stop_time_update`, und `stg_de_gtfsrt` filtere die heraus. Daraufhin entstanden
> `stg_de_fahrtmeldung`, `stg_de_fahrplanhalt`, `int_de_ausfaelle` und die
> `stop_times`-Extraktion im Loader.
>
> **Die Auszählung des vollständigen bundesweiten Feeds am 2026-08-21 zeigt etwas
> anderes:** von **49.133 Fahrten** trug **keine einzige** `trip.schedule_relationship =
> CANCELED`. Alle standen auf `SCHEDULED`. Auf Halt-Ebene dagegen: **12.747 SKIPPED**, und
> bei **582 Fahrten** (1,2 %) war *jeder* Halt SKIPPED. Nur **67** Fahrten kamen ohne
> `stop_time_update` — und auch die alle `SCHEDULED`, also keine Ausfälle.
>
> **Dieser Feed drückt einen Ausfall über die Halte aus, nicht über die Fahrt.** GTFS-RT
> lässt beides zu; `zug_ausgefallen` liest die Form, die hier nicht vorkommt.
>
> Zwei Folgen: Erstens sind die betroffenen Züge **nicht verloren** — sie stehen als
> `halt_ausgelassen` in den Daten und gehen in `quote_planmaessig` ein. Die frühere
> Aussage „beide Quoten sind zu günstig, die Ausfälle fehlen im Nenner" war falsch und ist
> auf Seite und Methodik korrigiert. Zweitens ist die unten beschriebene Auflösung über den
> Soll-Fahrplan für diese Quelle **wirkungslos, aber nicht fehlerhaft**: sie wartet auf
> eine Meldungsform, die nicht kommt, und trägt jede Quelle, die sie benutzt. Ob „alle
> Halte gestrichen" als Ausfall gewertet werden soll, ist eine fachliche Entscheidung —
> **BPULS-064**.

Der gebaute Weg, unverändert gültig für jede Quelle mit trip-level-Meldung:

```
stg_de_fahrtmeldung   Meldungen ohne Halte (das Gegenstück zum Filter in stg_de_gtfsrt)
stg_de_fahrplanhalt   Soll-Halte je Version und Feed, Zeiten in Sekunden
int_de_ausfaelle      beides gejoint -> ein Halt-Ereignis je Soll-Halt
int_de_stop_events    union, damit Downstream nichts davon merkt
```

**Regel 9 gilt hier scharf.** Der Laufweg einer Fahrt ist Fahrplaninhalt und ändert sich
mit der Version; gejoint wird gegen die zum Betriebstag **gültige** Version — nicht gegen
die neueste, nicht über alle vereinigt. Das ist der Unterschied zu `stg_de_static`: ein
Stationsname ist eine Beschriftung und darf vereinigt werden, eine Halteabfolge nicht.
Beide falschen Strategien sind gegengeprüft: der Unit-Test
`int_de_ausfaelle_nimmt_die_zum_betriebstag_gueltige_version` schlägt bei jeder von beiden
fehl.

**Drei Fälle bleiben unauflösbar** und werden von `assert_de_ausfaelle_aufgeloest` als
Warnung gemeldet statt still verschluckt: kein Fahrplan älter als der Betriebstag
(betrifft jeden Tag vor der ersten Ladung), dieselbe `trip_id` in beiden Feeds derselben
Version (welcher Laufweg gemeint ist, wäre geraten), oder die Version kennt die `trip_id`
nicht.

**Voraussetzung ist `stop_times.parquet` im Fahrplanverzeichnis.** Der Loader schreibt es
seit BPULS-032 mit; ältere Versionen bekommen es über
`statictool -fahrplan-nachtragen` aus ihrem mitgespeicherten Archiv.

**Fehlt die Datei in *allen* Versionen, läuft dbt trotzdem durch — seit BPULS-062.**
Die Extraktion ist bewusst best-effort: schlüge sie fatal fehl, opferte man das
unwiederbringliche Archiv für eine Datei, die daraus jederzeit herstellbar ist. Damit ist
ein Stand ohne eine einzige `stop_times.parquet` ein möglicher Zustand — und
`stg_de_fahrplanhalt` liest per Glob. Ein Glob ohne Treffer ist in DuckDB ein **Fehler**,
kein leeres Ergebnis (geprüft mit 1.5.5; `error_on_no_files` kennt `read_parquet` dort
nicht), und dieser Fehler nähme den ganzen Lauf mit: auch Pünktlichkeit, Engpässe und
Pufferbilanz, die mit Ausfällen nichts zu tun haben.

`fahrplanhalt_dateien()` zählt deshalb vorher per `glob()` — das liefert bei null Treffern
eine leere Menge statt eines Fehlers — und das Modell schaltet auf einen leeren, aber
typgleichen Zweig um. **Leer heißt hier nicht still:** der Lauf trägt eine `WARNING` mit
dem Befehl, der es behebt, und `assert_de_ausfaelle_aufgeloest` meldet dann *jeden*
ausgefallenen Zug als unaufgelöst. Eine leere View, die niemand bemerkt, wäre genau der
Blindfleck, den BPULS-032 gerade geschlossen hat.

Gegenprobe (der Baum wird aus der vorhandenen Fixture abgeleitet, nicht dupliziert —
duplizierte Fixtures veralten):

```bash
# Relativ, nicht /tmp: dbt-duckdb laeuft hier als Windows-Prozess und loest einen
# Git-Bash-Pfad wie /tmp/... nicht auf -- der Lauf scheitert dann an der fehlenden
# stops.txt statt an der fehlenden stop_times.parquet, also am falschen Grund.
OHNE=../data/de_static_ohne_fahrplan
rm -rf "$OHNE" && cp -r tests/fixtures/de_static "$OHNE"
rm -f "$OHNE"/v=*/*/stop_times.parquet
dbt build --full-refresh --vars "{\"de_gtfsrt_glob\": \"tests/fixtures/de/*.parquet\", \"de_static_dir\": \"$OHNE\"}"
```

Erwartung: `PASS=213 WARN=5 ERROR=0` von 218 (Stand 2026-08-23) — die fünfte Warnung ist
`assert_de_ausfaelle_aufgeloest`. Lässt man `fahrplanhalt_dateien()` stattdessen fest `1`
zurückgeben, endet derselbe Lauf mit `ERROR=1` und übersprungenem Downstream; genau daran
hängt der Nutzen der Prüfung.

## Dubletten in den Rohdaten sind unschädlich — aber nur hier

Beim Redeploy startet Coolify den neuen Container, bevor er den alten stoppt. Am
2026-08-20 schrieben beide zwei Minuten lang gleichzeitig auf dasselbe Volume, dazu kommt
der Kaltstart-Burst des neuen Containers, dessen Dedup-Tracker leer ist. Dieselbe
Momentaufnahme steht danach mehrfach in den Rohdaten. Das ist Absicht in dem Sinne, dass
es die bessere von zwei Möglichkeiten ist: eine Lücke wäre nicht nachlieferbar, eine
Dublette schon (Regel 1).

**Gemessen, nicht angenommen** (2026-08-21): derselbe Fixture-Bestand einmal und zweimal
geladen, beide Male `--full-refresh`.

| | einfach | doppelt |
|---|---|---|
| `stg_de_gtfsrt` | 14 Zeilen | 28 Zeilen |
| `int_de_stop_events` | 12 | 12 |
| `mart_zuglauf`, Summe `delay_an_sek` | 660 | 660 |
| `mart_verspaetungsentstehung` | 2 | 2 |
| `mart_datenqualitaet`, Halte | 12 | 12 |

Die Rohschicht verdoppelt sich, **kein einziger Mart ändert sich**. Der Grund ist nicht
eine Deduplizierung, sondern das Korn: `int_de_stop_events` verdichtet über
`(trip_key, stop_sequence)` — mit `distinct`, `qualify row_number()` und `max()`, und
jede dieser drei Formen verschluckt eine identische Zweitzeile. Ein `dedupe`-Schritt in
`stg_de_gtfsrt` wäre damit wirkungslose Arbeit.

**Die Grenze steht genau dort, wo über Rohzeilen gezählt wird.** Ein Modell, das
Momentaufnahmen zählt statt sie zu verdichten — Änderungsrate, Poll-Abdeckung, die noch
fehlenden Feed-Lücken aus BPULS-024 —, zählt das Überlappungsfenster jedes Deploys
doppelt. Solche Modelle müssen auf
`(trip_id, start_date, stop_sequence, snapshot_timestamp)` deduplizieren; die Verdichtung
auf Halt-Ereignisse muss es nicht.

Festgenagelt ist das im Unit-Test `int_de_dubletten_aendern_das_ergebnis_nicht`. Er ist
gegengeprüft: ohne das `distinct` in der `halte`-CTE schlägt er fehl.

