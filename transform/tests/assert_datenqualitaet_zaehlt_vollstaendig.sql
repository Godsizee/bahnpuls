-- Jeder planmaessig vorhandene Halt muss in genau einer Schublade landen: entweder
-- er hat einen Messwert, oder er hat einen benannten Grund, keinen zu haben, oder er
-- faellt in "kein Ist gemeldet".
--
-- Der Test existiert, weil die Gruende sich ueberschneiden duerfen (ein Zug kann
-- ausfallen *und* in der Umstellungsstunde liegen) und deshalb nicht addiert werden
-- koennen. Ohne diesen Test faellt ein Halt, den keine der Bedingungen erwischt,
-- nirgends auf -- die Abdeckungsquote bliebe unauffaellig, waehrend Halte still
-- verschwinden. Zaehlt gegen mart_zuglauf gegen, nicht gegen den Mart selbst.

with detail as (

    select
        betriebstag,
        quelle,
        count(*) filter (where soll_an is not null)  as mit_soll_an,
        count(delay_an_sek)                          as messwerte_an,
        count(*) filter (
            where soll_an is not null
              and delay_an_sek is null
              and (zug_ausgefallen or halt_ausgelassen or zeitumstellung_mehrdeutig)
        ) as mit_grund_an,
        count(*) filter (
            where soll_an is not null
              and delay_an_sek is null
              and not zug_ausgefallen
              and not halt_ausgelassen
              and not zeitumstellung_mehrdeutig
        ) as ohne_ist_an

    from {{ ref('mart_zuglauf') }}
    group by all

),

mart as (

    select betriebstag, quelle, halte_mit_soll_an, delay_an_messwerte, halte_ohne_ist_an
    from {{ ref('mart_datenqualitaet') }}

)

select
    coalesce(detail.betriebstag, mart.betriebstag) as betriebstag

from detail
full outer join mart
  on  detail.betriebstag = mart.betriebstag
  and detail.quelle      = mart.quelle

where detail.betriebstag is null
   or mart.betriebstag is null
   -- Der Mart muss dieselben Zahlen fuehren wie die Detailsicht ...
   or detail.mit_soll_an  is distinct from mart.halte_mit_soll_an
   or detail.messwerte_an is distinct from mart.delay_an_messwerte
   or detail.ohne_ist_an  is distinct from mart.halte_ohne_ist_an
   -- ... und die drei Schubladen muessen den Nenner vollstaendig ausschoepfen.
   or detail.mit_soll_an is distinct from
      (detail.messwerte_an + detail.mit_grund_an + detail.ohne_ist_an)
