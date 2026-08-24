-- Grundlage der Bahnhofsseiten (BPULS-061). Eine Zeile je Betriebstag, Bahnhof und
-- Schwelle -- **nur fuer die Knoten**, die eine eigene Seite haben.
--
-- Warum eingeschraenkt: mart_bahnhof kennt jede benannte Betriebsstelle im Gebiet, in
-- den Produktionsdaten rund 830. Ueber 30 Betriebstage und fuenf Schwellen waeren das
-- ueber 120.000 Zeilen fuer Seiten, die es nicht gibt. Evidence liefert seine Quelldaten
-- an den Browser aus (BPULS-056); die 44 Knoten sind rund 6.600 Zeilen.
--
-- **Begrenzt auf die letzten 30 Betriebstage je Quelle**, dieselbe Grenze und dieselbe
-- Begruendung wie bei der Puenktlichkeitsquelle -- und sie steht auf der Seite selbst.
with tage as (

    select quelle, betriebstag
    from mart_bahnhof
    group by quelle, betriebstag
    -- Je Quelle, nicht global: die Partition ist die Naht, an der eine zweite Quelle
    -- andockt, ohne dass ihre Betriebstage die der ersten verdecken.
    qualify dense_rank() over (partition by quelle order by betriebstag desc) <= 30

)

select
    bahnhof.betriebstag,
    bahnhof.quelle,
    bahnhof.bahnhof,
    bahnhof.slug,
    bahnhof.verbund,
    bahnhof.schwelle_sek,
    bahnhof.schwelle_sek / 60 as schwelle_min,

    bahnhof.zuege,
    bahnhof.halte_mit_ankunft,
    bahnhof.halte_gemessen,
    bahnhof.halte_puenktlich,
    bahnhof.halte_ausgefallen,
    bahnhof.halte_unbedienter_lauf,
    bahnhof.halte_verkuerzt,
    bahnhof.halte_ausgelassen,
    bahnhof.halte_mehrdeutig,
    bahnhof.halte_ohne_meldung,

    bahnhof.quote_gemessen,
    bahnhof.quote_planmaessig,

    -- Summen und Zaehler mitliefern, nicht nur die je-Halt-Werte: die Seite fasst
    -- mehrere Betriebstage zusammen, und ein Mittelwert von Mittelwerten gewichtete
    -- einen Sonntag wie einen Werktag.
    bahnhof.verspaetung_an_sek_summe,
    bahnhof.verspaetung_an_messwerte,
    bahnhof.haltezeit_delta_sek_summe,
    bahnhof.haltezeit_messwerte,
    bahnhof.laufzeit_delta_sek_summe,
    bahnhof.laufzeit_messwerte

from mart_bahnhof as bahnhof
join tage
  on  tage.quelle      = bahnhof.quelle
  and tage.betriebstag = bahnhof.betriebstag

where bahnhof.ist_knoten
