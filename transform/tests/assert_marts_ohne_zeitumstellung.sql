-- Folgeaufgabe aus BPULS-013: assert_keine_stille_zeitumstellung meldet die Halte in
-- der Umstellungsstunde nur (severity warn) -- ohne diesen Test bliebe die Meldung
-- folgenlos, und dieselben Halte lieferten trotzdem Kennzahlen. Die Verspaetung kann
-- dort um genau 3.600 s danebenliegen (Fallstricke in Bahnpuls_Datenmodell.md).

select
    trip_key,
    halt_nr,
    'Kennzahl trotz Umstellungsstunde' as befund

from {{ ref('mart_zuglauf') }}
where zeitumstellung_mehrdeutig
  and (
      delay_an_sek is not null
      or delay_ab_sek is not null
      or laufzeit_delta_sek is not null
      or haltezeit_delta_sek is not null
  )

union all

-- Der Laufzeitanteil rechnet gegen den Vorhalt. Ist der mehrdeutig, wandert der
-- Fehler eine Zeile weiter -- dort ist er ohne diesen Test unsichtbar, weil die
-- Zeile selbst sauber aussieht.
select
    halt.trip_key,
    halt.halt_nr,
    'Laufzeitanteil gegen mehrdeutigen Vorhalt' as befund

from {{ ref('mart_zuglauf') }} as halt
join {{ ref('mart_zuglauf') }} as vorhalt
  on vorhalt.trip_key = halt.trip_key
 and vorhalt.halt_nr  = halt.halt_nr - 1

where vorhalt.zeitumstellung_mehrdeutig
  and halt.laufzeit_delta_sek is not null
