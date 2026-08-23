{{ config(
    materialized='incremental',
    incremental_strategy='delete+insert',
    unique_key='betriebstag'
) }}

-- A1 aggregiert: wo entsteht Verspaetung, auf der Strecke oder im Bahnhof
-- (Bahnpuls_Analysen.md). Korn: ein Betriebstag x ein Abschnitt (von -> nach).
--
-- Quelle ist bewusst mart_zuglauf und nicht int_segment_delta: die Entwertung
-- mehrdeutiger und ausgefallener Halte darf nur an einer Stelle definiert sein.
-- Zwei Formulierungen wuerden Detail- und Aggregatsicht auseinanderlaufen lassen --
-- das Dashboard zeigte dann zwei Zahlen, die sich widersprechen, ohne dass ein Test
-- anschlaegt.
--
-- Nur direkte Abschnitte: ohne lueckenlose Folge beschreibt "von -> nach" keine
-- gefahrene Strecke. Der Startbahnhof jeder Fahrt hat keinen Vorhalt und faellt
-- damit heraus -- die Bereitstellungszeit im Ausgangsbahnhof ist eine andere Groesse
-- als der Aufenthalt an einem Zwischenhalt und gehoert nicht in dieselbe Kennzahl.

with zuglauf as (

    select *
    from {{ ref('mart_zuglauf') }}
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

aggregiert as (

    select
        betriebstag,
        quelle,
        von_stop_id,
        von_stop_name,
        stop_id   as nach_stop_id,
        stop_name as nach_stop_name,

        count(distinct trip_key) as zuege,

        -- Summe und Zaehler getrennt, nicht nur der Mittelwert: ueber mehrere Tage
        -- muss aus diesen beiden neu gerechnet werden koennen. Ein Mittelwert von
        -- Mittelwerten gewichtet einen Sonntag wie einen Werktag.
        -- count(spalte) zaehlt NULL nicht mit -- genau gewollt: nicht bestimmbare
        -- Beitraege duerfen den Nenner nicht aufblaehen.
        sum(laufzeit_delta_sek)   as laufzeit_delta_sek_summe,
        count(laufzeit_delta_sek) as laufzeit_messwerte,
        sum(haltezeit_delta_sek)  as haltezeit_delta_sek_summe,
        count(haltezeit_delta_sek) as haltezeit_messwerte,

        -- Danebengestellt statt eingerechnet (CLAUDE.md Regel 8): ohne diese
        -- Spalten verbessert jeder Ausfall die Kennzahl rechnerisch.
        count(*) filter (where zug_ausgefallen)           as ausgefallene_halte,
        count(*) filter (where halt_ausgelassen)          as ausgelassene_halte,
        count(*) filter (where zeitumstellung_mehrdeutig) as halte_zeitumstellung

    from zuglauf
    group by all

)

select
    *,
    -- Je Zug normiert, nie als Rohsumme (CLAUDE.md, Coding-Prinzipien SQL): eine
    -- Summe rankt sonst immer den dichtest befahrenen Abschnitt nach oben, egal wie
    -- gut er laeuft. Nur fuer die Ein-Tages-Sicht -- ueber mehrere Tage aus
    -- Summe/Zaehler neu rechnen, nicht diese Spalte mitteln.
    laufzeit_delta_sek_summe  / nullif(laufzeit_messwerte, 0)  as laufzeit_delta_sek_je_zug,
    haltezeit_delta_sek_summe / nullif(haltezeit_messwerte, 0) as haltezeit_delta_sek_je_zug

from aggregiert
