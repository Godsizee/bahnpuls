{{ config(materialized='table') }}

-- Betriebstage, an denen die Erhebung nachweislich unvollstaendig war (BPULS-079).
-- Ein Bereich aus dem Seed wird hier zu einer Zeile je Betriebstag entfaltet, damit
-- die Marts ueber Gleichheit joinen statt ueber `between`.
--
-- **Warum das ueberhaupt gefuehrt wird.** Ein Tag mit bekannt unvollstaendiger
-- Erhebung ist nicht ein Tag mit wenig Verkehr. Am 22./23.08.2026 sammelte der
-- Collector gegen eine veraltete Gebietsliste (BPULS-073); durch kamen die wenigen
-- Knoten, deren Nummer die Rotation zufaellig ueberlebt hat -- also ueberproportional
-- grosse Bahnhoefe und Fernverkehr. Das ist keine Luecke, sondern eine Schieflage: eine
-- Quote ueber diesen Zeitraum beschreibt diesen Rest, nicht das Gebiet.
--
-- **Entwerten, nicht loeschen** -- dieselbe Logik wie bei Ausfaellen (Regel 8) und bei
-- den gebietsfremden Halten (BPULS-075): die Rohdaten bleiben unangetastet (Regel 1),
-- mart_zuglauf und mart_datenqualitaet behalten den Tag mit Kennzeichnung, und nur die
-- Aggregate schliessen ihn aus.
--
-- **Warum eine gepflegte Liste und kein Schwellwert auf den Daten.** Ein abgeleitetes
-- Kriterium (etwa der Anteil beobachteter Gebietsbahnhoefe) waere selbstpflegend, sein
-- Schwellwert liesse sich hier aber an nichts messen -- im Repo liegen Fixtures, keine
-- Produktionshistorie. Er ginge ungeprueft live und entwertete im Zweifel einen guten
-- Tag oder liesse einen schiefen stehen. Die Frueherkennung kuenftiger Vorfaelle sitzt
-- ohnehin eine Schicht frueher und laeuft stuendlich: `pruefung.sh` meldet eine
-- veraltete Gebietsliste, mart_erhebung fehlende Polls.

with bereiche as (

    select
        betriebstag_von,
        betriebstag_bis,
        grund,
        referenz

    from {{ ref('erhebungsluecken') }}

),

entfaltet as (

    -- distinct, weil sich zwei Bereiche ueberlappen duerfen: derselbe Tag kann aus
    -- zwei Gruenden unvollstaendig sein. Ohne das vervielfachte ein Join auf diese
    -- Tabelle die Zeilen des Marts -- und zwar lautlos.
    select distinct
        cast(unnest(generate_series(
            betriebstag_von, betriebstag_bis, interval 1 day
        )) as date) as betriebstag,
        grund,
        referenz

    from bereiche

)

select
    betriebstag,
    string_agg(grund, ' | ' order by referenz)    as grund,
    string_agg(referenz, ', ' order by referenz)  as referenz

from entfaltet
group by 1
