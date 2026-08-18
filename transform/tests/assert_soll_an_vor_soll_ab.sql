-- An einem Halt kommt der Zug an, bevor er abfaehrt. Beide Zeiten sind absolute
-- Zeitstempel, die Bedingung gilt also auch fuer einen Halt ueber Mitternacht.
-- Eine Verletzung heisst: Datum falsch geparst oder Spalten vertauscht.

select
    trip_key,
    stop_sequence,
    soll_an,
    soll_ab

from {{ ref('fct_stop_events') }}
where soll_an is not null
  and soll_ab is not null
  and soll_an > soll_ab
