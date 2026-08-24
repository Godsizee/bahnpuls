-- Dieselbe Pruefung wie fuer mart_puenktlichkeit, nur ueber die Bahnhofsgruppierung:
-- die sieben Zustaende eines Halts schliessen einander aus und muessen zusammen exakt
-- den Nenner ergeben. Beide Aggregate teilen sich die Einordnung (Makro
-- `halt_zustand()`) -- der Test steht trotzdem zweimal, weil das Gruppieren und Zaehlen
-- je Aggregat eigener Code ist und genau dort ein Halt verlorengehen kann.
--
-- Geprueft wird ausserdem, dass halte_puenktlich nie ueber halte_gemessen liegt
-- (puenktlich ist eine Teilmenge von gemessen) und dass `zuege` nie kleiner ist als die
-- Zahl der Halte mit planmaessiger Ankunft: jede solche Ankunft gehoert zu einer Fahrt,
-- und mehrfach halten kann eine Fahrt an einem Bahnhof nur in Ausnahmefaellen.
select
    betriebstag,
    quelle,
    bahnhof,
    schwelle_sek

from {{ ref('mart_bahnhof') }}

where halte_mit_ankunft is distinct from (
          halte_ausgefallen
        + halte_unbedienter_lauf
        + halte_verkuerzt
        + halte_ausgelassen
        + halte_mehrdeutig
        + halte_ohne_meldung
        + halte_gemessen
      )
   or halte_puenktlich > halte_gemessen
