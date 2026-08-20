{{ config(severity='warn') }}

-- Dasselbe Fenster wie assert_soll_zeit_im_betriebstag_fenster, fuer GTFS-RT aber als
-- **Warnung**: dort ist die Soll-Zeit rekonstruiert (Prognose minus Verspaetung) und der
-- Betriebstag stammt als start_date aus dem Feed. Laufen die beiden auseinander, ist das
-- eine Aussage ueber die Quelle, nicht ueber die Transformation.
--
-- Warum nicht entwerten wie die unplausiblen Verspaetungen: dort war die Groessenordnung
-- gemessen (-83.050 s, ein Zug 23 h zu frueh, unmoeglich). Hier ist sie es noch nicht, und
-- ein Betriebstag darf legitim bis 30 h reichen. Auf Verdacht zu entwerten wuerde
-- moeglicherweise echte Nachtfahrten wegwerfen -- genau die mit den interessantesten
-- Stoerungen. Erst messen, dann entscheiden: die Warnung nennt die Zahl.

with halt_zeiten as (

    select trip_key, stop_sequence, betriebstag, 'soll_an' as feld, soll_an as zeit
    from {{ ref('fct_stop_events') }}
    where quelle = 'de_gtfsrt' and soll_an is not null

    union all

    select trip_key, stop_sequence, betriebstag, 'soll_ab' as feld, soll_ab as zeit
    from {{ ref('fct_stop_events') }}
    where quelle = 'de_gtfsrt' and soll_ab is not null

)

select
    *,
    -- Abstand zum Fenster in Stunden, damit die gespeicherten Fehlerzeilen die
    -- Groessenordnung zeigen und nicht nur ihre Anzahl.
    date_diff('minute', betriebstag::timestamp, zeit) / 60.0 as stunden_nach_tagesbeginn

from halt_zeiten
where zeit < betriebstag::timestamp
   or zeit >= betriebstag::timestamp + interval 30 hour
