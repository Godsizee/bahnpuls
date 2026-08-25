-- A2 (BPULS-034), Abschnittssicht. Ueber die letzten 30 Betriebstage je Quelle
-- zusammengefasst; die Tagesachse ist auf dieser Seite keine Frage.
--
-- **Begrenzt auf die 200 meistbefahrenen Abschnitte je Quelle**, gewaehlt nach
-- Verkehrsmenge und nicht nach Befund -- dieselbe Ueberlegung wie bei engpassknoten:
-- nach dem Kriterium auszuwaehlen, nach dem hinterher sortiert wird, macht den
-- Ausschnitt zirkulaer.
--
-- Die Linie bleibt im Korn: dieselbe Strecke kann von einer S-Bahn und einem
-- Fernverkehrszug voellig verschieden befahren werden, und der Fahrplan gibt beiden
-- unterschiedliche Zuschlaege. Ueber die Linie hinweg aggregiert die Seite selbst.
with fenster as (

    select quelle, betriebstag
    from mart_pufferbilanz
    group by quelle, betriebstag
    qualify dense_rank() over (partition by quelle order by betriebstag desc) <= 30

),

zusammengefasst as (

    select
        puffer.quelle,
        coalesce(puffer.route_kurzname, 'ohne Liniennummer') as linie,
        -- ADR-014: NULL heisst "der Fahrplan kennt diese Fahrt nicht" und bekommt ein
        -- eigenes Etikett -- eine Auswahlliste kann auf NULL nicht filtern.
        coalesce(puffer.verkehrsart, 'ohne Angabe') as verkehrsart,
        coalesce(puffer.gattung, 'ohne Angabe')     as gattung,
        puffer.von_bezeichnung,
        puffer.nach_bezeichnung,
        bool_and(puffer.bezeichnung_vollstaendig) as bezeichnung_vollstaendig,

        sum(puffer.zuege)                  as zuege,
        sum(puffer.abschnitte_bewertbar)   as bewertbar,
        sum(puffer.aufgeholt)              as aufgeholt,
        sum(puffer.verloren)               as verloren,
        sum(puffer.unveraendert)           as unveraendert,
        sum(puffer.verspaetet_eingefahren) as verspaetet_eingefahren,
        sum(puffer.puenktlich_eingefahren) as puenktlich_eingefahren,
        sum(puffer.reserve_genutzt)        as reserve_genutzt,
        sum(puffer.reserve_genutzt_sek)    as reserve_genutzt_sek,
        sum(puffer.reserve_ungenutzt)      as reserve_ungenutzt,
        sum(puffer.reserve_ungenutzt_sek)  as reserve_ungenutzt_sek,
        sum(puffer.verlust_sek)            as verlust_sek,
        sum(puffer.bilanz_sek)             as bilanz_sek

    from mart_pufferbilanz as puffer
    join fenster
      on  fenster.quelle      = puffer.quelle
      and fenster.betriebstag = puffer.betriebstag
    group by 1, 2, 3, 4, 5, 6

),

-- Auswahl der Abschnitte in einem eigenen Schritt: DuckDB laesst keine
-- Fensterfunktion innerhalb einer Fensterdefinition zu.
ausgewaehlt as (

    select
        quelle,
        von_bezeichnung,
        nach_bezeichnung,
        sum(zuege) as zuege_gesamt
    from zusammengefasst
    group by 1, 2, 3
    qualify row_number() over (
        partition by quelle
        order by zuege_gesamt desc, von_bezeichnung, nach_bezeichnung
    ) <= 200

)

select zusammengefasst.*
from zusammengefasst
join ausgewaehlt
  on  ausgewaehlt.quelle           = zusammengefasst.quelle
  and ausgewaehlt.von_bezeichnung  = zusammengefasst.von_bezeichnung
  and ausgewaehlt.nach_bezeichnung = zusammengefasst.nach_bezeichnung
