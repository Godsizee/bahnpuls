-- mart_engpassknoten und mart_verspaetungsentstehung rechnen dieselbe Groesse auf zwei
-- Achsen: einmal nach Abschnitt, einmal nach Abschnitt **und Tagesstunde**, und mit
-- unterschiedlichem Schluessel (Name statt stop_id). Beide filtern auf `abschnitt_direkt`
-- und beziehen sich damit auf exakt dieselben Zeilen aus mart_zuglauf.
--
-- Die Summen je Betriebstag und Quelle muessen deshalb uebereinstimmen. Der Test faengt
-- genau das, was sonst niemandem auffiele: eine der beiden Formeln aendert sich, die
-- andere nicht -- das Dashboard zeigt dann in der Rangliste andere Zahlen als im
-- Tagesueberblick, ohne dass irgendetwas fehlschlaegt.
--
-- Verglichen werden Summen und Zaehler, nicht die je-Zug-Werte: die duerfen sich
-- unterscheiden, weil sie auf verschiedenen Nennern beruhen.
with engpass as (

    select
        betriebstag,
        quelle,
        sum(laufzeit_delta_sek_summe)  as laufzeit_summe,
        sum(laufzeit_messwerte)        as laufzeit_messwerte,
        sum(haltezeit_delta_sek_summe) as haltezeit_summe,
        sum(haltezeit_messwerte)       as haltezeit_messwerte
    from {{ ref('mart_engpassknoten') }}
    group by 1, 2

),

entstehung as (

    select
        betriebstag,
        quelle,
        sum(laufzeit_delta_sek_summe)  as laufzeit_summe,
        sum(laufzeit_messwerte)        as laufzeit_messwerte,
        sum(haltezeit_delta_sek_summe) as haltezeit_summe,
        sum(haltezeit_messwerte)       as haltezeit_messwerte
    from {{ ref('mart_verspaetungsentstehung') }}
    group by 1, 2

)

select coalesce(engpass.betriebstag, entstehung.betriebstag) as betriebstag

from engpass
full outer join entstehung
  on  engpass.betriebstag = entstehung.betriebstag
  and engpass.quelle      = entstehung.quelle

where engpass.betriebstag is null
   or entstehung.betriebstag is null
   or engpass.laufzeit_summe     is distinct from entstehung.laufzeit_summe
   or engpass.laufzeit_messwerte is distinct from entstehung.laufzeit_messwerte
   or engpass.haltezeit_summe     is distinct from entstehung.haltezeit_summe
   or engpass.haltezeit_messwerte is distinct from entstehung.haltezeit_messwerte
