-- An einem Halt kommt der Zug an, bevor er abfaehrt. Beide Zeiten sind absolute
-- Zeitstempel, die Bedingung gilt also auch fuer einen Halt ueber Mitternacht.
-- Eine Verletzung heisst: Datum falsch geparst oder Spalten vertauscht.
--
-- **Nur fuer Quellen, in denen die Soll-Zeit eine Fahrplantatsache ist.** Bei GTFS-RT
-- ist sie aus Prognose minus Verspaetung **rekonstruiert**, und die beiden Werte eines
-- Halts stammen aus zwei unabhaengigen Meldungen: waechst die Abfahrtsverspaetung,
-- waehrend der Zug schon steht, faellt die zurueckgerechnete Soll-Abfahrt vor die
-- Soll-Ankunft. Das ist keine vertauschte Spalte, sondern eine Eigenschaft der Quelle
-- -- dieselbe Unterscheidung, die assert_de_soll_zeit_im_fenster schon trifft. Fuer
-- GTFS-RT uebernimmt assert_de_soll_an_vor_soll_ab, als Warnung mit Groessenordnung.

select
    trip_key,
    stop_sequence,
    soll_an,
    soll_ab

from {{ ref('fct_stop_events') }}
where quelle != 'de_gtfsrt'
  and soll_an is not null
  and soll_ab is not null
  and soll_an > soll_ab
