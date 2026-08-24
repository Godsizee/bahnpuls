{{ config(materialized='view') }}

-- Halte des Nahverkehrsfeeds, vereinigt ueber alle Versionen (BPULS-070).
--
-- **Wozu:** nicht als Fahrplan, sondern als Negativliste. Der Echtzeit-Feed fuehrt seit
-- dem 2026-08-22 Nahverkehr aus dem ganzen Bundesgebiet, und der Scope-Filter des
-- Collectors kann beides nicht auseinanderhalten -- er sieht nur eine Nummer, die auf
-- seiner Liste steht. Gemessen an einem Nachmittag: von 3.842 unbekannten IDs loesen 116
-- im Bahnfahrplan auf und 3.756 hier.
--
-- Bahn- und Nahverkehrsfeed teilen sich **denselben** Nummernkreis, und innerhalb einer
-- Veroeffentlichung widerspruchsfrei (Beleg in int_de_gebietsfremd). Diese Liste trennt
-- also nicht zwei Namensraeume, sondern beantwortet eine Frage: kennt der Nahverkehr
-- diese Nummer, und der Bahnfahrplan nicht? Gefaehrlich wird es zwischen Versionen --
-- eine Nummer von letzter Woche steht heute fuer eine andere Haltestelle.
--
-- **Warum ueber Versionen vereinigt und nicht die neueste:** dieselbe Rotation wie bei
-- den Bahn-Halten (Q6). Ein Halt, der unter einer alten Nummer weitergemeldet wird,
-- soll weiter erkannt werden. Regel 9 ist davon unberuehrt -- hier steht kein
-- Fahrplaninhalt, sondern die Frage "kennt der Nahverkehr diese Nummer ueberhaupt".

{% set dateien = nahverkehrshalt_dateien() %}

{% if dateien == 0 %}

{#-
    Keine Halteliste auf dem Volume. Regulaerer Zustand bis zum ersten Static-Load
    nach BPULS-070 -- und danach ein Befund, kein Programmierfehler: das Schreiben
    der Liste ist best-effort, damit ein Fehlschlag nie die Version kostet.

    Die leere View laesst jede Fahrt durch. Das ist die richtige Richtung -- lieber
    Fremdverkehr in den Zahlen als echte Fahrten verworfen --, aber es darf nicht
    still passieren: ohne die Warnung unten saehe ein Lauf ohne Liste genauso aus
    wie einer, der nichts zu beanstanden fand.
-#}
{% do exceptions.warn(
    "stg_de_nahverkehrshalt: keine stops.parquet unter " ~ var('de_static_dir') ~
    "/v=*/nv/ gefunden. Fremdverkehr wird nicht erkannt und zaehlt in allen Kennzahlen "
    ~ "mit (BPULS-070). Behebung: 'statictool' erneut laufen lassen"
) %}

select
    cast(null as varchar) as stop_id,
    cast(null as varchar) as stop_name,
    cast(null as date)    as static_version
where false

{% else %}

select
    stop_id,
    -- Bei Uneinigkeit gewinnt der zuletzt gesehene Name. Er dient hier nur der
    -- Nachvollziehbarkeit im Befund ("welche Haltestelle war das?"), in keine
    -- Kennzahl geht er ein.
    max(stop_name)                                                as stop_name,
    max(regexp_extract(filename, 'v=([0-9-]+)', 1))::date         as static_version

from {{ source('de_static', 'nv_stops') }}
where stop_id is not null
group by stop_id

{% endif %}
