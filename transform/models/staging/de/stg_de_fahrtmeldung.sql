{{ config(materialized='view') }}

-- Meldungen ueber eine **ganze Fahrt**, ohne einzelne Halte (BPULS-032).
--
-- Der Collector behaelt sie bewusst (ADR-003): ein vollstaendig ausgefallener Zug
-- erscheint im Feed genau so -- `trip.schedule_relationship = CANCELED` und
-- **kein** `stop_time_update`. stg_de_gtfsrt filtert sie heraus, weil dort jede
-- Zeile ein Halt sein muss; hier werden sie aufgegriffen.
--
-- **Warum das keine Feinheit ist:** am Produktionsstand vom 2026-08-21 (drei
-- Betriebstage, 52.263 Fahrten) wies die Auswertung **null** Ausfaelle aus, bei
-- gleichzeitig 21.823 ausgelassenen Halten. Nicht annaehernd null -- exakt null.
-- Ohne dieses Modell sieht A5 seinen eigenen Gegenstand nicht.
--
-- **Nachtrag 2026-08-21, nachgemessen:** dieser Feed setzt die trip-level-Markierung
-- ueberhaupt nicht. Auszaehlung des vollstaendigen bundesweiten Feeds: 49.133 Fahrten,
-- **0 mit CANCELED**; ein vollstaendiger Ausfall kommt hier als Fahrt, deren Halte
-- allesamt SKIPPED sind (582 Fahrten, 1,2 %). Dieses Modell ist damit fuer die aktuelle
-- Quelle **wirkungslos, nicht falsch** -- es traegt weiterhin jede Quelle, die die
-- Markierung benutzt. Der offene Punkt ist BPULS-064.

with source as (

    select
        trip_id,
        start_date,
        trip_schedule_relationship,
        is_trip_level_only,
        snapshot_timestamp,
        fetched_at

    from {{ source('de_raw', 'stop_events') }}

),

typed as (

    select
        cast(strptime(start_date, '%Y%m%d') as date) as betriebstag,
        trip_id,
        trip_schedule_relationship = 'CANCELED' as zug_ausgefallen,
        timezone('Europe/Berlin', to_timestamp(snapshot_timestamp)) as snapshot_ts,
        timezone('Europe/Berlin', to_timestamp(fetched_at))         as fetched_at

    from source
    -- Genau das Gegenstueck zum Filter in stg_de_gtfsrt: was dort herausfaellt,
    -- faengt dieses Modell auf. Die beiden Mengen sind disjunkt und zusammen
    -- vollstaendig.
    where is_trip_level_only

)

select
    betriebstag,
    betriebstag::varchar || '_' || trip_id as trip_key,
    trip_id,
    zug_ausgefallen,
    snapshot_ts,
    fetched_at,
    'de_gtfsrt' as quelle

from typed
