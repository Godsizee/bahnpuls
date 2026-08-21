-- Die sieben Zustaende eines Halts schliessen einander aus und muessen zusammen exakt
-- den Nenner ergeben. Faellt ein Halt durch alle Bedingungen -- etwa weil eine neue
-- Quelle einen Zustand mitbringt, den die Rangfolge nicht kennt --, verschwindet er
-- lautlos aus der Betrachtung, und genau das ist der Vorwurf, den diese Analyse
-- anderen macht.
--
-- Der Test prueft ausserdem, dass halte_puenktlich nie ueber halte_gemessen liegt:
-- puenktlich ist eine Teilmenge von gemessen, nie eine eigene Menge.
select
    betriebstag,
    quelle,
    route_kurzname,
    schwelle_sek

from {{ ref('mart_puenktlichkeit') }}

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
