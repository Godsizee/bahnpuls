{{ config(materialized='view') }}

-- Normalisiert die rohen GTFS-RT-Momentaufnahmen (BPULS-030). Reine Typisierung und
-- Umbenennung, keine Zustandslogik: eine Zeile hier ist weiterhin **eine Aenderung in
-- einem Snapshot**, nicht ein Halt-Ereignis. Die Verdichtung vieler Snapshots auf ein
-- Ereignis passiert in int_de_stop_events -- das ist Zustandslogik und gehoert nach
-- CLAUDE.md nicht in den Staging-Layer.
--
-- Drei Eigenschaften der Quelle, gegen den echten Feed gemessen (2026-08-20, 2.346
-- Fahrten im Scope), die hier bewusst *nicht* geglaettet werden:
--
--   1. route_id ist zu 100 % leer. route_kurzname kann aus dem Echtzeit-Feed nicht
--      kommen und bleibt NULL, bis der Static-Load steht (BPULS-023).
--   2. stop_sequence ist die rohe GTFS-Nummer, keine Position: 1.773 Fahrten beginnen
--      bei 0, 121 bei 1, 293 bei >1 -- letztere sind schon unterwegs, der Feed liefert
--      nur die Reststrecke. Sie wird **nicht neu indiziert**: ein row_number() wuerde
--      luckenhafte Laeufe lueckenlos aussehen lassen, und genau daran haengt
--      abschnitt_direkt.
--   3. Der Feed liefert je Snapshot oft nur einen Teil der Halte (395 von 2.346 mit
--      Luecke, 343 mit nur einem Halt). Der vollstaendige Laufweg entsteht erst aus der
--      Vereinigung ueber die Snapshots, nicht aus einem einzelnen.

with source as (

    -- Spalten explizit statt select *: das Schema kommt aus writer.Row im Collector,
    -- eine stille Aenderung dort soll hier auffallen.
    select
        trip_id,
        start_date,
        route_id,
        trip_schedule_relationship,
        stop_sequence,
        stop_id,
        arrival_delay,
        arrival_time,
        departure_delay,
        departure_time,
        schedule_relationship,
        is_trip_level_only,
        snapshot_timestamp,
        fetched_at

    from {{ source('de_raw', 'stop_events') }}

),

typed as (

    select
        cast(strptime(start_date, '%Y%m%d') as date) as betriebstag,
        trip_id,
        stop_sequence,
        nullif(stop_id, '')                          as stop_id,

        -- Der Feed liefert Unix-Sekunden, also einen eindeutigen Zeitpunkt. Das
        -- fct_stop_events-Schema fuehrt Soll und Ist als lokale Wanduhrzeit (so
        -- liefert es die CH-Quelle), deshalb wird hier auf Europe/Berlin umgerechnet.
        -- Nebenwirkung, bewusst in Kauf genommen: in der Ruecksprungnacht wird eine
        -- an sich eindeutige Zeit mehrdeutig und faellt unter dieselbe Entwertung wie
        -- die CH-Daten (BPULS-013). Betrifft eine Stunde im Jahr.
        case when arrival_time is not null
             then timezone('Europe/Berlin', to_timestamp(arrival_time)) end   as ist_an,
        case when departure_time is not null
             then timezone('Europe/Berlin', to_timestamp(departure_time)) end as ist_ab,

        arrival_delay   as delay_an_sek,
        departure_delay as delay_ab_sek,

        -- Soll = Prognose minus Verspaetung. Der Feed liefert keine Soll-Zeit; sie ist
        -- nur dort rekonstruierbar, wo beide Werte da sind.
        case when arrival_time is not null and arrival_delay is not null
             then timezone('Europe/Berlin', to_timestamp(arrival_time - arrival_delay)) end   as soll_an,
        case when departure_time is not null and departure_delay is not null
             then timezone('Europe/Berlin', to_timestamp(departure_time - departure_delay)) end as soll_ab,

        schedule_relationship = 'SKIPPED'       as halt_ausgelassen,
        trip_schedule_relationship = 'CANCELED' as zug_ausgefallen,
        is_trip_level_only,

        timezone('Europe/Berlin', to_timestamp(snapshot_timestamp)) as snapshot_ts,
        timezone('Europe/Berlin', to_timestamp(fetched_at))         as fetched_at

    from source

)

select
    betriebstag,
    betriebstag::varchar || '_' || trip_id as trip_key,
    trip_id,
    stop_sequence,
    stop_id,
    soll_an,
    soll_ab,
    ist_an,
    ist_ab,
    delay_an_sek,
    delay_ab_sek,
    halt_ausgelassen,
    zug_ausgefallen,
    snapshot_ts,
    fetched_at,
    'de_gtfsrt' as quelle

from typed
-- Eintraege ohne Halt sind Aussagen ueber die *Fahrt*, nicht ueber einen Halt (der
-- Collector behaelt sie bewusst, weil ein vollstaendig ausgefallener Zug im Feed ohne
-- stop_time_update erscheinen kann). Sie koennen kein Halt-Ereignis werden -- ein
-- Ausfall ohne Halt braucht einen eigenen Weg, siehe BPULS-032. Hier faellt er heraus,
-- und das ist eine benannte Luecke, keine stille.
where not is_trip_level_only
  and stop_sequence is not null
