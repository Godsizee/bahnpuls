{{ config(materialized='table') }}

-- Entscheidet je Fahrt, ob sie ueberhaupt Bahnverkehr im Zielgebiet ist (BPULS-070).
--
-- **Das Problem:** der Scope-Filter des Collectors ist eine stop_id-Liste aus dem
-- Bahnfahrplan. Seit dem 2026-08-22 fuehrt der Echtzeit-Feed auch Nahverkehr aus dem
-- ganzen Bundesgebiet, dessen Nummernkreis zahlenmaessig mit unserem kollidiert -- eine
-- Hannoveraner Bushaltestelle traegt zufaellig die Nummer eines Bahnhofs im Gebiet. Der
-- Filter sieht einen Treffer, die Fahrt ist 300 km entfernt. Von aussen sind die Fahrten
-- nicht zu unterscheiden: sie tragen ueber dieselbe Kollision auf der trip_id sogar
-- plausible Linienbezeichnungen (`RB42` mit 70 Halten, davon 68 nur im Nahverkehr).
--
-- **Warum die Entscheidung ueber die ganze Fahrt faellt und nicht ueber den Halt:** eine
-- einzelne Nummer kann in beiden Nummernkreisen etwas bedeuten. Erst das Verhaeltnis
-- ueber alle Halte einer Fahrt ist eindeutig -- gemessen an der Stichprobe vom
-- 2026-08-22 haben Fremdfahrten im Schnitt 6 von 16 Halten ausschliesslich im
-- Nahverkehrsfeed, echte Bahnfahrten 0,1.
--
-- **Warum nicht ueber die Namen:** naheliegend und gemessen untauglich. Die Regel
-- "mindestens zwei Halte namentlich im Gebiet" liesse nur 5 von 253 Fremdfahrten durch,
-- verwuerfe aber **237 von 1.681 echten Bahnfahrten** -- und 100 der Fremdfahrten haben
-- genau einen benannten Halt, der im Gebiet liegt. Das ist von einem Fernzug, der das
-- Gebiet einmal beruehrt, nicht zu trennen, und genau den will ADR-008 behalten.
--
-- Grundlage ist das Staging-Modell, nicht int_de_stop_events: dieses Modell entscheidet,
-- was dort uebrig bleibt, und darf deshalb nicht von ihm abhaengen.

with halte as (

    -- Ein Halt zaehlt einmal, egal wie oft er gemeldet wurde.
    select distinct
        betriebstag,
        trip_key,
        stop_id

    from {{ ref('stg_de_gtfsrt') }}
    where stop_id is not null

),

bewertet as (

    select
        halte.betriebstag,
        halte.trip_key,
        count(*)                                                       as halte,
        count(bahn.schluessel)                                         as halte_bahnfahrplan,
        count(*) filter (
            where nahverkehr.stop_id is not null and bahn.schluessel is null
        )                                                              as halte_nur_nahverkehr

    from halte
    left join {{ ref('stg_de_static') }} as bahn
      on  bahn.art        = 'stop'
      and bahn.schluessel = halte.stop_id
    left join {{ ref('stg_de_nahverkehrshalt') }} as nahverkehr
      on  nahverkehr.stop_id = halte.stop_id
    group by 1, 2

)

select
    betriebstag,
    trip_key,
    halte,
    halte_bahnfahrplan,
    halte_nur_nahverkehr,

    -- Strikt groesser, nicht "mehr als ein Drittel" o. ae.: bei Gleichstand -- und den
    -- gibt es vor allem bei 0 zu 0, also wenn kein Fahrplan die Fahrt kennt -- bleibt die
    -- Fahrt drin. Eine Fahrt zu verwerfen, ueber die nichts bekannt ist, waere derselbe
    -- Fehler wie die Belegquote von BPULS-066: nicht pruefbar ist nicht widerlegt.
    halte_nur_nahverkehr > halte_bahnfahrplan as gebietsfremd

from bewertet
