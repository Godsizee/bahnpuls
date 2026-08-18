-- stop_sequence muss je trip_key bei 1 beginnen und lueckenlos aufsteigen
-- (Pflichttest aus Bahnpuls_Datenmodell.md). Eine Luecke bedeutet einen verlorenen
-- Halt -- und damit einen Abschnitt in int_segment_delta, der zwei nicht
-- benachbarte Betriebsstellen als direkte Fahrt ausweisen wuerde.

with je_fahrt as (

    select
        trip_key,
        min(stop_sequence)   as erste,
        max(stop_sequence)   as letzte,
        count(*)             as halte

    from {{ ref('fct_stop_events') }}
    group by trip_key

)

select *
from je_fahrt
where erste != 1
   or letzte != halte
