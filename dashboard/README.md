# Dashboard (Evidence.dev)

Fachliche Definitionen stehen im Vault (`Referenz/Bahnpuls_Analysen.md`,
`Referenz/Bahnpuls_Datenmodell.md`), die veröffentlichte Fassung der Kennzahlen-Definition
auf der Seite `pages/methodik.md` — hier steht nur, was den Betrieb dieses Ordners betrifft.

**Das Dashboard fragt ausschließlich `marts` ab** (CLAUDE.md Regel 11). Die
Source-Definitionen unter `sources/bahnpuls/` sind deshalb bewusst simple
`select * from mart_…` — kommt eine Kennzahl im Dashboard vor, hat sie vorher ein
dbt-Modell.

## Lokal starten

Die Datenquelle ist die DuckDB-Datei aus `transform/`. Sie ist ein Build-Artefakt und
liegt nicht im Repo, **dbt muss also vorher gelaufen sein**:

```bash
cd transform
export DBT_PROFILES_DIR="$(pwd)"
../.venv/Scripts/dbt build --vars '{"ch_istdaten_glob": "tests/fixtures/ch/*_istdaten.csv"}'

cd ../dashboard
npm install
npm run sources     # liest die Marts aus DuckDB nach static/data
npm run dev
```

Ohne echte Rohdaten zeigt das Dashboard die synthetischen Fixtures aus
`transform/tests/fixtures/ch/`. Jede Seite weist diesen Datenstand aus — eine Zahl ohne
Herkunftsangabe wäre eine Behauptung.

## Zwei Stolpersteine

**Der Pfad in `sources/bahnpuls/connection.yaml` ist relativ zum Source-Verzeichnis**,
nicht zum Projektordner — daher die drei Ebenen in `../../../data/bahnpuls.duckdb`. Ein
Pfad relativ zu `dashboard/` scheitert mit einer Fehlermeldung, die auf ein ganz anderes
Verzeichnis zeigt.

**`typescript` ist auf `5.4.2` festgenagelt.** Evidence 40 verlangt genau diese Version als
Peer-Dependency; ohne den Pin löst npm `typescript` als `latest` auf und die Installation
bricht mit `ERESOLVE` ab.

## Warum kein Wasserfall-Diagramm

Der Backlog sah für den Laufweg einen Wasserfall vor. Evidence hat keine
Wasserfall-Komponente; der übliche Nachbau stapelt einen unsichtbaren Sockel unter den
sichtbaren Balken. Der Trick kippt, sobald ein Verspätungsstand negativ wird (Zug ist
vor der Zeit) — gestapelte negative Werte laufen in der Chart-Bibliothek in die
Gegenrichtung, und das Bild wäre still falsch. Statt dessen zeigt `pages/laufweg.md` die
Beiträge je Abschnitt und Halt als Balken (nach Laufzeit und Haltezeit eingefärbt, was
der Wasserfall gar nicht unterscheiden würde) und den Verspätungsstand daneben als Linie.
Dieselbe Information, ohne die Fehlerquelle.

## Deployment

Noch keins. Build nach Cloudflare Pages ist BPULS-040 — die Build-Kette braucht dann
zuerst `dbt build`, dann `npm run sources && npm run build`.
