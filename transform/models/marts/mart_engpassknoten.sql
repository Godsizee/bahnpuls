{{ config(
    materialized='incremental',
    incremental_strategy='delete+insert',
    unique_key='betriebstag'
) }}

-- A4 (BPULS-033): A1 ueber die Zeit aggregiert -- wo entsteht **je Zug** die meiste neue
-- Verspaetung, und zu welcher Tagesstunde (Bahnpuls_Analysen.md).
--
-- Korn: ein Betriebstag x eine Quelle x ein Abschnitt (von -> nach) x eine Tagesstunde.
--
-- Dieselbe Groesse wie mart_verspaetungsentstehung, zwei Unterschiede:
--
--   1. **Die Tagesstunde als eigene Achse** -- das ist die Heatmap, um die es geht.
--   2. **Der Abschnitt wird ueber den Namen geschluesselt, nicht ueber die stop_id.**
--
-- Punkt 2 ist keine Kosmetik. Die stop_id-Namensraeume rotieren zwischen den
-- Fahrplan-Veroeffentlichungen fast vollstaendig, und der Echtzeit-Feed referenziert
-- mehrere gleichzeitig (Q6, BPULS-023). Ueber die ID geschluesselt zerfaellt **ein
-- physischer Engpass in mehrere Zeilen**, jede mit einem Bruchteil der Zuege -- und
-- genau die Rangliste, um die es hier geht, waere damit still falsch: der schlimmste
-- Abschnitt landete aufgeteilt im Mittelfeld. Der Name aus stg_de_static vereinigt die
-- Namensraeume wieder.
--
-- Wo kein Name bekannt ist, bleibt die ID stehen und der Abschnitt bleibt fragmentiert.
-- Das ist sichtbar (die Bezeichnung ist erkennbar eine ID) und wird in
-- `bezeichnung_vollstaendig` mitgefuehrt, statt es zu verstecken.
--
-- **Die Stunde ist Wanduhrzeit der planmaessigen Ankunft**, nicht Betriebstagsstunde.
-- Ein Nachtzug mit Ankunft 01:30 zaehlt zur Stunde 1 und gehoert trotzdem zum
-- Betriebstag davor -- genau so soll es sein: die Frage lautet, wann im Tagesverlauf ein
-- Abschnitt klemmt. Halte ohne bestimmbare Soll-Ankunft bekommen `stunde = NULL` und
-- fallen aus der Heatmap, nicht aus der Summe.
--
-- **Nicht umgesetzt: die Verkehrsart** (FV/SPNV/S-Bahn). Die Referenz nennt sie
-- "sofern Klassifizierung sauber moeglich" -- sie waere aus dem Linienpraefix zu raten,
-- und bei aktuell 31,4 % benennbaren Halten waere das Raten auf Geratenem. Lieber offen
-- gelassen als scheinbar beantwortet.

with zuglauf as (

    select *
    from {{ ref('mart_zuglauf') }}
    -- Ohne lueckenlose Folge beschreibt "von -> nach" keine gefahrene Strecke; der
    -- erste Halt einer Fahrt hat keinen Vorhalt. Gleiche Bedingung wie in
    -- mart_verspaetungsentstehung -- ein Konsistenztest haelt beide zusammen.
    -- Und nur Abschnitte, deren **beide** Endpunkte in VRN + RMV liegen (BPULS-075).
    -- Der Collector sammelt Fernverkehrsfahrten mit ihrem ganzen Laufweg; ohne diese
    -- Bedingung stuenden Abschnitte in der Rangliste, die das Zielgebiet nie beruehren.
    where abschnitt_direkt
      and abschnitt_im_gebiet

    {% if is_incremental() %}
    and betriebstag >= (
        select coalesce(max(betriebstag), date '1900-01-01') from {{ this }}
    )
    {% endif %}

),

benannt as (

    select
        betriebstag,
        quelle,
        trip_key,

        coalesce(von_stop_name, von_stop_id) as von_bezeichnung,
        coalesce(stop_name, stop_id)         as nach_bezeichnung,
        von_stop_name is not null and stop_name is not null as bezeichnung_vollstaendig,

        -- Wanduhrstunde der planmaessigen Ankunft am Zielhalt des Abschnitts.
        case when soll_an is not null then extract(hour from soll_an) end as stunde,

        laufzeit_delta_sek,
        haltezeit_delta_sek,
        zug_ausgefallen,
        halt_ausgelassen,
        zeitumstellung_mehrdeutig

    from zuglauf

),

aggregiert as (

    select
        betriebstag,
        quelle,
        von_bezeichnung,
        nach_bezeichnung,
        stunde,

        -- Richtungspaar: derselbe Wert fuer A->B und B->A. Damit laesst sich die
        -- Asymmetrie eines Abschnitts in einer Abfrage gegenueberstellen, ohne die
        -- beiden Zeilen erst ueber eine Zeichenkettenlogik im Dashboard zusammenzusuchen.
        -- Asymmetrische Engpaesse sind ein starkes Indiz fuer Trassenkonflikte in eine
        -- Fahrtrichtung (Bahnpuls_Analysen.md A4).
        least(von_bezeichnung, nach_bezeichnung) || ' <-> '
            || greatest(von_bezeichnung, nach_bezeichnung) as abschnitt_paar,
        von_bezeichnung < nach_bezeichnung                 as richtung_hin,

        bool_and(bezeichnung_vollstaendig) as bezeichnung_vollstaendig,

        count(distinct trip_key) as zuege,

        -- Summe und Zaehler getrennt, nicht nur der Mittelwert: ueber mehrere Tage oder
        -- Stunden muss daraus neu gerechnet werden. Ein Mittel von Mitteln gewichtet
        -- eine Stunde mit zwei Zuegen wie eine mit vierzig.
        -- count(spalte) zaehlt NULL nicht mit -- gewollt: nicht bestimmbare Beitraege
        -- duerfen den Nenner nicht aufblaehen.
        sum(laufzeit_delta_sek)    as laufzeit_delta_sek_summe,
        count(laufzeit_delta_sek)  as laufzeit_messwerte,
        sum(haltezeit_delta_sek)   as haltezeit_delta_sek_summe,
        count(haltezeit_delta_sek) as haltezeit_messwerte,

        -- Danebengestellt statt eingerechnet (CLAUDE.md Regel 8).
        count(*) filter (where zug_ausgefallen)           as ausgefallene_halte,
        count(*) filter (where halt_ausgelassen)          as ausgelassene_halte,
        count(*) filter (where zeitumstellung_mehrdeutig) as halte_zeitumstellung

    from benannt
    group by all

)

select
    *,
    -- Je Zug normiert, nie als Rohsumme (Bahnpuls_Analysen.md A4: "sonst gewinnt immer
    -- der Abschnitt mit dem dichtesten Verkehr, und die Aussage ist wertlos"). Nur fuer
    -- die Sicht auf genau diese Zeile -- ueber Stunden oder Tage hinweg aus
    -- Summe/Zaehler neu rechnen, nicht diese Spalte mitteln.
    laufzeit_delta_sek_summe  / nullif(laufzeit_messwerte, 0)  as laufzeit_delta_sek_je_zug,
    haltezeit_delta_sek_summe / nullif(haltezeit_messwerte, 0) as haltezeit_delta_sek_je_zug

from aggregiert
