-- A5 (BPULS-032). Aggregat, kein Detail -- eine Zeile je Betriebstag, Quelle, Linie und
-- Schwelle.
--
-- **Begrenzt auf die letzten 30 Betriebstage je Quelle**, und zwar von Anfang an: bei
-- rund 300 Linien und fuenf Schwellen sind das 1.500 Zeilen je Tag, im Jahr ueber eine
-- halbe Million. Evidence liefert seine Quelldaten an den Browser aus; dieselbe Rechnung
-- hat die Laufweg-Seite schon einmal unbenutzbar gemacht (BPULS-056). Ein Monat traegt
-- jede Aussage, die diese Seite trifft.
--
-- Die Grenze steht auch auf der Seite selbst. Eine Stichprobe, die sich nicht als solche
-- zu erkennen gibt, ist schlimmer als keine.
with tage as (

    select quelle, betriebstag
    from mart_puenktlichkeit
    group by quelle, betriebstag
    -- Je Quelle, nicht global: die synthetischen CH-Fixtures reichen bis in den Oktober
    -- und wuerden die echten deutschen Tage sonst verdecken.
    qualify dense_rank() over (partition by quelle order by betriebstag desc) <= 30

)

select
    puenktlichkeit.betriebstag,
    puenktlichkeit.quelle,
    coalesce(puenktlichkeit.route_kurzname, 'ohne Liniennummer') as linie,
    puenktlichkeit.route_kurzname is not null                    as linie_bekannt,
    puenktlichkeit.schwelle_sek,
    puenktlichkeit.schwelle_sek / 60                             as schwelle_min,

    puenktlichkeit.fahrten,
    puenktlichkeit.fahrten_ausgefallen,
    puenktlichkeit.fahrten_unbedienter_lauf,
    puenktlichkeit.fahrten_unbedienter_lauf_bestaetigt,
    puenktlichkeit.fahrten_verkuerzt,

    puenktlichkeit.halte_mit_ankunft,
    puenktlichkeit.halte_gemessen,
    puenktlichkeit.halte_puenktlich,
    puenktlichkeit.halte_ausgefallen,
    puenktlichkeit.halte_unbedienter_lauf,
    puenktlichkeit.halte_verkuerzt,
    puenktlichkeit.halte_ausgelassen,
    puenktlichkeit.halte_mehrdeutig,
    puenktlichkeit.halte_ohne_meldung,

    puenktlichkeit.quote_gemessen,
    puenktlichkeit.quote_planmaessig

from mart_puenktlichkeit as puenktlichkeit
join tage
  on  tage.quelle      = puenktlichkeit.quelle
  and tage.betriebstag = puenktlichkeit.betriebstag
