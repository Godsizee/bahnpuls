#!/bin/sh
# Fachliche Pruefung als Coolify Scheduled Task (BPULS-026).
#
# Ein Container kann laufen und trotzdem nichts Sinnvolles schreiben -- genau
# das faengt der Healthcheck absichtlich nicht ab. Dieses Skript beurteilt den
# Inhalt: kommt der Feed frisch an, greift die Haltestellenliste noch, landen
# ueberhaupt Dateien auf dem Volume, ist noch Platz da.
#
# Exit 1 = Befund (Coolify meldet den fehlgeschlagenen Task), Exit 0 = in
# Ordnung; Warnungen werden ausgegeben, ohne den Task rot zu faerben.
set -u

HB="${BAHNPULS_HEARTBEAT_PATH:-data/heartbeat.json}"
DATA_DIR="${BAHNPULS_DATA_DIR:-data/raw}"

MAX_HEARTBEAT_AGE=600
MAX_FEED_AGE=300
# Der Feed traegt gelegentlich einen Zeitstempel wenige Sekunden in der
# Zukunft (im 24 h-Lauf bis -13 s). Das ist normal, kein Befund.
MIN_FEED_AGE=-120
# Anteil der Fahrten im Scope, in Promille. Im 24 h-Lauf lag er zwischen 21,5
# und 53,3 Promille -- und zwar tags wie nachts, weil nachts der ganze Feed
# schrumpft, nicht nur der Scope. Ein absoluter Schwellwert wuerde deshalb
# jede Nacht falsch anschlagen. 10 Promille laesst Faktor zwei Luft nach
# unten und faengt trotzdem den Fall ab, um den es geht: rotierende stop_ids,
# die den Scope gegen null laufen lassen (Q6 im Vault).
MIN_SCOPE_PROMILLE=10
# Geflusht wird stuendlich; zwei Stunden ohne neue Datei heisst, dass eine
# Stunde Historie fehlt.
MAX_DATEI_ALTER=7200
MIN_FREI_MB=2048
WARN_FREI_MB=10240

befund=0
melde() { echo "BEFUND: $1"; befund=1; }
warne() { echo "warnung: $1"; }

json_zahl() {
	sed -n "s/.*\"$1\": *\(-\{0,1\}[0-9]\{1,\}\).*/\1/p" "$HB" | head -1
}

# --- Heartbeat vorhanden und frisch ---------------------------------------
if [ ! -f "$HB" ]; then
	melde "heartbeat fehlt: $HB"
	exit 1
fi

hb_alter=$(( $(date +%s) - $(stat -c %Y "$HB") ))
[ "$hb_alter" -gt "$MAX_HEARTBEAT_AGE" ] &&
	melde "heartbeat ${hb_alter}s alt (Grenze ${MAX_HEARTBEAT_AGE}s)"

fehler=$(sed -n 's/.*"error": *"\(.*\)".*/\1/p' "$HB" | head -1)
[ -n "$fehler" ] && warne "letzter Poll mit Fehler: $fehler"

# --- Feed-Alter ------------------------------------------------------------
feed_alter=$(json_zahl feed_age_seconds)
if [ -z "$feed_alter" ]; then
	melde "feed_age_seconds nicht lesbar aus $HB"
elif [ "$feed_alter" -gt "$MAX_FEED_AGE" ] || [ "$feed_alter" -lt "$MIN_FEED_AGE" ]; then
	melde "Feed-Alter ${feed_alter}s ausserhalb ${MIN_FEED_AGE}..${MAX_FEED_AGE}s"
fi

# --- Greift die Haltestellenliste noch? ------------------------------------
gesamt=$(json_zahl entity_count)
im_scope=$(json_zahl in_scope_count)
if [ -z "$gesamt" ] || [ -z "$im_scope" ]; then
	melde "entity_count/in_scope_count nicht lesbar aus $HB"
elif [ "$gesamt" -le 0 ]; then
	melde "Feed lieferte 0 Fahrten"
else
	promille=$(( im_scope * 1000 / gesamt ))
	if [ "$promille" -lt "$MIN_SCOPE_PROMILLE" ]; then
		melde "nur ${promille} Promille im Scope (${im_scope}/${gesamt}, Grenze ${MIN_SCOPE_PROMILLE}) -- Haltestellenliste greift nicht mehr"
	else
		echo "scope: ${im_scope}/${gesamt} Fahrten (${promille} Promille)"
	fi
fi

# --- Landet ueberhaupt etwas auf dem Volume? -------------------------------
# Sortiert nach Pfad: date=/hour= sind nullgepolstert, der Dateiname ist die
# Nanosekundenzeit des Flushes -- die letzte Zeile ist damit die neueste Datei.
neueste=$(find "$DATA_DIR" -type f -name '*.parquet' 2>/dev/null | sort | tail -1)
if [ -z "$neueste" ]; then
	melde "keine einzige Parquet-Datei unter $DATA_DIR"
else
	datei_alter=$(( $(date +%s) - $(stat -c %Y "$neueste") ))
	if [ "$datei_alter" -gt "$MAX_DATEI_ALTER" ]; then
		melde "neueste Datei ist ${datei_alter}s alt (Grenze ${MAX_DATEI_ALTER}s): $neueste"
	else
		echo "neueste Datei ${datei_alter}s alt: $neueste"
	fi
fi

# --- Plattenplatz ----------------------------------------------------------
# Coolifys eigene 80-%-Warnung ist kein Sicherheitsnetz: auf strato stand sie
# auf 80 %, waehrend die Platte bei 99 % lag, ohne dass etwas passiert waere.
# -P ist POSIX, BusyBox kennt es -- aber falls nicht, lieber auf das nackte
# df zurueckfallen als die Pruefung an der Formatierung scheitern zu lassen.
frei_mb=$(df -Pk "$DATA_DIR" 2>/dev/null | awk 'NR==2 {print int($4/1024)}')
[ -z "$frei_mb" ] && frei_mb=$(df -k "$DATA_DIR" 2>/dev/null | awk 'NR==2 {print int($4/1024)}')
if [ -z "$frei_mb" ]; then
	warne "Plattenplatz nicht ermittelbar fuer $DATA_DIR"
elif [ "$frei_mb" -lt "$MIN_FREI_MB" ]; then
	melde "nur noch ${frei_mb} MB frei (Grenze ${MIN_FREI_MB} MB) -- ein fehlgeschlagener Flush ist nicht nachlieferbar"
elif [ "$frei_mb" -lt "$WARN_FREI_MB" ]; then
	warne "noch ${frei_mb} MB frei"
else
	echo "platte: ${frei_mb} MB frei"
fi

[ "$befund" -eq 0 ] && echo "pruefung ok"
exit "$befund"
