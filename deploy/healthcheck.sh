#!/bin/sh
# Docker-HEALTHCHECK auf den Heartbeat (BPULS-022).
#
# Prueft bewusst nur Lebendigkeit, nicht Sinnhaftigkeit: der Heartbeat wird bei
# JEDEM Poll geschrieben, auch wenn der Feed-Abruf fehlschlaegt. Ein veralteter
# Heartbeat heisst deshalb "der Prozess haengt", nicht "der Feed ist weg".
#
# Das ist keine Sparsamkeit, sondern Absicht: ein Feed-Ausfall darf hier nicht
# anschlagen. Ein Neustart wuerde ihn nicht beheben, aber den offenen
# Stundenpuffer kosten (CLAUDE.md Regel 3 und 4) -- und ein Healthcheck, der
# waehrend eines Deployments nie gruen wird, schickt Coolify in genau die
# Restart-Schleife, die deploy/README.md Schritt 1 vermeiden will.
# Das fachliche Urteil faellt pruefung.sh (BPULS-026), nicht dieser Check.
set -eu

HB="${BAHNPULS_HEARTBEAT_PATH:-data/heartbeat.json}"
# 300 s statt knapper: zwischen zwei Heartbeats liegen im schlimmsten Fall
# Poll-Intervall (30 s) plus ein blockierender Fetch (3 Versuche a 25 s plus
# Backoff, ~81 s). 300 s laesst Luft und erkennt einen haengenden Prozess
# trotzdem innerhalb von fuenf Minuten.
MAX_AGE="${BAHNPULS_HEARTBEAT_MAX_AGE:-300}"

if [ ! -f "$HB" ]; then
	echo "heartbeat fehlt: $HB"
	exit 1
fi

alter=$(( $(date +%s) - $(stat -c %Y "$HB") ))
if [ "$alter" -gt "$MAX_AGE" ]; then
	echo "heartbeat ${alter}s alt, Grenze ${MAX_AGE}s -- Collector haengt"
	exit 1
fi

echo "heartbeat ${alter}s alt"
