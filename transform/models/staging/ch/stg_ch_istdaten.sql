{{ config(materialized='view') }}

-- Normalisiert das CH-Ist-Daten-Archiv auf das gemeinsame fct_stop_events-Schema
-- (siehe Bahnpuls_Datenmodell.md). Anders als GTFS-RT liefert diese Quelle Soll und
-- Ist pro Halt bereits fertig gejoint -- keine Snapshot-Rekonstruktion noetig, die
-- Zeile hier entspricht schon fast der Zielgranularitaet (1 Zeile = 1 Halt).

with source as (

    -- Spalten explizit statt select *: das Quellschema ist mit 22 Spalten dokumentiert
    -- (Bahnpuls_Datenquellen.md), eine stille Aenderung daran soll hier auffallen --
    -- und nur so lassen sich die Unit-Tests unten gegen eine gemockte Quelle fahren.
    select
        betriebstag,
        fahrt_bezeichner,
        produkt_id,
        linien_text,
        umlauf_id,
        faellt_aus_tf,
        bpuic,
        haltestellen_name,
        ankunftszeit,
        an_prognose,
        an_prognose_status,
        abfahrtszeit,
        ab_prognose,
        ab_prognose_status

    from {{ source('ch_raw', 'istdaten') }}

),

casted as (

    select
        -- BETRIEBSTAG kommt als DD.MM.YYYY (SBB-Format).
        cast(strptime(betriebstag, '%d.%m.%Y') as date)   as betriebstag,
        fahrt_bezeichner                                  as trip_id,
        produkt_id,
        linien_text                                       as route_kurzname,
        nullif(trim(umlauf_id), '')                       as block_id,
        nullif(trim(faellt_aus_tf), '')::boolean          as zug_ausgefallen,
        bpuic                                             as stop_id,
        haltestellen_name                                 as stop_name,
        -- Soll ohne Sekunden, Prognose mit Sekunden (SBB-Format). Bewusst strptime
        -- (nicht try_strptime): eine falsche Formatannahme soll beim ersten Lauf
        -- gegen eine echte Datei laut auffallen, nicht still NULLs erzeugen.
        -- Noch nicht an einer echten Datei verifiziert, siehe Backlog BPULS-011.
        nullif(trim(ankunftszeit), '')                    as ankunftszeit_raw,
        nullif(trim(abfahrtszeit), '')                     as abfahrtszeit_raw,
        nullif(trim(an_prognose), '')                     as an_prognose_raw,
        nullif(trim(ab_prognose), '')                     as ab_prognose_raw,
        nullif(trim(an_prognose_status), '')              as an_prognose_status,
        nullif(trim(ab_prognose_status), '')              as ab_prognose_status

    from source

),

typed as (

    select
        betriebstag,
        trip_id,
        stop_id,
        stop_name,
        route_kurzname,
        block_id,
        zug_ausgefallen,
        case when ankunftszeit_raw is not null
             then strptime(ankunftszeit_raw, '%d.%m.%Y %H:%M') end as soll_an,
        case when abfahrtszeit_raw is not null
             then strptime(abfahrtszeit_raw, '%d.%m.%Y %H:%M') end as soll_ab,
        case when an_prognose_raw is not null
             then strptime(an_prognose_raw, '%d.%m.%Y %H:%M:%S') end as ist_an_roh,
        case when ab_prognose_raw is not null
             then strptime(ab_prognose_raw, '%d.%m.%Y %H:%M:%S') end as ist_ab_roh,
        an_prognose_status,
        ab_prognose_status

    from casted
    -- Verkehrsart-Filter: nur Schienenverkehr, siehe Bahnpuls_Datenquellen.md
    -- (Bus macht ~79% der Tagesdatei aus).
    where produkt_id = 'Zug'

),

normalized as (

    select
        betriebstag,
        betriebstag::varchar || '_' || trip_id            as trip_key,
        stop_id,
        stop_name,
        soll_an,
        soll_ab,
        -- Nur AN_PROGNOSE_STATUS/AB_PROGNOSE_STATUS = 'REAL' ist ein belastbarer
        -- Ist-Wert -- PROGNOSE/GESCHAETZT/UNBEKANNT zaehlen nicht, siehe
        -- Bahnpuls_Datenquellen.md.
        case when an_prognose_status = 'REAL' then ist_an_roh end as ist_an,
        case when ab_prognose_status = 'REAL' then ist_ab_roh end as ist_ab,
        case when an_prognose_status = 'REAL' and soll_an is not null
             then date_diff('second', soll_an, ist_an_roh) end   as delay_an_sek,
        case when ab_prognose_status = 'REAL' and soll_ab is not null
             then date_diff('second', soll_ab, ist_ab_roh) end   as delay_ab_sek,
        (soll_an is null or an_prognose_status = 'REAL')
            and (soll_ab is null or ab_prognose_status = 'REAL') as ist_endgueltig,
        -- CH liefert keinen Flag fuer einen einzelnen ausgelassenen Halt.
        -- DURCHFAHRT_TF ist planmaessige Durchfahrt (kein Halt vorgesehen), keine
        -- Anomalie -- bewusst nicht auf halt_ausgelassen gemappt, siehe Backlog
        -- BPULS-011. Default false statt NULL: "kein Signal" != "war ausgelassen".
        false                                               as halt_ausgelassen,
        coalesce(zug_ausgefallen, false)                    as zug_ausgefallen,
        route_kurzname,
        block_id,
        'ch_istdaten'                                       as quelle

    from typed

),

final as (

    select
        *,
        -- CH liefert keine stop_sequence direkt. Ueber die Soll-Zeit hergeleitet --
        -- damit per Konstruktion luecken- und duplikatfrei je trip_key (row_number).
        row_number() over (
            partition by trip_key
            order by coalesce(soll_an, soll_ab)
        ) as stop_sequence

    from normalized

)

select * from final
