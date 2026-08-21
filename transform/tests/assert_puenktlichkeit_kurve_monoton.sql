-- Zwei Eigenschaften der Schwellenkurve, die aus der Definition folgen und deshalb
-- nie verletzt sein duerfen:
--
--   1. **Monoton.** Wer bei 3 Minuten puenktlich ist, ist es bei 6 auch. Eine sinkende
--      Kurve hiesse, dass der Schwellenvergleich nicht auf demselben Wert arbeitet --
--      etwa weil irgendwo Minuten gegen Sekunden gerechnet werden. Das Ergebnis saehe
--      weiter plausibel aus.
--   2. **Nenner konstant.** Die zaehlbaren Spalten ausser halte_puenktlich haengen
--      nicht von der Schwelle ab; sie wiederholen sich je Gruppe fuenfmal. Laufen sie
--      auseinander, ist der cross join gegen die Schwellen falsch verdrahtet, und jede
--      Quote bezoege sich auf eine andere Grundmenge.
with je_gruppe as (

    select
        betriebstag,
        quelle,
        route_kurzname,
        schwelle_sek,
        halte_puenktlich,
        lag(halte_puenktlich) over (
            partition by betriebstag, quelle, route_kurzname order by schwelle_sek
        ) as puenktlich_bei_kleinerer_schwelle,
        min(halte_mit_ankunft) over (partition by betriebstag, quelle, route_kurzname) as nenner_min,
        max(halte_mit_ankunft) over (partition by betriebstag, quelle, route_kurzname) as nenner_max,
        min(halte_gemessen)    over (partition by betriebstag, quelle, route_kurzname) as gemessen_min,
        max(halte_gemessen)    over (partition by betriebstag, quelle, route_kurzname) as gemessen_max,
        min(fahrten)           over (partition by betriebstag, quelle, route_kurzname) as fahrten_min,
        max(fahrten)           over (partition by betriebstag, quelle, route_kurzname) as fahrten_max

    from {{ ref('mart_puenktlichkeit') }}

)

select betriebstag, quelle, route_kurzname, schwelle_sek

from je_gruppe

where halte_puenktlich < coalesce(puenktlich_bei_kleinerer_schwelle, 0)
   or nenner_min   <> nenner_max
   or gemessen_min <> gemessen_max
   or fahrten_min  <> fahrten_max
