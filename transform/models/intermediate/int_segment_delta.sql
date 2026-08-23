{{ config(materialized='table') }}

-- A1 -- Zerlegung der Verspaetungsaenderung in Laufzeit- und Haltezeitanteil
-- (fachliche Deutung in Bahnpuls_Analysen.md, Formel in Bahnpuls_Datenmodell.md).
-- Eine Zeile je Halt-Ereignis, damit der Wasserfall eines Laufwegs vollstaendig
-- daraus lesbar ist: Startverspaetung am ersten Halt, danach je Halt ein Laufzeit-
-- und ein Haltezeitbeitrag.

with stop_events as (

    select
        betriebstag,
        trip_key,
        quelle,
        route_kurzname,
        stop_sequence,
        stop_id,
        stop_name,
        soll_an,
        soll_ab,
        halt_ausgelassen,
        zug_ausgefallen,
        ist_endgueltig,
        halt_im_gebiet,
        -- Ein ausgefallener Zug oder ein ausgelassener Halt hat keine Verspaetung --
        -- nicht die Verspaetung 0 (CLAUDE.md Regel 8). Die Zeile bleibt trotzdem in
        -- der Reihenfolge stehen: faellt sie heraus, wuerde der Abschnitt darueber
        -- hinweg als direkte Fahrt zwischen zwei nicht benachbarten Betriebsstellen
        -- erscheinen. So werden stattdessen die angrenzenden Deltas ehrlich NULL.
        case when zug_ausgefallen or halt_ausgelassen
             then null else delay_an_sek end as delay_an_sek,
        case when zug_ausgefallen or halt_ausgelassen
             then null else delay_ab_sek end as delay_ab_sek

    from {{ ref('fct_stop_events') }}

),

with_previous as (

    select
        *,
        lag(stop_sequence) over w as von_stop_sequence,
        lag(stop_id)       over w as von_stop_id,
        lag(stop_name)     over w as von_stop_name,
        lag(delay_ab_sek)  over w as von_delay_ab_sek,
        lag(halt_im_gebiet) over w as von_halt_im_gebiet

    from stop_events
    window w as (partition by trip_key order by stop_sequence)

)

select
    betriebstag,
    trip_key,
    quelle,
    route_kurzname,
    von_stop_sequence,
    von_stop_id,
    von_stop_name,
    stop_sequence                         as nach_stop_sequence,
    stop_id                               as nach_stop_id,
    stop_name                             as nach_stop_name,
    -- Nur bei lueckenloser Folge beschreibt der Abschnitt wirklich eine direkte
    -- Fahrt. Fuer CH per Konstruktion immer wahr (row_number im Staging), fuer
    -- kuenftige Quellen mit echter stop_sequence nicht garantiert.
    von_stop_sequence = stop_sequence - 1 as abschnitt_direkt,
    von_halt_im_gebiet,
    halt_im_gebiet as nach_halt_im_gebiet,
    -- Ein Abschnitt gehoert dem Gebiet nur, wenn **beide** Endpunkte darin liegen
    -- (BPULS-075). Genau daran scheiterte der Anlass: `Koeln Hbf -> Koeln Messe/Deutz`
    -- stand mit 261 Zuegen in der Engpass-Rangliste, obwohl Koeln in keiner Halteliste
    -- vorkommt. Am ersten Halt einer Fahrt gibt es keinen Vorhalt -- dort ist der Wert
    -- false, nicht NULL: es gibt keinen Abschnitt, ueber den etwas unbekannt waere.
    coalesce(von_halt_im_gebiet and halt_im_gebiet, false) as abschnitt_im_gebiet,
    soll_an,
    soll_ab,
    delay_an_sek,
    delay_ab_sek,
    -- Laufzeitverlust: was auf dem Abschnitt vom Vorhalt hierher entstanden ist.
    -- Negativ ist kein Fehler, sondern Pufferabbau (A2).
    delay_an_sek - von_delay_ab_sek       as laufzeit_delta_sek,
    -- Haltezeitverlust: was waehrend des Halts entstanden ist. NULL, wo eine der
    -- beiden Zeiten fehlt -- der Anteil ist dann nicht bestimmbar und wird als
    -- unbekannt ausgewiesen, nie als 0 (Fallstrick A1 in Bahnpuls_Analysen.md).
    delay_ab_sek - delay_an_sek           as haltezeit_delta_sek,
    halt_ausgelassen,
    zug_ausgefallen,
    ist_endgueltig

from with_previous
