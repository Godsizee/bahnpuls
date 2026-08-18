-- Der Laufzeitanteil muss sich auf genau den Vorhalt derselben Fahrt beziehen.
-- Klingt trivial, ist es nicht: eine falsche Fensterpartition oder Sortierung
-- (etwa partition by betriebstag statt trip_key) erzeugt weiterhin plausible
-- Zahlen, verschiebt aber jeden Wasserfall in A1 still um eine Fahrt. Aus dieser
-- lokalen Bedingung folgt die Teleskopsumme des gesamten Laufwegs.

with segment as (

    select * from {{ ref('int_segment_delta') }}

),

verkettet as (

    select
        s.trip_key,
        s.nach_stop_sequence,
        s.von_stop_sequence,
        s.delay_an_sek,
        v.delay_ab_sek as vorhalt_delay_ab_sek,
        s.laufzeit_delta_sek

    from segment s
    left join segment v
           on v.trip_key = s.trip_key
          and v.nach_stop_sequence = s.von_stop_sequence
    where s.von_stop_sequence is not null

)

select *
from verkettet
where laufzeit_delta_sek is distinct from (delay_an_sek - vorhalt_delay_ab_sek)
