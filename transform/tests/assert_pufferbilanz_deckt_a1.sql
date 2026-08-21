-- mart_pufferbilanz zerlegt genau die Abschnitte, die mart_verspaetungsentstehung
-- summiert: beide filtern auf `abschnitt_direkt`, beide zaehlen nur bestimmbare
-- Laufzeitanteile.
--
-- Eine Ausnahme, und die ist der Grund fuer den `<=`-Vergleich statt Gleichheit: A2
-- braucht zusaetzlich einen bestimmbaren **Eingangszustand** (delay_an minus
-- laufzeit_delta). Wo der fehlt, faellt die Zeile aus A2 heraus, nicht aus A1. A2 kann
-- deshalb weniger Zeilen zaehlen als A1, aber niemals mehr -- und die Summe der
-- Laufzeitanteile kann in A2 nicht groesser ausfallen als die Gesamtbewegung in A1.
with puffer as (

    select
        betriebstag,
        quelle,
        sum(abschnitte_bewertbar) as bewertbar
    from {{ ref('mart_pufferbilanz') }}
    group by 1, 2

),

entstehung as (

    select
        betriebstag,
        quelle,
        sum(laufzeit_messwerte) as messwerte
    from {{ ref('mart_verspaetungsentstehung') }}
    group by 1, 2

)

select coalesce(puffer.betriebstag, entstehung.betriebstag) as betriebstag

from puffer
full outer join entstehung
  on  puffer.betriebstag = entstehung.betriebstag
  and puffer.quelle      = entstehung.quelle

where entstehung.betriebstag is null
   or puffer.bewertbar > entstehung.messwerte
