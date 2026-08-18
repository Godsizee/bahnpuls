-- Genau der erste Halt einer Fahrt darf keinen Vorhalt haben. Faengt ein ueber
-- Fahrtgrenzen hinweg laufendes lag() ab -- das wuerde am Fahrtanfang einen
-- Laufzeitverlust aus einer fremden Fahrt ausweisen.

select
    trip_key,
    nach_stop_sequence,
    von_stop_sequence

from {{ ref('int_segment_delta') }}
where (nach_stop_sequence = 1) != (von_stop_sequence is null)
