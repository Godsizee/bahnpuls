{{ config(materialized='view') }}

-- Soll-Halte aus dem statischen Fahrplan (BPULS-032). Reine Typisierung und
-- Umbenennung; welche Version fuer welchen Betriebstag gilt, entscheidet
-- int_de_ausfaelle, nicht diese View.
--
-- **Warum es diese View gibt:** ein vollstaendig ausgefallener Zug erscheint im
-- Echtzeit-Feed ohne stop_time_update -- es gibt keinen Halt, an dem der Ausfall
-- haengen koennte. Gemessen am Produktionsstand vom 2026-08-21 erreichte dadurch
-- **kein einziger** Ausfall die Kennzahlen (0 bei 52.263 Fahrten), waehrend 21.823
-- ausgelassene Halte ankamen. Erst der Soll-Laufweg macht daraus wieder Halte.

{% set dateien = fahrplanhalt_dateien() %}

{% if dateien == 0 %}

{#-
    Kein einziger Soll-Fahrplan auf dem Volume. Das ist ein moeglicher Zustand und
    kein Programmierfehler: die Extraktion aus dem Archiv ist bewusst best-effort
    (ErrFahrplanUnvollstaendig), damit ein Fehlschlag dort nie das unwiederbringliche
    Archiv kostet -- und vor der ersten Ladung mit dem neuen Loader gibt es die Datei
    ueberhaupt nicht.

    Der Glob wuerde hier abbrechen und **den ganzen dbt-Lauf** mitnehmen, also auch
    Puenktlichkeit, Engpaesse und Pufferbilanz, die mit Ausfaellen nichts zu tun
    haben. Stattdessen bleibt die View leer -- aber nicht still: die Warnung unten
    steht im Lauf, und `assert_de_ausfaelle_aufgeloest` meldet dann **jeden**
    ausgefallenen Zug als unaufgeloest. Eine leere View, die niemand bemerkt, waere
    genau der Blindfleck, den BPULS-032 gerade geschlossen hat.
-#}
{% do exceptions.warn(
    "stg_de_fahrplanhalt: keine stop_times.parquet unter " ~ var('de_static_dir') ~
    "/v=*/ gefunden. Ausfaelle bleiben unaufgeloest (A5 zeigt zu wenige). "
    ~ "Behebung: 'statictool -fahrplan-nachtragen -static-dir " ~ var('de_static_dir') ~ "'"
) %}

select
    cast(null as date)    as static_version,
    cast(null as varchar) as feed,
    cast(null as varchar) as trip_id,
    cast(null as bigint)  as stop_sequence,
    cast(null as varchar) as stop_id,
    cast(null as bigint)  as soll_an_sek,
    cast(null as bigint)  as soll_ab_sek
where false

{% else %}

with roh as (

    select
        trip_id,
        stop_sequence,
        stop_id,
        arrival_time,
        departure_time,
        regexp_extract(filename, 'v=([0-9-]+)', 1) as static_version,
        -- Der Feed-Name steckt im Verzeichnis unter der Version. route_id und
        -- stop_id sind je Feed eigene Namensraeume (BPULS-023), deshalb muss er
        -- mitgefuehrt werden.
        str_split(replace(filename, chr(92), '/'), '/')[-2] as feed

    from {{ source('de_static', 'stop_times') }}
    where trip_id is not null
      and stop_sequence is not null

)

select
    cast(static_version as date) as static_version,
    feed,
    trip_id,
    cast(stop_sequence as bigint) as stop_sequence,
    nullif(stop_id, '')           as stop_id,

    -- GTFS-Zeiten sind **Sekunden seit Betriebstagsbeginn**, keine Uhrzeiten:
    -- "25:30:00" ist der naechste Kalendertag, 01:30 Uhr, und gehoert trotzdem zu
    -- diesem Betriebstag. Als Uhrzeit geparst (`CAST ... AS TIME`) faellt genau die
    -- Nachtfahrt heraus, in der die interessanten Stoerungen stecken -- das ist
    -- CLAUDE.md Regel 6 und hier der eigentliche Grund fuer die Zerlegung von Hand.
    {{ gtfs_zeit_in_sekunden('arrival_time') }}   as soll_an_sek,
    {{ gtfs_zeit_in_sekunden('departure_time') }} as soll_ab_sek

from roh

{% endif %}
