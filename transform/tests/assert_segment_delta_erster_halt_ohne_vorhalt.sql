-- Genau der erste Halt einer Fahrt darf keinen Vorhalt haben. Faengt ein ueber
-- Fahrtgrenzen hinweg laufendes lag() ab -- das wuerde am Fahrtanfang einen
-- Laufzeitverlust aus einer fremden Fahrt ausweisen.
--
-- "Erster Halt" ist bewusst die **kleinste stop_sequence der Fahrt**, nicht die 1
-- (geaendert mit BPULS-030). Bei CH entsteht die Sequenz per row_number() und beginnt
-- immer bei 1; GTFS-RT liefert dagegen die Fahrplannummer aus dem Static-Feed, die bei
-- 0 beginnen kann -- und bei einem Zug, der beim Start der Beobachtung schon unterwegs
-- war, bei einem beliebigen Wert. Die Invariante, um die es geht, ist von dieser
-- Nummerierung unabhaengig.

with je_fahrt as (

    select
        trip_key,
        min(nach_stop_sequence) as erste_sequenz

    from {{ ref('int_segment_delta') }}
    group by trip_key

)

select
    sd.trip_key,
    sd.nach_stop_sequence,
    sd.von_stop_sequence

from {{ ref('int_segment_delta') }} sd
join je_fahrt using (trip_key)
where (sd.nach_stop_sequence = je_fahrt.erste_sequenz) != (sd.von_stop_sequence is null)
