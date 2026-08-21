-- A2 (BPULS-034), Liniensicht: "Verhaeltnis Aufholvermoegen zu Stoerungsanfall je Linie"
-- (Bahnpuls_Analysen.md A2).
--
-- Eigene Quelle statt Aggregation der Abschnittssicht, und das ist kein Vorrat: die
-- Abschnittssicht ist auf die 200 meistbefahrenen Abschnitte begrenzt. Eine Linie
-- daraus zusammenzurechnen hiesse, sie nur auf ihrem befahrensten Teil zu beurteilen --
-- ausgerechnet die Nebenstrecke, auf der es klemmt, fiele heraus. Hier zaehlt jeder
-- Abschnitt mit; das Ergebnis ist eine Zeile je Linie und damit ohnehin klein.
with fenster as (

    select quelle, betriebstag
    from mart_pufferbilanz
    group by quelle, betriebstag
    qualify dense_rank() over (partition by quelle order by betriebstag desc) <= 30

)

select
    puffer.quelle,
    coalesce(puffer.route_kurzname, 'ohne Liniennummer') as linie,

    count(distinct puffer.von_bezeichnung || ' -> ' || puffer.nach_bezeichnung) as abschnitte,
    sum(puffer.zuege)                  as zuege,
    sum(puffer.abschnitte_bewertbar)   as bewertbar,
    sum(puffer.verspaetet_eingefahren) as verspaetet_eingefahren,
    sum(puffer.reserve_genutzt)        as reserve_genutzt,
    sum(puffer.reserve_genutzt_sek)    as reserve_genutzt_sek,
    sum(puffer.puenktlich_eingefahren) as puenktlich_eingefahren,
    sum(puffer.reserve_ungenutzt)      as reserve_ungenutzt,
    sum(puffer.reserve_ungenutzt_sek)  as reserve_ungenutzt_sek,
    sum(puffer.verloren)               as verloren,
    sum(puffer.verlust_sek)            as verlust_sek,
    sum(puffer.bilanz_sek)             as bilanz_sek

from mart_pufferbilanz as puffer
join fenster
  on  fenster.quelle      = puffer.quelle
  and fenster.betriebstag = puffer.betriebstag
group by 1, 2
