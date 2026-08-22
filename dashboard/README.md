# Dashboard (Evidence.dev)

Fachliche Definitionen stehen im Vault (`Referenz/Bahnpuls_Analysen.md`,
`Referenz/Bahnpuls_Datenmodell.md`), die veröffentlichte Fassung der Kennzahlen-Definition
auf der Seite `pages/methodik.md` — hier steht nur, was den Betrieb dieses Ordners betrifft.

**Das Dashboard fragt ausschließlich `marts` ab** (CLAUDE.md Regel 11). Die
Source-Definitionen unter `sources/bahnpuls/` rechnen deshalb nichts aus — kommt eine
Kennzahl im Dashboard vor, hat sie vorher ein dbt-Modell. Was sie tun dürfen, ist
**begrenzen**: `zuglauf_auswahl.sql` liefert einen ausgeschriebenen Ausschnitt statt des
ganzen Marts, siehe unten.

## Lokal starten

Die Datenquelle ist die DuckDB-Datei aus `transform/`. Sie ist ein Build-Artefakt und
liegt nicht im Repo, **dbt muss also vorher gelaufen sein**:

```bash
cd transform
export DBT_PROFILES_DIR="$(pwd)"
../.venv/Scripts/dbt build --vars '{"ch_istdaten_glob": "tests/fixtures/ch/*_istdaten.csv", "de_gtfsrt_glob": "tests/fixtures/de/*.parquet", "de_static_dir": "tests/fixtures/de_static"}'

cd ../dashboard
npm install
npm run sources     # liest die Marts aus DuckDB nach static/data
npm run dev
```

Ohne echte Rohdaten zeigt das Dashboard die synthetischen Fixtures aus
`transform/tests/fixtures/`. Jede Seite weist diesen Datenstand aus — eine Zahl ohne
Herkunftsangabe wäre eine Behauptung.

**`npm run build` frischt die Daten nicht auf.** `npm run sources` ist ein eigener
Schritt. Lokal fällt das nicht auf, solange noch Ausgabe eines früheren Laufs herumliegt —
im frischen Container antwortet die Seite dann mit 200 und ist leer.

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

## Warum die Laufweg-Seite nur einen Ausschnitt anbietet

Evidence liefert seine Quelldaten **an den Browser** aus und rechnet dort. Ein
`select * from mart_zuglauf` ergab bei echten Daten 707.585 Zeilen und 347 MB je
Seitenaufruf — bei 36 Fixture-Zeilen war davon nichts zu merken, im Browser dann ein
Timeout beim Initialisieren der Datenbank.

`sources/bahnpuls/zuglauf_auswahl.sql` begrenzt deshalb auf **je Quelle die letzten drei
Betriebstage, darin je Tag und Linie die ersten sechs Fahrten** nach planmäßiger Abfahrt.
Die Grenze steht ausgeschrieben in der Datei und im Hinweiskasten der Seite — eine
Stichprobe, die sich nicht als solche zu erkennen gibt, ist schlimmer als keine.

Zwei Dinge daran sind nicht beliebig:

- **Die Quote gilt je Linie**, nicht je Tag insgesamt. Ein Schnitt über alle Fahrten
  (vorher: `row_number() over (order by trip_key)`) ist reproduzierbar, aber sinnlos —
  welche Linien überleben, entscheidet die Sortierung der Schlüssel, und der Linienfilter
  darüber kennte dann die halben Linien gar nicht.
- **Der Betriebstag wird als Text ausgewählt.** Der Wert eines Dropdowns landet über eine
  Zeichenkette wieder in der Abfrage; ein `DATE` wird dabei zu dem, was der Browser daraus
  macht (`Thu Aug 13 2026 …`), und der Vergleich liefe leer — ohne Fehlermeldung, nur mit
  leerer Seite.

Der eigentliche Umbau — serverseitige Abfrage oder je Fahrt vorbereitete Seiten — bleibt
offen und ist mit einem statischen Evidence-Build nicht zu haben.

## Warum die Engpass-Seite nach Verkehrsmenge auswählt und nach Verspätung sortiert

`sources/bahnpuls/engpassknoten.sql` liefert die **200 meistbefahrenen** Abschnitte der
letzten 30 Betriebstage, die Seite sortiert sie dann nach neu entstandener Verspätung je
Zug. Andersherum — nach Verspätung auswählen — wäre der Ausschnitt **zirkulär**: die
Rangliste suchte in einer Menge, die schon nach demselben Kriterium vorsortiert ist, und
jede Zahl darin sähe schlimmer aus, als sie ist. Der Preis ist ein Engpass auf einer wenig
befahrenen Strecke, der nicht auftaucht; er steht auf der Seite.

Die Abschnitte werden im Mart über den **Bahnhofsnamen** geschlüsselt, nicht über die
`stop_id`. Die Namensräume rotieren zwischen Fahrplan-Versionen und der Echtzeit-Feed
verwendet mehrere gleichzeitig — über die ID zerfiele ein physischer Engpass in mehrere
Zeilen mit je einem Bruchteil der Züge, und die Rangliste zeigte nicht den schlimmsten
Abschnitt, sondern den mit dem einheitlichsten Namensraum.

## Warum die Fahrplanreserve zwei Quellen hat

`pufferbilanz.sql` (Abschnitte) ist wie die Engpass-Quelle auf die 200 meistbefahrenen
Abschnitte begrenzt. `puffer_linien.sql` ist **nicht** daraus aggregiert, obwohl es
naheläge: die Liniensicht würde eine Linie dann nur auf ihrem befahrensten Teil
beurteilen — ausgerechnet die Nebenstrecke, auf der es klemmt, fiele heraus. Eine Zeile
je Linie ist ohnehin klein genug, um ohne Begrenzung auszukommen.

## Auch das Aggregat ist begrenzt

`sources/bahnpuls/puenktlichkeit.sql` liefert die letzten **30 Betriebstage je Quelle**,
und zwar von Anfang an. Bei rund 300 Linien und fünf Schwellen sind das 1.500 Zeilen je
Tag, im Jahr über eine halbe Million — dieselbe Rechnung, die die Laufweg-Seite schon
einmal unbenutzbar gemacht hat. Ein Monat trägt jede Aussage, die die Seite trifft.

Beim Aggregieren über Schwellen ist eine Falle eingebaut: alle Zählspalten außer
`halte_puenktlich` hängen **nicht** von der Schwelle ab und stehen deshalb fünfmal in der
Tabelle. Wer sie ohne `where schwelle_sek = …` summiert, zählt jeden Halt fünffach — die
Zahlen sähen nur größer aus, nichts würde fehlschlagen. Die Seitenabfragen filtern
deshalb ausdrücklich auf eine Schwelle, wo die Schwelle keine Rolle spielt.

## Wenn ein Bahnhof zweimal im Laufweg steht

Kopfmachen, Ringlauf, Wendefahrt: Ein Zug kann denselben Bahnhof zweimal anfahren. Die
Daten unterscheiden die beiden Halte über `halt_nr`, eine Diagrammachse über den Namen
aber nicht — beide Schritte fielen auf dieselbe Kategorie und würden zusammengezählt.
`pages/laufweg.md` hängt deshalb eine Nummer an den Namen, aber nur dort, wo er mehrdeutig
ist. Der Fall steckt als Fixture in `transform/tests/fixtures/ch/2026-08-12_istdaten.csv`
(Linie `S 1`, Bern–Thun–Spiez–Thun–Bern): ohne die Nummerierung werden aus acht
Achsenkategorien sechs.

## Deployment

Selbst gehostet unter Coolify auf dem eigenen VPS (ADR-012, war Cloudflare Pages). Der
Build läuft im Container zur Laufzeit über `deploy/dashboard-entrypoint.sh`: erst `dbt`
gegen die Rohdaten des Volumes, dann `npm run sources`, dann `npm run build`, dann `sirv`.
Stündlicher Rebuild als Coolify Scheduled Task. Einzelheiten in
`Referenz/Bahnpuls_Betrieb_und_Deployment.md`.

### `sirv` braucht `--dev`, sonst altert die Seite in den Zustand „ohne Daten"

`npm run serve` ruft `sirv build … --single --dev --quiet`. Das `--dev` sieht nach einem
Entwicklungsschalter aus und ist in Wahrheit die Bedingung dafür, dass der stündliche
Rebuild überhaupt etwas bewirkt.

Ohne `--dev` liest `sirv` das Verzeichnis **genau einmal beim Start** und baut daraus eine
feste Tabelle aus Pfad, Größe und Zeitstempel (`build.js`: `if (!opts.dev) totalist(dir,
…)`, danach `lookup = viaCache`). Danach gilt: was beim Start nicht da war, existiert für
den Server nicht. Der Rebuild schreibt seine Parquet-Dateien aber unter **neue**
Hash-Verzeichnisse — der Hash hängt an den Daten —, also unter Pfade, die in dieser Tabelle
fehlen. `manifest.json` wird dagegen am selben Pfad ersetzt und weiter ausgeliefert, nur
mit der beim Start gemerkten `Content-Length`.

Das Ergebnis ist die unangenehmste Form von kaputt: **die Seite antwortet mit 200, trägt
den richtigen Titel, und jede einzelne Datenquelle liefert 404.** Im Browser „No sources
found", von außen unauffällig. Genau so stand sie am 2026-08-21 zwischen dem
16:20-Rebuild und dem Fund.

Nachgemessen statt vermutet, mit derselben `sirv`-Version aus `node_modules`:

| | vor dem Start angelegt | nach dem Start angelegt |
|---|---|---|
| ohne `--dev` | 200 | **404** |
| mit `--dev` | 200 | 200 |

Der Preis ist ein `stat` je Anfrage statt einer Tabelle im Speicher — bei dieser Seite
nicht messbar. Die Alternative wäre, den Server nach jedem Rebuild neu zu starten; genau
das wollte `dashboard-rebuild.sh` vermeiden.

### Zwei Prüfungen nach jedem Rebuild, weil „HTTP 200" nichts über den Inhalt sagt

`deploy/dashboard-rebuild.sh` prüft am Ende zweierlei, und beide Prüfungen laufen, auch
wenn die erste schon anschlägt — sie beantworten verschiedene Fragen, und ein Abbruch nach
der ersten versteckt den zweiten Befund bis zum nächsten Lauf.

| | `dashboard-quellen-pruefen.js` | `dashboard-seitenabfragen-pruefen.py` |
|---|---|---|
| Frage | Liefert der Server die Dateien aus, die das Manifest nennt? | Passen die Seitenabfragen zu dem, was in diesen Dateien steht? |
| Prüft gegen | den laufenden Server auf `:3000` | die erzeugten Parquet-Dateien in DuckDB |
| Fand | die sieben 404er-Quellen (BPULS-063) | eine Spalte, die die Quellabfrage nicht liefert (BPULS-067) |

**Warum die zweite nötig ist:** `evidence build:strict` prüft keine Seitenabfrage gegen die
Daten. Am 2026-08-22 stand `fahrten_unbedienter_lauf_nicht_pruefbar` im Mart und in
`pages/puenktlichkeit.md`, fehlte aber in `sources/bahnpuls/puenktlichkeit.sql` — die zählt
ihre Spalten einzeln auf. Der strikte Bau lief grün; aufgefallen wäre es erst im Browser
des Lesers als fehlende Bindung. Gefunden hat es die Gegenprobe von Hand: die Seitenabfrage
wörtlich gegen die erzeugte Parquet-Datei laufen lassen, statt den Bau anzusehen.

Das Skript tut genau das für alle 31 Blöcke der fünf Seiten mit SQL. Es **bindet** nur
(`create view`), führt also nichts aus — gesucht sind fehlende Spalten, nicht
Zahlen. `${inputs.…}` wird durch eine Konstante ersetzt, `${abfrage}` durch eine temporäre
View desselben Namens; je Seite eine eigene Verbindung, damit eine Abfrage, die eine Abfrage
einer *anderen* Seite nennt, hier genauso scheitert wie im Browser. Laufzeit 0,9 s.

Drei Dinge sind ausdrücklich eigene Befunde und nicht als Ergebnis der Prüfung zu lesen:
das Fehlen des Skripts im Image (BPULS-065), eine im Manifest genannte, aber fehlende
Datei, und **null gefundene SQL-Blöcke** — ändert Evidence die Schreibweise der Blöcke,
meldete das Skript sonst stillschweigend „alle 0 binden".

Gegengeprüft in beide Richtungen: gegen den Stand *vor* `2295b14` meldet es genau die eine
fehlende Spalte, gegen den Stand danach alle 31 grün. Das Manifest ist dabei die Instanz,
nicht das Verzeichnis — lokal liegt dort noch ein `mart_zuglauf/` aus einem älteren Bau,
und ein Verzeichnislisting würde eine gelöschte Quelle als vorhanden ausweisen.
