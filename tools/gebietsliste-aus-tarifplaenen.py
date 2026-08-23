"""Gebietsliste VRN + RMV aus den Tarifplaenen ableiten (BPULS-074).

Die beiden Tarifplaene unter `docs/tarifplaene/` sind die fachliche Autoritaet fuer
die Verbundgrenzen. Ihr eingebetteter Text enthaelt alle Orts- und Wabennamen --
aber auch Richtungsangaben am Kartenrand ("nach Kassel") und die
Uebergangstarif-Tabellen der Nachbarverbuende. Der reine Textabgleich traegt
deshalb nur bis etwa 90 %; den Rest entscheiden zwei ausgeschriebene Listen.

**Das Kriterium ist der Heimatverbund, nicht der Uebergangstarif** (Entscheidung
des Nutzers, 2026-08-23). Kahl hat einen RMV-Uebergangstarif, gehoert aber zur VAB
-- also nicht ins Gebiet. Dasselbe gilt fuer den Landkreis Hersfeld-Rotenburg, der
zum NVV gehoert, auch wenn es Richtung Suedhessen tarifliche Schnittmengen gibt.

Die beiden PDFs liegen **nicht im Repo** -- sie sind urheberrechtlich geschuetzte
Werke der Verbuende. Vor dem Lauf ablegen unter `docs/tarifplaene/`:

    RMV-Tarifgesamtplan.pdf   Bezug: rmv.de (Tarifgesamtplan, Uebersichtskarte)
    VRN-wabenplan.pdf         Bezug: vrn.de (Wabenplan)

Aufruf aus dem Repo-Wurzelverzeichnis:

    .venv/Scripts/python tools/gebietsliste-aus-tarifplaenen.py [--schreiben]

Ohne `--schreiben` wird nur berichtet, nichts veraendert.
"""
import re
import sys
import unicodedata
from collections import Counter
from pathlib import Path

import duckdb
import pymupdf

WURZEL = Path(__file__).resolve().parent.parent
PLAENE = WURZEL / "docs" / "tarifplaene"
SCOPE = WURZEL / "config" / "scope_stops.csv"

# Nachbarverbuende, deren Namen als Richtungsangabe oder Uebergangstarif-Tabelle
# auf den Karten stehen und deshalb faelschlich treffen. Ohne diese Liste gelten
# Karlsruhe Hbf, Wuerzburg Hbf, Koblenz Hbf, Siegen Hbf und Kassel-Wilhelmshoehe
# als Gebietshalte -- gemessen 2026-08-23.
FREMDE_ZENTREN = ["karlsruhe", "wurzburg", "koblenz", "siegen", "kassel"]

# Zwei Nachbarverbuende lassen sich **nicht ueber den Namen allein** ausschliessen:
# dieselben Ortsnamen gibt es auch im Gebiet. Gemessen 2026-08-23:
# Sulzbach (Taunus, RMV) gegen Sulzbach (Main, VAB), Laudenbach (Bergstrasse, VRN)
# gegen Laudenbach am Main (VAB), Woerth am Rhein (VRN) gegen Woerth (Main, VAB).
# Ein reiner Namensfilter wirft die Gebietshalte gleich mit weg. Deshalb gilt jede
# dieser Listen nur innerhalb ihrer Region.
#
# Und eine reine Laengengrad-Regel reicht auch nicht: Neustadt (Kr Marburg) liegt
# bei lon 9,12 und damit oestlicher als der halbe Untermain -- aber 80 km noerdlich
# davon, mitten im RMV.
REGIONEN = {
    # VAB (Verkehrsgemeinschaft am Bayerischen Untermain): bayerische Gemeinden
    # mit RMV-Uebergangstarif. Nach dem Heimatverbund-Kriterium nicht im Gebiet.
    # **Achtung:** hierunter faellt auch Aschaffenburg, der Knoten, an dem
    # RMV-Zuege aus Frankfurt enden.
    "VAB / bayerischer Untermain": {
        "box": (49.45, 50.15, 9.00, 9.60),
        "orte": [
            "aschaffenburg", "kahl", "miltenberg", "obernburg", "klingenberg",
            "amorbach", "elsenfeld", "grossheubach", "erlenbach", "laudenbach",
            "collenberg", "faulbach", "kleinheubach", "sulzbach", "niedernberg",
            "alzenau", "mombris", "schollkrippen", "hosbach", "goldbach",
            "haibach", "grosswallstadt", "kleinwallstadt", "worth",
            "dorfprozelten", "stadtprozelten", "burgstadt", "eichenbuhl",
            "rudenau", "schneeberg", "weilbach", "monchberg", "rollbach",
            "trennfurt", "hausen", "wiesthal", "heigenbrucken", "laufach",
        ],
    },
    # NVV (Nordhessen): der Landkreis Hersfeld-Rotenburg gehoert dorthin, nicht
    # zum RMV. Auf der RMV-Karte erscheint er wegen des Uebergangstarifs.
    "NVV / Hersfeld-Rotenburg": {
        "box": (50.70, 51.15, 9.50, 10.10),
        "orte": [
            "hersfeld", "bebra", "rotenburg", "ronshausen", "wildeck",
            "ludwigsau", "heinebach", "lispenhausen", "cornberg",
            "nentershausen", "sontra", "bosserode", "honebach", "friedlos",
        ],
    },
}

# Orte, die der Textabgleich verliert, obwohl sie zum Gebiet gehoeren
# (bestaetigt vom Nutzer, 2026-08-23).
NACHTRAG = ["bammental", "asselheim", "grunstadt"]


def normalisiere(s):
    s = unicodedata.normalize("NFKD", s.lower()).replace("ß", "ss")
    s = "".join(c for c in s if not unicodedata.combining(c))
    return re.sub(r"[^a-z]", "", s)


def orte_aus_pdf(pfad):
    """Ortsnamen einer Tarifkarte. Loest die Silbentrennung des Kartensatzes auf
    und zieht gesperrt gesetzte Beschriftungen ("F r a n k f u r t") zusammen."""
    text = pymupdf.open(pfad)[0].get_text()
    zusammen, puffer = [], ""
    for z in (zeile.strip() for zeile in text.split("\n")):
        if not z:
            if puffer:
                zusammen.append(puffer)
                puffer = ""
            continue
        if puffer:
            z, puffer = puffer + z, ""
        if z.endswith("-") and len(z) > 2:
            puffer = z[:-1]
            continue
        zusammen.append(z)
    if puffer:
        zusammen.append(puffer)

    orte = set()
    for z in zusammen:
        if re.fullmatch(r"(?:\S ){2,}\S", z):
            z = z.replace(" ", "")
        z = z.strip(" .,()/")
        if not (2 < len(z) < 40):
            continue
        if not re.fullmatch(r"[A-Za-zÄÖÜäöüß][A-Za-zÄÖÜäöüß .,\-/()']*", z):
            continue
        orte.add(z)
        # 'Enkenbach-Alsenborn' steht im Bahnhofsnamen oft nur als 'Enkenbach'.
        for teil in re.split(r"[\-/,()\s]+", z):
            if len(teil) >= 5:
                orte.add(teil)
    return orte


def gebietsschluessel():
    rmv = orte_aus_pdf(PLAENE / "RMV-Tarifgesamtplan.pdf")
    vrn = orte_aus_pdf(PLAENE / "VRN-wabenplan.pdf")
    # Mindestlaenge 5: kuerzere Namen treffen als Teilzeichenkette zu viel
    # ('Ehr' in 'Fehrbach') und bringen mehr Fehler als Nutzen.
    schluessel = {normalisiere(o) for o in (rmv | vrn)}
    schluessel = {s for s in schluessel if len(s) >= 5}
    schluessel |= set(NACHTRAG)
    return rmv, vrn, sorted(schluessel, key=len, reverse=True)


def im_gebiet(name, lat, lon, schluessel):
    """Trifft der Name einen Gebietsschluessel -- und liegt er nicht in einer der
    ausgeschlossenen Nachbarregionen? Gibt den treffenden Schluessel zurueck oder
    None."""
    n = normalisiere(name)
    for fremd in FREMDE_ZENTREN:
        if fremd in n:
            return None
    for regel in REGIONEN.values():
        lat_min, lat_max, lon_min, lon_max = regel["box"]
        if lat is None or lon is None:
            continue
        if not (lat_min <= lat <= lat_max and lon_min <= lon <= lon_max):
            continue
        if any(ort in n for ort in regel["orte"]):
            return None
    return next((s for s in schluessel if s in n), None)


def main():
    schreiben = "--schreiben" in sys.argv
    rmv, vrn, schluessel = gebietsschluessel()
    print(f"RMV-Plan {len(rmv)} Namen, VRN-Plan {len(vrn)} Namen "
          f"-> {len(schluessel)} Gebietsschluessel")

    c = duckdb.connect()
    c.execute(f"create view s as select * from "
              f"read_csv('{SCOPE.as_posix()}', header=true, all_varchar=true)")
    halte = c.execute("select stop_id, stop_name, stop_lat, stop_lon from s").fetchall()

    drin, raus = [], []
    for sid, name, lat, lon in halte:
        try:
            koord = (float(lat), float(lon))
        except (TypeError, ValueError):
            koord = (None, None)
        ziel = drin if im_gebiet(name, koord[0], koord[1], schluessel) else raus
        ziel.append((sid, name, lat, lon))

    print(f"\nHalte in der bisherigen Liste: {len(halte)}")
    print(f"  im Gebiet VRN + RMV: {len(drin):5}  ({100*len(drin)/len(halte):.1f} %)")
    print(f"  ausserhalb:          {len(raus):5}  ({100*len(raus)/len(halte):.1f} %)")

    z = Counter(re.split(r"[,\-/(]", name)[0].strip() for _, name, _, _ in raus)
    print(f"\nEntfallende Orte: {len(z)} verschiedene, die haeufigsten 25:")
    for ort, n in z.most_common(25):
        print(f"  {n:4}x  {ort}")

    if not schreiben:
        print("\n(Probelauf -- nichts geschrieben. Mit --schreiben ausfuehren.)")
        return 0

    zeilen = sorted(drin, key=lambda r: (r[1], r[0]))
    with SCOPE.open("w", encoding="utf-8", newline="") as f:
        f.write("stop_id,stop_name,stop_lat,stop_lon\n")
        for sid, name, lat, lon in zeilen:
            f.write(f"{sid},{name},{lat},{lon}\n")
    print(f"\ngeschrieben: {len(zeilen)} Halte nach {SCOPE}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
