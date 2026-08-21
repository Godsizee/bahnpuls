-- Zwei Zerlegungen derselben Menge, beide muessen erschoepfend sein:
--
--   1. nach Ausgang:      aufgeholt + verloren + unveraendert = abschnitte_bewertbar
--   2. nach Eingang:      verspaetet + puenktlich             = abschnitte_bewertbar
--
-- Faellt eine Zeile durch beide Raster -- etwa weil eine Bedingung auf NULL trifft und
-- damit weder wahr noch falsch ist --, verschwindet sie lautlos aus den Anteilen. Die
-- Prozentzahlen auf der Seite blieben unauffaellig und bezoegen sich auf eine andere
-- Grundmenge als angegeben.
--
-- Dazu die Teilmengenbeziehungen: was mit verspaeteter Einfahrt aufgeholt wurde, kann
-- nicht mehr sein als das, was ueberhaupt aufgeholt wurde.
select
    betriebstag,
    quelle,
    route_kurzname,
    von_bezeichnung,
    nach_bezeichnung

from {{ ref('mart_pufferbilanz') }}

where abschnitte_bewertbar is distinct from (aufgeholt + verloren + unveraendert)
   or abschnitte_bewertbar is distinct from (verspaetet_eingefahren + puenktlich_eingefahren)
   or reserve_genutzt   > aufgeholt
   or reserve_ungenutzt > aufgeholt
   or reserve_genutzt + reserve_ungenutzt is distinct from aufgeholt
   -- Betraege koennen nicht negativ sein: sie summieren Betraege, keine Vorzeichen.
   or reserve_genutzt_sek   < 0
   or reserve_ungenutzt_sek < 0
   or verlust_sek           < 0
