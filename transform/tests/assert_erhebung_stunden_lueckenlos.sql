-- Prueft, dass das Stundengeruest in mart_erhebung wirklich lueckenlos ist.
--
-- **Warum das ein eigener Test ist:** der ganze Mart existiert, um eine Stunde ohne
-- Poll sichtbar zu machen. Faellt das Geruest weg -- etwa weil jemand die Stunden
-- wieder aus den Daten gruppiert --, verschwindet genau diese Stunde, und die Tabelle
-- sieht danach **besser** aus als vorher. Ein Fehler, der die Zahlen schoener macht,
-- faellt von allein nie auf.
--
-- Geprueft wird je Quelle: die Zahl der Zeilen muss der Zahl der Stunden zwischen
-- erster und letzter entsprechen.
with spanne as (

    select
        quelle,
        count(*)                                                   as zeilen,
        min(kalendertag + to_hours(stunde))                        as erste,
        max(kalendertag + to_hours(stunde))                        as letzte

    from {{ ref('mart_erhebung') }}
    group by 1

)

select
    quelle,
    zeilen,
    date_diff('hour', erste, letzte) + 1 as erwartete_zeilen

from spanne
where zeilen is distinct from date_diff('hour', erste, letzte) + 1
