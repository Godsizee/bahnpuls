-- Detail- und Aggregatsicht muessen dieselbe Geschichte erzaehlen. Der Test ist
-- keine Wiederholung der Aggregation um ihrer selbst willen: beide Marts laufen
-- unabhaengig voneinander inkrementell, und eine Partition, die nur in einem der
-- beiden ersetzt wird, faellt sonst nirgends auf -- das Dashboard zeigte dann im
-- Ranking andere Zahlen als im Laufweg derselben Fahrt.

with detail as (

    select
        betriebstag,
        quelle,
        von_stop_id,
        stop_id                    as nach_stop_id,
        sum(laufzeit_delta_sek)    as laufzeit_summe,
        count(laufzeit_delta_sek)  as laufzeit_n,
        sum(haltezeit_delta_sek)   as haltezeit_summe,
        count(haltezeit_delta_sek) as haltezeit_n

    from {{ ref('mart_zuglauf') }}
    -- Dieselbe Bedingung wie im Aggregat, beide Teile: mart_zuglauf traegt weiterhin
    -- **alle** Halte einer Fahrt, auch die ausserhalb von VRN + RMV (BPULS-075). Fehlte
    -- hier `abschnitt_im_gebiet`, meldete dieser Test genau den Ausschluss als
    -- Abweichung, den er nicht pruefen soll.
    where abschnitt_direkt
      and abschnitt_im_gebiet
      -- Und dieselbe dritte Bedingung: mart_zuglauf traegt die Betriebstage mit
      -- unvollstaendiger Erhebung weiterhin (BPULS-079), das Aggregat nicht. Ohne
      -- diese Zeile meldete der Test genau den Ausschluss als Abweichung.
      and erhebung_vollstaendig
    group by all

),

aggregat as (

    select
        betriebstag,
        quelle,
        von_stop_id,
        nach_stop_id,
        laufzeit_delta_sek_summe  as laufzeit_summe,
        laufzeit_messwerte        as laufzeit_n,
        haltezeit_delta_sek_summe as haltezeit_summe,
        haltezeit_messwerte       as haltezeit_n

    from {{ ref('mart_verspaetungsentstehung') }}

)

select
    coalesce(detail.betriebstag, aggregat.betriebstag)     as betriebstag,
    coalesce(detail.von_stop_id, aggregat.von_stop_id)     as von_stop_id,
    coalesce(detail.nach_stop_id, aggregat.nach_stop_id)   as nach_stop_id

from detail
full outer join aggregat
  on  detail.betriebstag  = aggregat.betriebstag
  and detail.quelle       = aggregat.quelle
  and detail.von_stop_id  = aggregat.von_stop_id
  and detail.nach_stop_id = aggregat.nach_stop_id

where detail.betriebstag is null
   or aggregat.betriebstag is null
   or detail.laufzeit_summe  is distinct from aggregat.laufzeit_summe
   or detail.laufzeit_n      is distinct from aggregat.laufzeit_n
   or detail.haltezeit_summe is distinct from aggregat.haltezeit_summe
   or detail.haltezeit_n     is distinct from aggregat.haltezeit_n
