#!/bin/sh
# Baut die Evidence-Seite aus den Rohdaten auf dem Volume und liefert sie aus
# (BPULS-040, ADR-012). Laeuft beim Containerstart und danach erneut ueber einen
# Coolify Scheduled Task -- das Ergebnis ist eine statische Seite, der Server bedient
# sie einfach weiter.
#
# Die Rohdaten werden ausschliesslich **gelesen**. Das Volume ist read-only gemountet,
# damit ein Fehler hier niemals Historie kosten kann (CLAUDE.md Regel 1).
set -eu

DE_GLOB="${BAHNPULS_DE_GLOB:-/data/raw/**/*.parquet}"
CH_GLOB="${BAHNPULS_CH_GLOB:-tests/fixtures/ch/*_istdaten.csv}"
VARS="{\"ch_istdaten_glob\": \"$CH_GLOB\", \"de_gtfsrt_glob\": \"$DE_GLOB\"}"

echo "dashboard: dbt build (de=$DE_GLOB ch=$CH_GLOB)"
cd /app/transform

# --full-refresh, weil die beiden Quellen unterschiedlich alte Betriebstage liefern und
# die inkrementelle Logik nur vorwaerts laedt (Fallstrick in transform/README.md).
#
# Ein fehlgeschlagener dbt-Lauf bricht hier bewusst nicht ab: die Seite soll dann den
# letzten guten Stand weiter ausliefern, statt zu verschwinden. Ob die Daten frisch sind,
# steht auf der Seite selbst, nicht im Exit-Code dieses Skripts.
if ! /opt/venv/bin/dbt build --full-refresh --vars "$VARS"; then
	echo "dashboard: dbt meldete Fehler -- Seite wird mit dem vorhandenen Stand gebaut"
fi

echo "dashboard: evidence build"
cd /app/dashboard
npm run build

echo "dashboard: serving on :3000"
exec npm run serve
