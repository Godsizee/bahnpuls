{{ config(materialized='table') }}

-- Verdichtet die GTFS-RT-Momentaufnahmen auf **ein Halt-Ereignis je Halt** und bringt
-- sie damit auf das fct_stop_events-Schema (BPULS-030).
--
-- Warum ein eigenes Modell und nicht direkt in stg_de_gtfsrt: das hier ist
-- Zustandslogik -- aus vielen Prognosen wird ein Ist -- und die gehoert nach CLAUDE.md
-- nicht in den Staging-Layer. Die CH-Quelle braucht diesen Schritt nicht, weil ihre
-- Zeile bereits ein Halt-Ereignis ist; deshalb haengt fct_stop_events fuer CH am
-- Staging-Modell und fuer DE hier.
--
-- Die Regel (Bahnpuls_Datenmodell.md): als Ist gilt der **zeitlich letzte** Wert, der
-- bis kurz nach dem Soll-Zeitpunkt gemeldet wurde. Die Karenz faengt ab, dass die
-- letzte Meldung leicht nach dem Ereignis eintrifft. Sie ist eine **Annahme**, steht
-- deshalb als Variable hier und auf der Methodik-Seite -- sie beeinflusst jede
-- nachgelagerte Kennzahl.

{% set karenz = var('de_ist_karenz_minuten', 5) %}

with snapshots as (

    select * from {{ ref('stg_de_gtfsrt') }}

),

-- Jeder Halt, der ueberhaupt je gemeldet wurde. Basis, damit auch Halte bestehen
-- bleiben, fuer die kein Wert die Regel erfuellt -- die Zeile bleibt stehen und traegt
-- NULL, statt aus dem Laufweg zu verschwinden (CLAUDE.md Regel 8, Fallstrick A1).
halte as (

    select distinct betriebstag, trip_key, stop_sequence, stop_id, quelle
    from snapshots

),

-- Letzter Zustand je Halt, unabhaengig von der Karenz: ob ausgelassen oder ausgefallen
-- ist eine Aussage ueber den Halt, keine Prognose auf einen Zeitpunkt.
zustand as (

    select
        trip_key,
        stop_sequence,
        halt_ausgelassen,
        zug_ausgefallen,
        snapshot_ts as letzter_snapshot_ts

    from snapshots
    qualify row_number() over (
        partition by trip_key, stop_sequence order by snapshot_ts desc
    ) = 1

),

-- Soll getrennt von Ist: die Soll-Zeit ist eine Fahrplantatsache, keine Prognose auf
-- einen Zeitpunkt, und darf deshalb nicht an der Karenz haengen. Zoege man sie aus
-- demselben gefilterten Kandidaten, verloere ein Halt, dessen einziger Snapshot zu spaet
-- kam, auch seine Soll-Zeit -- er fiele aus dem Nenner von mart_datenqualitaet heraus,
-- und die verpasste Messung machte sich damit selbst unsichtbar.
soll as (

    select
        trip_key,
        stop_sequence,
        max(soll_an) as soll_an,
        max(soll_ab) as soll_ab

    from snapshots
    group by trip_key, stop_sequence

),

ankunft as (

    select
        trip_key,
        stop_sequence,
        ist_an,
        delay_an_sek,
        snapshot_ts as an_snapshot_ts

    from snapshots
    -- Ohne Soll-Zeit ist die Regel nicht anwendbar: der Feed liefert keine, sie wird
    -- aus Prognose minus Verspaetung rekonstruiert, und fehlt eines von beiden, gibt
    -- es keinen Bezugspunkt. Dann bleibt der Wert nicht bestimmbar statt geraten.
    where soll_an is not null
      and snapshot_ts <= soll_an + interval {{ karenz }} minute
    qualify row_number() over (
        partition by trip_key, stop_sequence order by snapshot_ts desc
    ) = 1

),

abfahrt as (

    select
        trip_key,
        stop_sequence,
        ist_ab,
        delay_ab_sek,
        snapshot_ts as ab_snapshot_ts

    from snapshots
    where soll_ab is not null
      and snapshot_ts <= soll_ab + interval {{ karenz }} minute
    qualify row_number() over (
        partition by trip_key, stop_sequence order by snapshot_ts desc
    ) = 1

)

select
    halte.betriebstag,
    halte.trip_key,
    halte.stop_sequence::bigint as stop_sequence,
    halte.stop_id,

    -- Kein Stationsname im Echtzeit-Feed. Der Rohwert waere eine ID, kein Name -- ihn
    -- als Namen auszugeben, waere eine Luege im Dashboard. Kommt mit BPULS-023.
    cast(null as varchar) as stop_name,

    soll.soll_an,
    soll.soll_ab,
    ankunft.ist_an,
    abfahrt.ist_ab,
    ankunft.delay_an_sek::bigint as delay_an_sek,
    abfahrt.delay_ab_sek::bigint as delay_ab_sek,

    -- Endgueltig ist ein Wert, wenn ueber den Stichtag hinaus beobachtet wurde: dann
    -- kann keine spaetere Meldung mehr kommen. Endet die Beobachtung vorher -- laufender
    -- Betriebstag, oder der Collector stand still --, ist der Wert noch in Bewegung.
    coalesce(
        zustand.letzter_snapshot_ts >= coalesce(soll.soll_ab, soll.soll_an)
            + interval {{ karenz }} minute,
        false
    ) as ist_endgueltig,

    coalesce(zustand.halt_ausgelassen, false) as halt_ausgelassen,
    coalesce(zustand.zug_ausgefallen, false)  as zug_ausgefallen,

    -- route_id ist im freien gtfs.de-Echtzeitfeed zu 100 % leer (gemessen 2026-08-20
    -- an 2.346 Fahrten im Scope), block_id liefert die Quelle gar nicht (BPULS-003).
    cast(null as varchar) as route_kurzname,
    cast(null as varchar) as block_id,

    halte.quelle

from halte
left join soll
  on  halte.trip_key      = soll.trip_key
  and halte.stop_sequence = soll.stop_sequence
left join zustand
  on  halte.trip_key      = zustand.trip_key
  and halte.stop_sequence = zustand.stop_sequence
left join ankunft
  on  halte.trip_key      = ankunft.trip_key
  and halte.stop_sequence = ankunft.stop_sequence
left join abfahrt
  on  halte.trip_key      = abfahrt.trip_key
  and halte.stop_sequence = abfahrt.stop_sequence
