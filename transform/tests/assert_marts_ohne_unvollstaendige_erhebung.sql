-- Kein Aggregat darf einen Betriebstag ausweisen, an dem die Erhebung nachweislich
-- unvollstaendig war (BPULS-079).
--
-- Warum gegen den **Seed** und nicht gegen `erhebung_vollstaendig`: die Kennzeichnung
-- ist genau das, was hier geprueft wird. Ein Test, der sie gegen sich selbst haelt, ist
-- immer gruen. Derselbe Gedanke wie in assert_marts_ohne_gebietsfremde_abschnitte, das
-- die Bahnhofsnamen frisch gegen die Gebietsliste haelt statt gegen das Flag.
--
-- Der Test greift damit auch den Fall ab, den die Kennzeichnung allein nicht sieht: ein
-- neuer Eintrag im Seed, waehrend die inkrementellen Marts ihre alten Partitionen
-- behalten. Ohne `--full-refresh` steht der Tag dann weiter in den Aggregaten -- und
-- genau das meldet diese Zeile.
--
-- mart_zuglauf und mart_datenqualitaet stehen bewusst **nicht** in der Liste: dort
-- gehoert der Tag hin.

with aggregate as (

    select 'mart_puenktlichkeit' as mart, betriebstag
    from {{ ref('mart_puenktlichkeit') }}

    union all

    select 'mart_verspaetungsentstehung', betriebstag
    from {{ ref('mart_verspaetungsentstehung') }}

    union all

    select 'mart_engpassknoten', betriebstag
    from {{ ref('mart_engpassknoten') }}

    union all

    select 'mart_pufferbilanz', betriebstag
    from {{ ref('mart_pufferbilanz') }}

)

select
    aggregate.mart,
    aggregate.betriebstag,
    count(*) as zeilen

from aggregate
join {{ ref('erhebungsluecken') }} as luecke
  on aggregate.betriebstag between luecke.betriebstag_von and luecke.betriebstag_bis

group by 1, 2
