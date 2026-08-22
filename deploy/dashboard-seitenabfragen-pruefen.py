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
ABFRAGE = re.compile(r"\$\{\s*([A-Za-z_][A-Za-z0-9_]*)\s*\}")
REST = re.compile(r"\$\{[^}]*\}")

# Fuer die Bindung ist der Wert egal; 0 passt als Zahl und in Anfuehrungszeichen als Text.
PLATZHALTER = "0"

befunde = []


def abbrechen(zusammenfassung):
	"""Erst die gesammelten Befunde, dann die Zusammenfassung.

	Die Zusammenfassung darf die Einzelbefunde nie verdecken: eine im Manifest genannte,
	aber fehlende Datei ist etwas anderes als ein leeres Manifest, und wer nur den letzten
	Satz liest, sucht sonst an der falschen Stelle (BPULS-065).
	"""
	for zeile in befunde:
		print(f"seitenabfragen: {zeile}", file=sys.stderr)
	print(f"seitenabfragen: BEFUND -- {zusammenfassung}", file=sys.stderr)
	sys.exit(1)


def quellen_aus_manifest():
	"""Die im Manifest genannten Dateien, nicht die auf der Platte gefundenen.

	Ein Verzeichnis aus einem aelteren Bau bleibt liegen (lokal etwa `mart_zuglauf`) und
	wuerde eine geloeschte Quelle als vorhanden ausweisen -- der Fehler saehe dann aus wie
	ein gesunder Bau.
	"""
	daten = json.loads(MANIFEST.read_text(encoding="utf-8"))
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
	sql = ABFRAGE.sub(lambda m: '"' + m.group(1) + '"', sql)
	offen = REST.search(sql)
	if offen:
		# Nicht stillschweigend stehen lassen: ein nicht ersetzter Ausdruck wuerde als
		# Syntaxfehler durchschlagen oder -- schlimmer -- zufaellig binden.
		return sql, f"unbekannter Ausdruck {offen.group(0)}, das Skript kennt ihn nicht"
	return sql, None


quellen = list(quellen_aus_manifest())
if not quellen:
	abbrechen("keine einzige der im Manifest genannten Quelldateien ist benutzbar")

seiten = sorted(SEITEN.rglob("*.md"))
if not seiten:
	abbrechen(f"keine Seite unter {SEITEN}")

geprueft = 0
for seite in seiten:
	bloecke = BLOCK.findall(seite.read_text(encoding="utf-8"))
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
		except Exception as fehler:  # noqa: BLE001 - jede Bindungsart ist ein Befund
			befunde.append(f"{kennung}: {str(fehler).splitlines()[0]}")
	con.close()

if geprueft == 0:
	# Nicht als Erfolg durchgehen lassen: aendert Evidence die Schreibweise der Bloecke,
	# faende dieses Skript nichts mehr und meldete stillschweigend "alle 0 binden".
	abbrechen(f"keine einzige SQL-Abfrage in {len(seiten)} Seiten gefunden")

if befunde:
	abbrechen(
		f"{len(befunde)} von {geprueft} Abfragen binden nicht gegen die ausgelieferten Quellen"
	)

print(f"seitenabfragen: alle {geprueft} binden gegen die {len(quellen)} ausgelieferten Quellen")
