{{ config(severity='warn') }}

-- Umstellungsnaechte sind Pflicht-Testfaelle (Bahnpuls_Datenmodell.md). In der
-- Nacht des letzten Sonntags im Maerz existiert die lokale Stunde 02:00-02:59 gar
-- nicht, in der Nacht des letzten Sonntags im Oktober existiert sie zweimal.
--
-- Soll und Ist sind lokale Wanduhrzeiten ohne Offset. Liegen beide in der
-- doppelten Stunde, ist aus den Daten allein nicht entscheidbar, ob sie denselben
-- Durchgang meinen -- die Verspaetung kann dann um genau 3600 s danebenliegen.
-- Diese Mehrdeutigkeit ist nicht wegrechenbar, auch nicht ueber AT TIME ZONE
-- (geprueft: die Umrechnung waehlt fuer beide Werte denselben Durchgang und
-- aendert die Differenz nicht). Deshalb warn statt error: die betroffenen Halte
-- werden sichtbar gemacht und gehoeren auf die Methodik-Seite (BPULS-015) sowie
-- spaeter in mart_datenqualitaet (BPULS-024) -- nicht aber in eine Kennzahl, und
-- der taegliche Lauf darf an einer Nacht im Jahr nicht scheitern.
--
-- Europe/Zurich und Europe/Berlin haben identische Umstellungsregeln, der Test
-- gilt damit fuer beide Quellen.

with halt_zeiten as (

    select trip_key, stop_sequence, quelle, soll_an as zeit
    from {{ ref('fct_stop_events') }}
    where soll_an is not null

    union all

    select trip_key, stop_sequence, quelle, soll_ab as zeit
    from {{ ref('fct_stop_events') }}
    where soll_ab is not null

),

umstellungstage as (

    select
        *,
        cast(zeit as date) as tag
    from halt_zeiten
    where month(zeit) in (3, 10)

)

select
    trip_key,
    stop_sequence,
    quelle,
    zeit,
    case when month(tag) = 3 then 'uebersprungene Stunde'
         else 'doppelte Stunde' end as umstellungsart

from umstellungstage
-- letzter Sonntag des Monats: Sonntag, dessen Datum + 7 Tage im Folgemonat liegt
where dayofweek(tag) = 0
  and month(tag + interval 7 day) != month(tag)
  and hour(zeit) = 2
