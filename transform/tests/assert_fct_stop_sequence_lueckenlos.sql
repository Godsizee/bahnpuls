-- stop_sequence muss je trip_key bei 1 beginnen und lueckenlos aufsteigen -- **fuer
-- Quellen, die das zusichern koennen**. Eine Luecke bedeutet dort einen verlorenen
-- Halt, und damit einen Abschnitt in int_segment_delta, der zwei nicht benachbarte
-- Betriebsstellen als direkte Fahrt ausweisen wuerde.
--
-- Der Test gilt bewusst nicht mehr fuer alle Quellen (geaendert mit BPULS-030). Bei
-- CH entsteht die Sequenz per row_number() im Staging; dort prueft dieser Test die
-- **Transformation**, und Lueckenlosigkeit ist eine echte Zusicherung. Bei GTFS-RT ist
-- stop_sequence dagegen die Fahrplannummer aus dem Static-Feed, keine Position: am
-- 2026-08-20 gegen den echten Feed gemessen begannen 1.773 von 2.187 Fahrten bei 0,
-- 293 bei einem Wert > 1 (der Zug war schon unterwegs), und 395 hatten Luecken, weil
-- ein Snapshot nur einen Teil der Halte liefert.
--
-- Diese Luecken sind eine Eigenschaft der Quelle, kein Fehler der Transformation. Sie
-- werden deshalb nicht wegdefiniert, sondern getragen: abschnitt_direkt markiert jeden
-- Abschnitt, dessen Vorhalt nicht unmittelbar davor liegt, und die Aggregate rechnen
-- nur mit direkten Abschnitten. Ein row_number() ueber die GTFS-RT-Sequenz wuerde
-- luckenhafte Laeufe lueckenlos aussehen lassen -- also genau den Schaden anrichten,
-- den dieser Test verhindern soll.

with je_fahrt as (

    select
        trip_key,
        quelle,
        min(stop_sequence)   as erste,
        max(stop_sequence)   as letzte,
        count(*)             as halte

    from {{ ref('fct_stop_events') }}
    where quelle = 'ch_istdaten'
    group by trip_key, quelle

)

select *
from je_fahrt
where erste != 1
   or letzte != halte
