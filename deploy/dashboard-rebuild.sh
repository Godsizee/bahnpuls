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
#
# Das Fehlen der Pruefung ist ein **eigener** Befund und darf nicht als ihr Ergebnis
# gelesen werden: vom 2026-08-21 bis zum 2026-08-22 lag die Datei nicht im Image (im
# Dockerfile beim COPY vergessen), node brach mit MODULE_NOT_FOUND ab, und der Task
# meldete stuendlich das Gegenteil der Wahrheit -- die Quellen wurden die ganze Zeit
# ausgeliefert. Ein Waechter, der aus dem falschen Grund rot ist, macht den naechsten
# echten Befund unsichtbar (BPULS-065).
# Beide Pruefungen laufen, auch wenn die erste schon anschlaegt: sie beantworten
# verschiedene Fragen ("wird ausgeliefert?" gegen "passt zusammen?"), und ein Abbruch nach
# der ersten wuerde den zweiten Befund bis zum naechsten Lauf verstecken.
befunde=0

PRUEFER=/app/deploy/dashboard-quellen-pruefen.js
if [ ! -f "$PRUEFER" ]; then
	echo "rebuild: BEFUND -- $PRUEFER fehlt im Image, die Quellen sind ungeprueft"
	befunde=$((befunde + 1))
elif ! node "$PRUEFER"; then
	echo "rebuild: BEFUND -- die Seite liefert ihre Datenquellen nicht aus"
	befunde=$((befunde + 1))
fi

# Zweite Frage: liefert die Seite ueberhaupt Zahlen aus dem, was da ist? Eine Spalte, die
# im Mart und in der Seite steht, aber nicht in der Quellabfrage, laesst `build:strict`
# unberuehrt und faellt erst im Browser des Lesers als fehlende Bindung auf -- von aussen
# wieder als HTTP 200 mit richtiger Groesse (BPULS-067).
SEITENPRUEFER=/app/deploy/dashboard-seitenabfragen-pruefen.py
if [ ! -f "$SEITENPRUEFER" ]; then
	echo "rebuild: BEFUND -- $SEITENPRUEFER fehlt im Image, die Seitenabfragen sind ungeprueft"
	befunde=$((befunde + 1))
elif ! /opt/venv/bin/python "$SEITENPRUEFER"; then
	echo "rebuild: BEFUND -- eine Seitenabfrage passt nicht zu den ausgelieferten Quellen"
	befunde=$((befunde + 1))
fi

[ "$befunde" -eq 0 ] || exit 1
