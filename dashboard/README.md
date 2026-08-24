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
../.venv/Scripts/dbt build --vars '{"de_gtfsrt_glob": "tests/fixtures/de/*.parquet", "de_static_dir": "tests/fixtures/de_static"}'

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

## Deutsche Zahlen — und warum dafür in `node_modules` gefasst wird

`32,126.0` liest ein deutscher Leser nicht nur ungewohnt, sondern falsch: als
zweiunddreißig Komma eins. Die Seite wird in Bewerbungen verlinkt; eine im ersten Blick
falsch gelesene Zahl ist teurer als eine fehlende Seite (BPULS-080).

**Über `fmt` ist das nicht zu erreichen.** Evidence formatiert jede Zahl — BigValue,
DataTable, Diagrammachse, Tooltip — über `ssf` (SheetJS), und `ssf` kennt keine Locale:
Gruppierungs- und Dezimaltrenner sind fest englisch verdrahtet. Gemessen an Evidence
40.1.8, der zum Zeitpunkt der Umsetzung neuesten Fassung: `[$-407]#,##0.0` wird als
Währungsangabe missverstanden (`$12,345.7`), `#.##0,0` als kaputter Code (`12345.678`).
Einen Locale-Haken hat Evidence nicht.

Der naheliegende Ausweg — die Zahlen in SQL mit `format()` zu Zeichenketten machen —
kostet mehr als er bringt: Zeichenketten kämen ohne Sortierung in die Tabellen und
überhaupt nicht an die Diagrammachsen, die ihre Werte selbst formatieren. Die Prosa
deutsch und die Achse daneben englisch wäre schlechter als der einheitlich englische
Zustand vorher.

Deshalb setzt `tools/zahlen-auf-deutsch-einbauen.mjs` an der einen Stelle an, durch die
alle Zahlen laufen: es biegt die drei `ssf`-Importe in
`@evidence-dev/component-utilities` auf `tools/ssf-de.js` um und pinnt den einen
`toLocaleString`-Aufruf in `autoFormatting.js` auf `de-DE`. `ssf-de.js` reicht jeden
Aufruf an `ssf` durch und tauscht danach die Trenner — nur innerhalb zusammenhängender
Ziffernläufe, damit ein Literal wie `#,##0 "Min."` seinen Punkt behält, und nur bei
Zahlen, damit Datumsangaben (`24.08.2026`) unangetastet bleiben.

**Das Skript läuft als `pre`-Schritt vor `sources`, `build`, `build:strict` und `dev`,
nicht als `postinstall`:** `node_modules` wird im Image in einer eigenen Stufe installiert
und danach nur kopiert — ein `postinstall`-Haken dort sähe die Datei gar nicht. Es ist
wiederholbar und meldet beim zweiten Lauf `zahlen: schon deutsch`. Findet es einen
Ankerpunkt nicht, **bricht es ab**, statt still zu überspringen; ein übersprungener
Einbau baute eine grüne Seite mit englischen Zahlen.

`npm run test:formatierung` prüft die Fälle einzeln (Tausendertrenner, Nachkommastellen,
negative Werte, Prozent, Literal im Formatcode, Datum, Text, Spalten ganz ohne
Formatangabe). **Nach jedem Evidence-Update gehört beides gemacht:** die Tests laufen
lassen *und* eine Zahl auf der gebauten Seite ansehen. Ein Ankerpunkt kann weiterbestehen,
während die Formatierung längst woanders sitzt — dann meldet das Skript grün und die Seite
zeigt wieder `32,126.0`.

**Der Datumscode muss gequotet werden.** `fmt="dd.mm.yyyy"` wirft in `ssf`
`bad second format` — es liest den Punkt hinter `mm` als Bruchteil einer Sekunde —, und
Evidence fängt den Fehler ab und fällt auf eine andere Darstellung zurück. Auf den Seiten
steht deshalb `fmt='dd"."mm"."yyyy'`.

## Bahnhofsseiten: warum eine Liste in `svelte.config.js` steht

`pages/bahnhof/[bahnhof].md` ist **eine** Datei und wird zu einer Seite je Knoten
(BPULS-061). Welche das sind, steht in `dashboard/svelte.config.js` als
`kit.prerender.entries` — Evidence mischt eine solche Datei aus dem Projektwurzelverzeichnis
in seine eigene SvelteKit-Konfiguration (`loadUserConfiguration`).

**Ohne diese Liste bliebe jede Bahnhofsseite ungebaut, und niemand erführe es.** SvelteKit
findet parametrierte Seiten nur über Links im **vorgerenderten** HTML. Gemessen am Bau:
`build/bahnhoefe/index.html` enthält **null** `href` auf `/bahnhof/…` — die Tabelle dort
entsteht erst im Browser aus DuckDB-WASM. `<Value>` und `<BigValue>` rendern dagegen schon
serverseitig; die Unterscheidung ist nicht offensichtlich und war der eigentliche Befund
dieser Aufgabe. Der Adapter läuft mit `strict: false`, ein Fehlschlag wäre also stumm.

Die Liste kommt aus `transform/seeds/knoten.csv` — **derselben Datei**, aus der
`mart_bahnhof.ist_knoten` entsteht. Eine zweite Aufzählung liefe auseinander, und das
Ergebnis wären Seiten ohne Zahlen oder Zahlen ohne Seite. Ein neuer Knoten ist damit eine
Zeile in der CSV; danach ist ein `--full-refresh` fällig, sonst trägt nur der jüngste
Betriebstag das neue `ist_knoten` (steht in `transform/README.md`).

**Der Titel im Browser-Tab bleibt statisch, die Überschrift nicht.** Evidence baut aus dem
Frontmatter ein eigenes `<svelte:head>` in jede Seite, und Svelte lässt genau eines je
Komponente zu — ein zweites bricht den Bau ab (`A component can only have one
<svelte:head> tag`, am Bau geprüft). Der Bahnhofsname steht deshalb über `<Value>` als
einzige `h1` auf der Seite, und `hide_title: true` unterdrückt die Überschrift aus dem
Frontmatter, damit nicht zwei dastehen. Im Tab steht für alle 44 Seiten „Bahnhof"; wer das
ändern will, kommt an `handle-og.cjs` in `@evidence-dev/preprocess` nicht vorbei.

**Die Seite wird über den `slug` angesprochen, nicht über den Namen.** Er steht ebenfalls im
Seed, statt aus dem Namen abgeleitet zu werden: die Adresse wird zitiert (BPULS-077) und
darf sich nicht ändern, weil jemand die Umlautregel anfasst.

## Was eine Seite im Browser kostet — gemessen, nicht geschätzt

`deploy/dashboard-ladezeit-messen.js` laedt jede Seite in einem echten Chrome (headless,
ueber das DevTools-Protokoll, ohne zusaetzliche Abhaengigkeit) und liest danach die
**Ressourcen-Zeitleiste des Browsers** aus. Aufruf:

```bash
node deploy/dashboard-ladezeit-messen.js                       # gegen die Produktionsseite
node deploy/dashboard-ladezeit-messen.js --langsam             # 1,6 Mbit/s, 150 ms RTT
node deploy/dashboard-ladezeit-messen.js http://localhost:3000 # gegen einen lokalen Bau
```

**Messung vom 2026-08-24** gegen `bahnpuls.dasdann.jetzt`, kalter Cache, je Seite einmal
vollstaendig durchgescrollt:

| | schnelle Leitung | gedrosselt (1,6 Mbit/s) |
|---|---|---|
| Uebertragen je Seite | 1,5–3,7 MB | 3,6–3,7 MB |
| davon Parquet | **0,00 MB** | **0,00 MB** |
| davon vorgerechnete `.arrow` | ≤ 0,09 MB | ≤ 0,09 MB |
| Text steht (DOMContentLoaded) | 0,2–0,9 s | ~1,6 s |
| alles nachgeladen | 0,8–8,0 s | ~19 s |
| groesste einzelne Datei | 1,88 MB (JS) | 1,88 MB (JS) |

**Der Befund ist ein anderer als erwartet.** Die Sorge aus BPULS-056 war die Datenmenge —
gemessen wird beim Aufruf aber **keine einzige Parquet-Datei** geholt. Evidence liefert die
beim Bau vorgerechneten Abfrageergebnisse aus (`/api/prerendered_queries/*.arrow`, wenige
Kilobyte), und die Zahlen stehen ohnehin schon im vorgerenderten HTML. Selbst das
Umstellen des Betriebstags auf der Laufweg-Seite loeste **null** zusaetzliche Anfragen aus.
Die Grenzen der Quellen (3 Tage x 6 Fahrten, 200 Abschnitte, 30 Tage) sind damit derzeit
nicht der Engpass — **das JavaScript ist es**: rund 3 MB je Seite, davon 1,88 MB in einem
einzigen Bundle.

Fuer eine Vorfuehrung heisst das: die Seite ist gedrosselt nach knapp zwei Sekunden lesbar,
weil der Text und die Zahlen vorgerendert sind; die Diagramme kommen nach. Was **nicht**
gemessen ist: eine Auswahl, die es beim Bau nicht gab (etwa ein Betriebstag, den die
vorgerechneten Ergebnisse nicht abdecken) — dort muesste DuckDB-WASM tatsaechlich laden.
Diese Grenze steht als offener Punkt an BPULS-078.

**Drei Dinge, an denen die Messung zuerst gescheitert ist** — sie stehen hier, damit sie
niemand noch einmal sucht:

1. **Nicht scrollen heisst nicht messen.** Evidence laedt die Diagrammbibliothek erst, wenn
   ein Diagramm ins Bild kommt. Ohne Scrollen meldete dieselbe Seite 1,5 statt 3,6 MB.
2. **Eigene Buchfuehrung ueber Netzwerkereignisse geht schief.** Weiterleitungen melden
   `requestWillBeSent` zweimal, und fuer Anfragen aus einem spaet angehaengten Worker fehlt
   die URL. Die Zeitleiste des Browsers kennt beides richtig.
3. **Ein `element.click()` bedient kein `cmdk`-Auswahlfeld.** Die Auswahl blieb stehen, die
   Messung meldete "0 Anfragen" und sah wie ein gutes Ergebnis aus. Jetzt laeuft es ueber
   Tastatur (`ArrowDown`, `Enter` **mit** `char`-Ereignis), und das Skript prueft danach,
   ob sich der Wert wirklich geaendert hat — sonst meldet es einen Befund.

## Feste Einstiegspunkte (BPULS-077)

Die Laufweg-Seite oeffnet nicht mehr auf dem neuesten, sondern auf dem **juengsten
vollstaendig erhobenen** Betriebstag (Abfrage `standard`). Sonst begaenne eine Vorfuehrung
im schlechtesten Fall mit einer Fussnote statt mit einem Zug.

Die Auswahl laesst sich zusaetzlich in der Adresse mitgeben
(`/laufweg?tag=…&linie=…&fahrt=…`). **Die Parameter werden ueber `window.location` gelesen,
nicht ueber `$page.url.searchParams`:** SvelteKit verbietet den Zugriff darauf in einer
vorgerenderten Seite und bricht den Bau mit einem 500er ab. Beim Vorrendern gibt es kein
`window`, dann gilt die Vorauswahl.

Faellt eine verlinkte Fahrt aus dem Fenster der letzten drei Betriebstage, waehlt die Seite
**nichts** aus — deshalb steht dort ein sichtbarer Hinweis mit dem Weg zurueck auf den
aktuellen Stand. Ein Link ohne Parameter altert nicht; ein Bahnhofslink
(`/bahnhof/<slug>/`) ohnehin nicht, seine Adresse kommt aus dem Seed.

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
ist. Der Fall steckt als Fahrt `1014` in `transform/tests/fixtures/de/2026-08-13_snapshots.parquet`
(Mannheim–Heidelberg–Mannheim): ohne die Nummerierung werden aus drei Achsenkategorien
zwei, und die beiden Mannheimer Halte fallen zu einem Balken zusammen.

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

**Eine Ebene höher gilt dasselbe.** Ein `<Column id=…>` auf eine Spalte, die die Abfrage
nicht liefert, ist kein Bindungsfehler — im Browser bleibt einfach eine Spalte leer, ohne
Meldung. Das Skript hält deshalb auch `data={abfrage}` und die Spaltenattribute (`id`, `x`,
`y`, `series`, `value`, `label`) der Komponenten gegen die Spalten der genannten Abfrage;
`<Column>` erbt die Abfrage der umschließenden `<DataTable>`. 116 solcher Angaben auf den
fünf Seiten. `sort` steht bewusst **nicht** in der Liste: in Evidence schaltet es die
Sortierung ein oder aus und benennt keine Spalte.

Bindet eine Abfrage nicht, meldet das Skript ihre Komponenten **nicht** zusätzlich als
„unbekannte Abfrage" — der Befund steht schon da, und eine zweite Meldung schickte die
Suche an die falsche Stelle.

**Exit 2 heißt „etwas gefunden", jeder andere Fehlschlag heißt „der Prüfer selbst ist
gescheitert"** — und das Rebuild-Skript schreibt beide Fälle verschieden hin. Ohne diese
Unterscheidung meldete ein fehlendes Modul oder ein Tippfehler im Prüfer denselben Satz wie
eine falsche Seitenabfrage, und der Satz wäre gelogen. Genau daran hing BPULS-065.

Vier Dinge sind ausdrücklich eigene Befunde und nicht als Ergebnis der Prüfung zu lesen:
das Fehlen des Skripts im Image (BPULS-065), eine im Manifest genannte, aber fehlende
Datei, **null gefundene SQL-Blöcke** und **null gefundene Spaltenangaben**. Die letzte
Falle ist beim Bau dieses Skripts einmal zugeschnappt: ein verunglückter Ausdruck im
Tag-Muster ließ es kein einziges Markup finden, und der Lauf meldete grün.

Gegengeprüft in beide Richtungen: gegen den Stand *vor* `2295b14` meldet es genau die eine
fehlende Spalte, gegen den Stand danach alle 31 grün; ein absichtlich verdrehtes
`<Column id=…>` und ein `data={…}` auf eine nicht existierende Abfrage werden einzeln
benannt. Das Manifest ist dabei die Instanz, nicht das Verzeichnis — lokal liegt dort noch
ein `mart_zuglauf/` aus einem älteren Bau, und ein Verzeichnislisting würde eine gelöschte
Quelle als vorhanden ausweisen.
