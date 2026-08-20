#!/bin/sh
# Baut Daten und Seite neu, ohne den Server anzufassen (BPULS-040). Laeuft als Coolify
# Scheduled Task im schon laufenden Dashboard-Container.
#
# Warum getrennt vom Entrypoint: der endet mit `exec npm run serve` und laesst sich
# deshalb nicht wiederholen. sirv liefert direkt aus dem Verzeichnis aus -- neue Dateien
# sind sofort da, der Server muss nicht neu gestartet werden.
#
# Ohne diesen Task zeigt die Seite bis in alle Ewigkeit den Stand vom Containerstart und
# altert stillschweigend. Das ist die Art Fehler, die niemand bemerkt.
set -eu

DE_GLOB="${BAHNPULS_DE_GLOB:-/data/raw/date=*/hour=*/*.parquet}"
CH_GLOB="${BAHNPULS_CH_GLOB:-tests/fixtures/ch/*_istdaten.csv}"
VARS="{\"ch_istdaten_glob\": \"$CH_GLOB\", \"de_gtfsrt_glob\": \"$DE_GLOB\"}"

cd /app/transform
if /opt/venv/bin/dbt build --full-refresh --vars "$VARS"; then
	echo "rebuild: dbt ok"
else
	# Kein Abbruch: die vorhandene Seite ist besser als keine. Der Task meldet den
	# Fehler trotzdem als Befund, damit er nicht untergeht.
	echo "rebuild: BEFUND -- dbt meldete Fehler, Seite behaelt den alten Datenstand"
	cd /app/dashboard && npm run sources >/dev/null 2>&1 || true
	npm run build >/dev/null 2>&1 || true
	exit 1
fi

cd /app/dashboard
# Erst die Quellen, dann die Seite -- `evidence build` frischt die Daten nicht auf.
npm run sources >/dev/null
npm run build >/dev/null
echo "rebuild: seite neu gebaut"
