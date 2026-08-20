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

Erwartet CH-Ist-Daten-CSVs unter `../data/ch/*_istdaten.csv` (Pfad/Glob als dbt-Var
`ch_istdaten_glob` in `dbt_project.yml`, per `--vars` überschreibbar). Die DuckDB-Datei
landet unter `../data/bahnpuls.duckdb` — Build-Artefakt, nicht in Git.

## Stand BPULS-011

`stg_ch_istdaten` normalisiert das CH-Ist-Daten-Archiv (Spur A) auf das
`fct_stop_events`-Schema und ist gegen eine synthetische Fixture getestet (echte
CSV-Datei bisher nicht erreichbar — `data.opentransportdata.swiss` blockt automatisierte
Zugriffe aus dieser Umgebung mit HTTP 403, siehe Backlog BPULS-011). Zwei Annahmen sind
**noch nicht an einer echten Datei verifiziert**:

- Zeitformat: `ANKUNFTSZEIT`/`ABFAHRTSZEIT` als `DD.MM.YYYY HH:MM`, `AN_PROGNOSE`/
  `AB_PROGNOSE` als `DD.MM.YYYY HH:MM:SS`.
- Boolean-Spalten (`FAELLT_AUS_TF` u. a.) als literale Strings `true`/`false`.

Falls beides nicht stimmt, schlägt `dbt run` beim ersten echten Lauf laut fehl (bewusst
`strptime`/`::boolean`, nicht `try_`-Varianten) — kein stiller Datenfehler, siehe
Modell-Kommentare in `models/staging/ch/stg_ch_istdaten.sql`.

`stop_sequence` existiert in der CH-Quelle nicht und wird über die Soll-Zeit hergeleitet
(`row_number()` je `trip_key`). `halt_ausgelassen` ist für CH immer `false` — die Quelle
liefert keinen Flag für einen einzelnen ausgelassenen Halt, `DURCHFAHRT_TF` bedeutet
planmäßige Durchfahrt und ist keine Anomalie (siehe Modell-Kommentar).

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

Verifiziert wie BPULS-011 gegen **synthetische Fixtures** (echte CH-Datei weiterhin
nicht beschaffbar), siehe Abschnitt „Fixtures" unten.

## Fixtures und Testlauf

Die synthetischen CH-Dateien liegen unter `tests/fixtures/ch/` — im Repo, weil sie
Testdaten sind und keine Rohdaten. `data/ch/` bleibt echten Rohdaten vorbehalten, damit
sich Synthetisches und Echtes dort nie vermischen:

```bash
dbt build --vars '{"ch_istdaten_glob": "tests/fixtures/ch/*_istdaten.csv"}'
```

`2026-08-11_istdaten.csv` deckt ab: Pufferabbau (negatives Laufzeit-Delta), einen Halt
mit `AB_PROGNOSE_STATUS` ≠ `REAL` (Haltezeitanteil `NULL` statt 0), einen Endhalt ohne
Abfahrt, eine Nachtfahrt über Mitternacht (Betriebstag bleibt der Vortag), einen
ausgefallenen Zug und eine Buszeile (muss herausgefiltert werden).
`2026-10-25_istdaten.csv` ist die **Rücksprungnacht** — siehe BPULS-013.

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
Eingaben, die in echten Daten nicht verlässlich vorkommen. Für `stg_ch_istdaten` sind
Unit-Tests **nicht möglich**: dbt muss für eine gemockte Eingabe die Spalten der
Relation introspizieren, und die Quelle ist über `external_location` nur ein
`read_csv`-Ausdruck, keine Relation. Diese Ebene wird deshalb über die Fixture-Dateien
abgedeckt.

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
CH-Fixture der Rücksprungnacht (2026-10-25) stand als `max(betriebstag)` in den Marts und
schluckte den DE-Tag 2026-08-13 vollständig.

**Regel:** nach dem Anschluss einer Quelle oder beim Nachladen historischer Tage einmal

```bash
dbt build --full-refresh
```

Im laufenden Betrieb ist das nicht nötig und auch nicht erwünscht — dort ist genau das
Vorwärtsladen gewollt.

## Lauf gegen die Fixtures

```bash
dbt build --vars '{"ch_istdaten_glob": "tests/fixtures/ch/*_istdaten.csv", "de_gtfsrt_glob": "tests/fixtures/de/*.parquet"}'
```

Erwartung: alle Tests grün bis auf `assert_keine_stille_zeitumstellung`, das mit
`severity: warn` konfiguriert ist und die Halte der Rücksprungnacht meldet — so gewollt.

