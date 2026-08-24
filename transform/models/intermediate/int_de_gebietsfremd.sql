{{ config(materialized='table') }}

-- Entscheidet je Fahrt, ob sie ueberhaupt Bahnverkehr im Zielgebiet ist (BPULS-070).
--
-- **Das Problem:** der Scope-Filter des Collectors ist eine stop_id-Liste aus dem
-- Bahnfahrplan. Seit dem 2026-08-22 fuehrt der Echtzeit-Feed auch Nahverkehr aus dem
-- ganzen Bundesgebiet, und eine Bushaltestelle in Hannover traegt dann die Nummer eines
-- Bahnhofs im Gebiet. Der Filter sieht einen Treffer, die Fahrt ist 300 km entfernt. Von
-- aussen sind die Fahrten nicht zu unterscheiden: sie tragen ueber dieselbe Kollision auf
-- der trip_id sogar plausible Linienbezeichnungen (`RB42` mit 70 Halten, davon 68 nur im
-- Nahverkehr).
--
-- **Die Kollision ist eine zwischen Versionen, nicht zwischen Feeds** -- nachgemessen am
-- 2026-08-23 und anders, als es hier zuerst stand. Innerhalb **einer** Veroeffentlichung
-- teilen sich Bahn- und Nahverkehrsfeed denselben Nummernkreis widerspruchsfrei: von
-- 16.459 rv-Halten stehen 5.092 auch im Nahverkehrsfeed, und **alle 5.092** tragen dort
-- denselben Namen -- es ist derselbe Bahnhof, nicht ein zufaelliger Namensvetter.
-- Kollisionen entstehen erst, wenn eine alte Nummer auf eine neue Version trifft: die
-- stop_id-Werte rotieren zwischen Veroeffentlichungen fast vollstaendig, und der
-- Nahverkehrsfeed besetzt mit 683.872 von rund 695.000 moeglichen Nummern praktisch den
-- ganzen Raum. Eine Bahn-ID von letzter Woche ist deshalb heute fast sicher eine
-- Bushaltestelle.
--
-- Genau das ist am 2026-08-22 passiert, und es kam nicht von hier: der Collector sammelte
-- bis zum 23.08. abends gegen eine Liste, von der nach der Veroeffentlichung noch 48 von
-- 1.916 IDs im Fahrplan standen. Was hereinkam, war zu 92 % Nahverkehr -- die 84 bis 93 %
-- gebietsfremder Fahrten in der Bilanz waren das **richtige** Urteil ueber falsch
-- eingesammelte Daten, kein Fehler dieses Modells (BPULS-073).
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
