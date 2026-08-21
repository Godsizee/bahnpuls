-- Ein aufgeloester Ausfall behauptet nichts ueber Zeiten. Er traegt Soll-Zeiten
-- aus dem Fahrplan und sonst NULL -- eine Verspaetung von 0 waere die Aussage
-- "puenktlich", und genau die darf ein Ausfall nie bekommen (CLAUDE.md Regel 8).
--
-- Ausserdem: jede Zeile muss mindestens eine Soll-Zeit haben. Ein Halt ohne Soll-An
-- und ohne Soll-Ab ist kein Halt, sondern eine leere Zeile im Laufweg.
select
    trip_key,
    stop_sequence

from {{ ref('int_de_ausfaelle') }}

where delay_an_sek is not null
   or delay_ab_sek is not null
   or ist_an is not null
   or ist_ab is not null
   or not zug_ausgefallen
   or halt_ausgelassen
   or (soll_an is null and soll_ab is null)
