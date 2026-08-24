"""Prueft die SQL-Bloecke der Evidence-Seiten gegen die erzeugten Quelldateien (BPULS-067).

**Warum das noetig ist:** `evidence build:strict` prueft die Seitenabfragen nicht gegen
die Daten. Am 2026-08-22 stand `fahrten_unbedienter_lauf_nicht_pruefbar` im Mart und in
der Seite, fehlte aber in der Quellabfrage -- die zaehlt ihre Spalten einzeln auf. Der
strikte Bau lief gruen, und der Fehler waere erst im Browser des Lesers aufgetreten, als
fehlende Bindung. Von aussen ist die Seite dabei nicht von einer gesunden zu
unterscheiden: HTTP 200, richtiger Titel, richtige Groesse.

Gefunden hat es damals die Gegenprobe von Hand -- die Seitenabfrage woertlich gegen die
erzeugte Parquet-Datei laufen lassen, statt den Bau anzusehen. Genau das tut dieses
Skript, fuer jeden Block jeder Seite.

Gebunden wird nur (`create view`), nicht ausgefuehrt: gesucht sind fehlende Spalten und
Tippfehler, nicht Zahlen. Die Werte der Eingabefelder sind dafuer gleichgueltig und
werden durch eine Konstante ersetzt.

Dieselbe Frage gilt eine Ebene hoeher: `<Column id=…>` auf eine Spalte, die die Abfrage
nicht liefert, ist **kein** Bindungsfehler -- im Browser bleibt die Spalte einfach leer.
Deshalb werden auch `data={abfrage}` und die Spaltenattribute der Komponenten gegen die
Spalten der genannten Abfrage gehalten (siehe `komponenten_pruefen`).

Aufruf: /opt/venv/bin/python /app/deploy/dashboard-seitenabfragen-pruefen.py
        [manifest.json] [seitenverzeichnis]
"""

import json
import pathlib
import re
import sys

import duckdb

STANDARD_MANIFEST = "/app/dashboard/build/data/manifest.json"
MANIFEST = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else STANDARD_MANIFEST)
SEITEN = pathlib.Path(sys.argv[2] if len(sys.argv) > 2 else "/app/dashboard/pages")

# ```sql name ... ``` -- der Name ist optional, Evidence erlaubt auch namenlose Bloecke.
BLOCK = re.compile(r"^```sql[ \t]*([A-Za-z_][A-Za-z0-9_]*)?[^\n]*\n(.*?)^```", re.M | re.S)
EINGABE = re.compile(r"\$\{\s*inputs\.[^}]*\}")
# Seitenparameter einer vorgerenderten Seite (`pages/bahnhof/[bahnhof].md`,
# BPULS-061). Fuer die Bindung ist der Wert genauso egal wie bei einem Auswahlfeld --
# geprueft wird, ob die Abfrage ihre Spalten findet, nicht welcher Bahnhof herauskommt.
SEITENPARAMETER = re.compile(r"\$\{\s*params\.[^}]*\}")
ABFRAGE = re.compile(r"\$\{\s*([A-Za-z_][A-Za-z0-9_]*)\s*\}")
REST = re.compile(r"\$\{[^}]*\}")

# Komponenten: oeffnendes Tag mit Attributen, oder schliessendes Tag.
TAG = re.compile(r"</([A-Za-z][A-Za-z0-9]*)>|<([A-Z][A-Za-z0-9]*)\b([^>]*?)(/?)>", re.S)
ATTR = re.compile(r"([A-Za-z][A-Za-z0-9_]*)\s*=\s*(\{[^}]*\}|\"[^\"]*\"|'[^']*'|[^\s>]+)")
NUR_NAME = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
# `y={["a", "b"]}` -- ein Spaltenattribut darf mehrere Spalten nennen (LineChart mit zwei
# Reihen). Ohne diese Form geprueft zu bekommen, waere die zweite Reihe genau die stille
# Luecke, gegen die dieses Skript gebaut ist.
SPALTENLISTE = re.compile(r"^\{\s*\[(.*)\]\s*\}$", re.S)

# Attribute, deren Wert ein Spaltenname der zugehoerigen Abfrage ist. `sort` steht
# bewusst nicht dabei: in Evidence schaltet es die Sortierung ein oder aus, es benennt
# keine Spalte -- als Spaltenname geprueft waere es eine Falschmeldung.
SPALTEN_ATTRIBUTE = {"x", "y", "series", "value", "label", "id"}

# `<DropdownOption value="%" />` nennt einen Wert der Daten, keine Spalte.
OHNE_SPALTEN = {"DropdownOption"}

# Fuer die Bindung ist der Wert egal; 0 passt als Zahl und in Anfuehrungszeichen als Text.
PLATZHALTER = "0"

befunde = []


def abbrechen(zusammenfassung):
	"""Erst die gesammelten Befunde, dann die Zusammenfassung.

	Die Zusammenfassung darf die Einzelbefunde nie verdecken: eine im Manifest genannte,
	aber fehlende Datei ist etwas anderes als ein leeres Manifest, und wer nur den letzten
	Satz liest, sucht sonst an der falschen Stelle (BPULS-065).

	**Exit 2 heisst Befund, jeder andere Fehlschlag heisst kaputter Pruefer.** Ohne diese
	Unterscheidung waere ein fehlendes Modul oder ein Tippfehler in diesem Skript nicht
	von einer falschen Seitenabfrage zu unterscheiden -- genau die Verwechslung, die den
	Rebuild-Task 14 Stunden lang das Gegenteil der Wahrheit melden liess.
	"""
	for zeile in befunde:
		print(f"seitenabfragen: {zeile}", file=sys.stderr)
	print(f"seitenabfragen: BEFUND -- {zusammenfassung}", file=sys.stderr)
	sys.exit(2)


def quellen_aus_manifest():
	"""Die im Manifest genannten Dateien, nicht die auf der Platte gefundenen.

	Ein Verzeichnis aus einem aelteren Bau bleibt liegen (lokal etwa `mart_zuglauf`) und
	wuerde eine geloeschte Quelle als vorhanden ausweisen -- der Fehler saehe dann aus wie
	ein gesunder Bau.
	"""
	try:
		daten = json.loads(MANIFEST.read_text(encoding="utf-8"))
	except (OSError, ValueError) as fehler:
		# Ein fehlendes oder unleserliches Manifest ist eine Aussage ueber den Bau, nicht
		# ueber dieses Skript -- es gehoert als Befund gemeldet, nicht als Absturz.
		abbrechen(f"das Manifest {MANIFEST} ist nicht lesbar: {fehler}")
	wurzel = MANIFEST.parent.parent
	for quelle, pfade in (daten.get("renderedFiles") or {}).items():
		for p in pfade:
			teile = str(p).split("/")
			if quelle not in teile:
				befunde.append(f"manifest nennt einen Pfad ohne Quellenname: {p}")
				continue
			abfrage = teile[teile.index(quelle) + 1]
			# Die Pfade im Manifest sind relativ zur Build-Wurzel und tragen ein
			# "static/"-Praefix, das im ausgelieferten Verzeichnis nicht vorkommt.
			datei = wurzel / str(p).removeprefix("static/")
			if not datei.exists():
				befunde.append(f"{quelle}.{abfrage}: das Manifest nennt {p}, die Datei fehlt")
				continue
			yield quelle, abfrage, datei


def einsetzen(sql):
	sql = EINGABE.sub(PLATZHALTER, sql)
	sql = SEITENPARAMETER.sub(PLATZHALTER, sql)
	sql = ABFRAGE.sub(lambda m: '"' + m.group(1) + '"', sql)
	offen = REST.search(sql)
	if offen:
		# Nicht stillschweigend stehen lassen: ein nicht ersetzter Ausdruck wuerde als
		# Syntaxfehler durchschlagen oder -- schlimmer -- zufaellig binden.
		return sql, f"unbekannter Ausdruck {offen.group(0)}, das Skript kennt ihn nicht"
	return sql, None


def spaltennamen(wert):
	"""Die Spalten, die ein Attribut nennt -- eine, oder mehrere als Liste."""
	wert = wert.strip()
	liste = SPALTENLISTE.match(wert)
	if liste:
		namen = [teil.strip().strip('"').strip("'") for teil in liste.group(1).split(",")]
		return [name for name in namen if name]
	return [wert.strip('"').strip("'")]


def komponenten_pruefen(text, spalten, benannt, kennung_seite):
	"""Haelt `data={abfrage}` und die Spaltenattribute der Komponenten gegeneinander.

	Dieselbe Fehlerklasse eine Ebene ueber der Abfrage: `<Column id=…>` auf eine Spalte,
	die die Abfrage nicht liefert, bleibt im Browser eine leere Spalte -- keine Meldung,
	keine Bindungsfehler, nur eine Tabelle, in der etwas fehlt.

	`<Column>` steht innerhalb von `<DataTable data={…}>` und erbt dessen Abfrage; der
	Stapel bildet genau diese Verschachtelung ab.

	Gibt die Zahl der geprueften Spaltenbezuege zurueck -- der Aufrufer muss merken, wenn
	das keine sind.
	"""
	bezuege = 0
	stapel = []
	for treffer in TAG.finditer(text):
		schliessend, name, roh, selbstschliessend = treffer.groups()
		if schliessend:
			while stapel and stapel.pop()[0] != schliessend:
				pass
			continue

		attribute = dict(ATTR.findall(roh or ""))
		geerbt = stapel[-1][1] if stapel else None
		abfrage = geerbt

		if "data" in attribute:
			wert = attribute["data"].strip()
			inhalt = wert[1:-1].strip() if wert.startswith("{") and wert.endswith("}") else wert
			if not NUR_NAME.match(inhalt):
				befunde.append(f"{kennung_seite} / <{name}>: data={wert} ist kein einfacher Abfragename, das Skript kennt die Form nicht")
				abfrage = None
			elif inhalt in spalten:
				abfrage = inhalt
			elif inhalt in benannt:
				# Die Abfrage gibt es, sie hat nur nicht gebunden -- das steht schon als
				# eigener Befund da. Sie hier zusaetzlich als unbekannt zu melden,
				# schickte die Suche an die falsche Stelle.
				abfrage = None
			else:
				befunde.append(f"{kennung_seite} / <{name}>: data={{{inhalt}}} nennt keine Abfrage dieser Seite")
				abfrage = None

		if not selbstschliessend:
			stapel.append((name, abfrage))

		if abfrage is None or name in OHNE_SPALTEN:
			continue

		for attribut, wert in attribute.items():
			if attribut not in SPALTEN_ATTRIBUTE:
				continue
			for einzeln in spaltennamen(wert):
				bezuege += 1
				if not NUR_NAME.match(einzeln):
					# Ausdruck statt Spaltenname -- nicht stillschweigend uebergehen.
					befunde.append(f"{kennung_seite} / <{name} {attribut}=…>: {einzeln} ist kein einfacher Spaltenname, das Skript kennt die Form nicht")
					continue
				if einzeln.lower() not in spalten[abfrage]:
					befunde.append(f"{kennung_seite} / <{name} {attribut}={einzeln}>: die Abfrage {abfrage} liefert diese Spalte nicht")

	return bezuege


quellen = list(quellen_aus_manifest())
if not quellen:
	abbrechen("keine einzige der im Manifest genannten Quelldateien ist benutzbar")

seiten = sorted(SEITEN.rglob("*.md"))
if not seiten:
	abbrechen(f"keine Seite unter {SEITEN}")

geprueft = 0
bezuege = 0
for seite in seiten:
	text = seite.read_text(encoding="utf-8")
	bloecke = BLOCK.findall(text)
	if not bloecke:
		continue

	# Je Seite eine eigene Verbindung: eine Abfrage, die eine Abfrage einer *anderen*
	# Seite nennt, ist im Browser ein Fehler und muss auch hier einer sein.
	con = duckdb.connect()
	for quelle, abfrage, datei in quellen:
		con.execute(f'create schema if not exists "{quelle}"')
		# CREATE VIEW nimmt keine Parameter -- der Pfad wird eingesetzt, Hochkommas verdoppelt.
		pfad = str(datei).replace("'", "''")
		con.execute(f"""create view "{quelle}"."{abfrage}" as select * from read_parquet('{pfad}')""")

	spalten = {}
	for name, sql in bloecke:
		geprueft += 1
		kennung = f"{seite.name} / {name or '(ohne Namen)'}"
		sql, fehler = einsetzen(sql)
		if fehler:
			befunde.append(f"{kennung}: {fehler}")
			continue
		try:
			# Auch namenlose Bloecke laufen ueber eine View: `explain` wuerde zusaetzlich
			# den Optimierer anwerfen und koennte an einem eingesetzten Platzhalter
			# scheitern, statt an dem, wonach hier gesucht wird.
			con.execute(f'create or replace temp view "{name or "__ohne_namen"}" as {sql}')
			if name:
				spalten[name] = {
					z[0].lower() for z in con.execute(f'describe "{name}"').fetchall()
				}
		except Exception as fehler:  # noqa: BLE001 - jede Bindungsart ist ein Befund
			befunde.append(f"{kennung}: {str(fehler).splitlines()[0]}")

	# Die Bloecke aus dem Text nehmen, sonst liest der Tag-Scanner SQL als Markup
	# (`<` und `>` kommen in Vergleichen vor).
	benannt = {name for name, _ in bloecke if name}
	bezuege += komponenten_pruefen(BLOCK.sub("", text), spalten, benannt, seite.name)
	con.close()

if geprueft == 0:
	# Nicht als Erfolg durchgehen lassen: aendert Evidence die Schreibweise der Bloecke,
	# faende dieses Skript nichts mehr und meldete stillschweigend "alle 0 binden".
	abbrechen(f"keine einzige SQL-Abfrage in {len(seiten)} Seiten gefunden")

if bezuege == 0:
	# Dieselbe Falle eine Ebene hoeher, und sie ist beim Bau dieses Skripts einmal
	# zugeschnappt: ein verunglueckter Ausdruck im Tag-Muster liess es kein einziges
	# Markup finden, und der Lauf meldete gruen.
	abbrechen(f"keine einzige Spaltenangabe in den Komponenten von {len(seiten)} Seiten gefunden")

if befunde:
	# Die Zusammenfassung nennt beide Ebenen, weil sie beide melden kann: eine Abfrage,
	# die nicht bindet, ist etwas anderes als eine Komponente, die auf eine Spalte zeigt,
	# die es nicht gibt -- und wer nur die letzte Zeile liest, soll nicht falsch suchen.
	wort = "Befund" if len(befunde) == 1 else "Befunde"
	abbrechen(
		f"{len(befunde)} {wort} aus {geprueft} Abfragen und {bezuege} Spaltenangaben"
	)

print(
	f"seitenabfragen: alle {geprueft} binden gegen die {len(quellen)} ausgelieferten "
	f"Quellen, {bezuege} Spaltenangaben in den Komponenten stimmen"
)
