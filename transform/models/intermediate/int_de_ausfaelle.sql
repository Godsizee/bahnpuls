{{ config(materialized='table') }}

-- Loest vollstaendige Ausfaelle in Halt-Ereignisse auf (BPULS-032, A5).
--
-- Ein ausgefallener Zug meldet sich im Feed als Aussage ueber die **ganze Fahrt**,
-- ohne stop_time_update. Es gibt also keinen Halt, an dem der Ausfall haengen
-- koennte -- und ohne Halt taucht er in keiner Kennzahl auf. Am Produktionsstand
-- vom 2026-08-21 waren das **alle** Ausfaelle: null gezaehlte bei 52.263 Fahrten.
--
-- **Nachtrag 2026-08-21, nachgemessen:** dieser Feed setzt die trip-level-Markierung
-- ueberhaupt nicht. Auszaehlung des vollstaendigen bundesweiten Feeds: 49.133 Fahrten,
-- **0 mit CANCELED**; ein vollstaendiger Ausfall kommt hier als Fahrt, deren Halte
-- allesamt SKIPPED sind (582 Fahrten, 1,2 %). Dieses Modell ist damit fuer die aktuelle
-- Quelle **wirkungslos, nicht falsch** -- es traegt weiterhin jede Quelle, die die
-- Markierung benutzt. Der offene Punkt ist BPULS-064.
--
-- Dieses Modell holt den Soll-Laufweg aus dem statischen Fahrplan und erzeugt je
-- Soll-Halt eine Zeile, die dasselbe Schema traegt wie ein beobachteter Halt --
-- mit NULL-Verspaetungen und `zug_ausgefallen = true`. Die Zeile behauptet damit
-- nichts ueber Zeiten, nur dass dieser Halt planmaessig vorgesehen war und nicht
-- bedient wurde.
--
-- **Regel 9 gilt hier scharf.** Der Laufweg einer Fahrt ist Fahrplaninhalt und
-- aendert sich mit der Version; gejoint wird gegen die **zum Betriebstag gueltige**
-- Version, nicht gegen die neueste und nicht ueber alle vereinigt. Das ist der
-- Unterschied zu stg_de_static: ein Stationsname ist eine Beschriftung und darf
-- vereinigt werden, eine Halteabfolge nicht.

{% set karenz = var('de_ist_karenz_minuten', 5) %}

with ausfaelle as (

    -- Eine Zeile je ausgefallener Fahrt, mit der letzten Beobachtung.
    select
        betriebstag,
        trip_key,
        trip_id,
        max(snapshot_ts) as letzter_snapshot_ts

    from {{ ref('stg_de_fahrtmeldung') }}
    where zug_ausgefallen
    group by 1, 2, 3

),

-- Fahrten, die **auch** mit Halten gemeldet wurden, sind ueber den normalen Weg
-- bereits vollstaendig da. Sie hier ein zweites Mal aufzuloesen erzeugte Dubletten
-- mit widerspruechlichen Werten -- und zwar lautlos, weil beide Zeilen plausibel
-- aussehen.
ohne_beobachtete_halte as (

    select ausfaelle.*
    from ausfaelle
    where not exists (
        select 1
        from {{ ref('stg_de_gtfsrt') }} as beobachtet
        where beobachtet.trip_key = ausfaelle.trip_key
    )

),

-- Version und Feed nach CLAUDE.md Regel 9. Die Zuordnung steht im Makro, weil
-- int_de_soll_laufweg sie ebenfalls braucht -- eine Regel, die den Laufweg einer
-- Fahrt bestimmt, darf nicht an zwei Stellen leicht verschieden stehen.
eindeutig as (

    {{ gueltige_fahrplanversion('ohne_beobachtete_halte') }}

),

soll_halte as (

    select
        a.betriebstag,
        a.trip_key,
        a.letzter_snapshot_ts,
        f.stop_sequence,
        f.stop_id,
        -- Betriebstagsbeginn plus Sekunden. Genau deshalb liegen die Zeiten als
        -- Sekunden vor und nicht als Uhrzeit: "25:10:00" wird hier zum naechsten
        -- Kalendertag, ohne den Betriebstag zu wechseln (Regel 6).
        case when f.soll_an_sek is not null
             then a.betriebstag::timestamp + to_seconds(f.soll_an_sek) end as soll_an,
        case when f.soll_ab_sek is not null
             then a.betriebstag::timestamp + to_seconds(f.soll_ab_sek) end as soll_ab

    from ohne_beobachtete_halte as a
    join eindeutig as e
      on e.trip_key = a.trip_key
    join {{ ref('stg_de_fahrplanhalt') }} as f
      on  f.trip_id        = a.trip_id
      and f.static_version = e.static_version
      and f.feed           = e.feed

)

select
    soll_halte.betriebstag,
    soll_halte.trip_key,
    soll_halte.stop_sequence::bigint as stop_sequence,
    soll_halte.stop_id,
    halte_name.bezeichnung as stop_name,

    soll_halte.soll_an,
    soll_halte.soll_ab,

    -- Es gab keine Fahrt, also gibt es keine Ist-Zeit und keine Verspaetung. NULL,
    -- nie 0 -- ein Ausfall ist keine Puenktlichkeit (CLAUDE.md Regel 8).
    cast(null as timestamp) as ist_an,
    cast(null as timestamp) as ist_ab,
    cast(null as bigint)    as delay_an_sek,
    cast(null as bigint)    as delay_ab_sek,

    -- Endgueltig, sobald ueber den Soll-Zeitpunkt hinaus beobachtet wurde -- dieselbe
    -- Regel wie beim beobachteten Halt. Ein Ausfall kann zurueckgenommen werden,
    -- solange der Zug noch nicht faellig war.
    coalesce(
        soll_halte.letzter_snapshot_ts >= coalesce(soll_halte.soll_ab, soll_halte.soll_an)
            + interval {{ karenz }} minute,
        false
    ) as ist_endgueltig,

    false as halt_ausgelassen,
    true  as zug_ausgefallen,

    linien_name.bezeichnung as route_kurzname,
    -- Muss mit int_de_stop_events mitziehen: beide Zweige laufen in dieselbe
    -- Faktentabelle, und ein ausgefallener Zug ohne Verkehrsart fiele aus jeder
    -- Auswahl heraus -- ausgerechnet dort, wo Ausfall und Verspaetung nebeneinander
    -- stehen sollen (CLAUDE.md Regel 8).
    {{ verkehrsart('linien_name.feed') }} as verkehrsart,
    {{ zuggattung('linien_name.bezeichnung') }} as gattung,
    cast(null as varchar)   as block_id,

    'de_gtfsrt' as quelle

from soll_halte
left join {{ ref('stg_de_static') }} as halte_name
  on  halte_name.art        = 'stop'
  and halte_name.schluessel = soll_halte.stop_id
left join {{ ref('stg_de_static') }} as linien_name
  on  linien_name.art        = 'linie'
  and linien_name.schluessel = split_part(soll_halte.trip_key, '_', 2)
