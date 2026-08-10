# Transform (dbt-duckdb)

Layer-Aufbau (`staging` → `intermediate` → `marts`) und das `fct_stop_events`-Zielschema
stehen in `Referenz/Bahnpuls_Datenmodell.md` im Vault, nicht hier (keine Redundanz).
`intermediate/` und `marts/` sind bislang leere Ordner — erste Modelle folgen ab
BPULS-012.

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
