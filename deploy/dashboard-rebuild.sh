#!/bin/sh
# Baut Daten und Seite neu, ohne den Server anzufassen (BPULS-040). Laeuft als Coolify
# Scheduled Task im schon laufenden Dashboard-Container.
#
# Warum getrennt vom Entrypoint: der endet mit `exec npm run serve` und laesst sich
# deshalb nicht wiederholen. sirv liefert direkt aus dem Verzeichnis aus -- neue Dateien
# sind sofort da, der Server muss nicht neu gestartet werden.
#
# **Das gilt nur, weil `npm run serve` mit `--dev` laeuft.** Ohne diesen Schalter liest
# sirv das Verzeichnis genau einmal beim Start und liefert danach ausschliesslich, was
# damals darin stand -- dieses Skript schriebe dann stundenlang Dateien, die niemand
# abrufen kann, und die Seite stuende mit HTTP 200 und ohne eine einzige Zahl da.
# Begruendung und Messung in dashboard/README.md.
#
# Ohne diesen Task zeigt die Seite bis in alle Ewigkeit den Stand vom Containerstart und
# altert stillschweigend. Das ist die Art Fehler, die niemand bemerkt.
set -eu

DE_GLOB="${BAHNPULS_DE_GLOB:-/data/raw/date=*/hour=*/*.parquet}"
CH_GLOB="${BAHNPULS_CH_GLOB:-tests/fixtures/ch/*_istdaten.csv}"
# Alle Versionen, nicht die neueste: die stop_ids rotieren (Q6, BPULS-023).
STATIC_DIR="${BAHNPULS_STATIC_DIR:-/data/static}"
VARS="{\"ch_istdaten_glob\": \"$CH_GLOB\", \"de_gtfsrt_glob\": \"$DE_GLOB\", \"de_static_dir\": \"$STATIC_DIR\"}"

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

# Gegenprobe am laufenden Server, nicht am Dateisystem: eine Seite ohne Quellen ist von
# aussen nicht von einer gesunden zu unterscheiden (200, richtiger Titel), und der
# Healthcheck fragt nur die Startseite ab. Bewusst **hier** und nicht im Healthcheck --
# eine Seite mit altem Datenstand ist besser als ein neu gestarteter Container, aber der
# Task soll rot werden.
if ! node /app/deploy/dashboard-quellen-pruefen.js; then
	echo "rebuild: BEFUND -- die Seite liefert ihre Datenquellen nicht aus"
	exit 1
fi
