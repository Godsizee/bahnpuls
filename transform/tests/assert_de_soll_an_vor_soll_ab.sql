{{ config(severity='warn') }}

-- Soll-Ankunft nach Soll-Abfahrt an demselben Halt, fuer die deutschen Echtzeitdaten.
--
-- Warum hier eine Warnung steht, wo assert_soll_an_vor_soll_ab einen Fehler meldet:
-- dort ist die Soll-Zeit eine Fahrplantatsache und eine Verletzung heisst vertauschte
-- Spalte. Hier ist sie **rekonstruiert** -- Prognose minus Verspaetung --, und Ankunft
-- und Abfahrt kommen aus zwei unabhaengigen Meldungen desselben Halts. Waechst die
-- Abfahrtsverspaetung, waehrend der Zug schon steht, rutscht die zurueckgerechnete
-- Soll-Abfahrt vor die Soll-Ankunft, ohne dass an der Transformation etwas falsch ist.
--
-- **Nicht entwertet, sondern gezaehlt** -- dieselbe Begruendung wie bei
-- assert_de_soll_zeit_im_fenster: die Groessenordnung ist noch nicht gemessen. Am
-- 2026-08-22 traf es 5 Halte, nachdem der Fall drei Betriebstage lang gar nicht
-- vorkam. Wird daraus eine Groesse, die die Haltezeit-Bilanz (A1/A2) verschiebt,
-- gehoert die negative Soll-Haltezeit entwertet und nicht nur gezaehlt.

select
    trip_key,
    stop_sequence,
    soll_an,
    soll_ab,
    -- Damit die gespeicherten Zeilen die Groessenordnung zeigen und nicht nur ihre Zahl.
    date_diff('second', soll_ab, soll_an) as sekunden_verdreht

from {{ ref('fct_stop_events') }}
where quelle = 'de_gtfsrt'
  and soll_an is not null
  and soll_ab is not null
  and soll_an > soll_ab
