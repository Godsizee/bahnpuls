"""Kennzahlen der Rohdaten, ohne Shell-Quoting (BPULS-030).

Die Coolify-Scheduled-Tasks reichen Kommandos durch zwei Shell-Ebenen; Anfuehrungs-
zeichen und Backslashes ueberleben das nicht zuverlaessig, und das Kommandofeld hat
ein Laengenlimit. Deshalb liegt die Abfrage als Datei im Image und wird kurz
aufgerufen: `/opt/venv/bin/python /app/deploy/diagnose.py`.
"""

import os

import duckdb

GLOB = os.environ.get("BAHNPULS_DE_GLOB", "/data/raw/date=*/hour=*/*.parquet")

ABFRAGEN = {
    "Umfang": "select count(*) zeilen, count(distinct trip_id) fahrten, "
              "min(start_date) von, max(start_date) bis from read_parquet(?)",
    "Verspaetung (Sekunden)": "select min(arrival_delay) an_min, max(arrival_delay) an_max, "
                              "min(departure_delay) ab_min, max(departure_delay) ab_max "
                              "from read_parquet(?)",
    "Soll gegen Betriebstag (Stunden)": (
        "select min(h) min_h, max(h) max_h, "
        "count(*) filter (where h < 0 or h >= 30) ausserhalb, count(h) gesamt from ("
        "select (arrival_time - arrival_delay - epoch(strptime(start_date, '%Y%m%d'))) / 3600.0 h "
        "from read_parquet(?))"
    ),
}

con = duckdb.connect()
for titel, sql in ABFRAGEN.items():
    print(f"--- {titel}")
    try:
        r = con.execute(sql, [GLOB])
        namen = [d[0] for d in r.description]
        for name, wert in zip(namen, r.fetchone()):
            print(f"  {name:16} = {wert}")
    except Exception as fehler:  # noqa: BLE001 - Diagnose soll nie abbrechen
        print(f"  Fehler: {fehler}")
