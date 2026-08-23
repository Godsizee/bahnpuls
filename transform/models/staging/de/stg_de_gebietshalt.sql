{{ config(materialized='view') }}

-- Die Gebietsliste VRN + RMV, wie sie der Collector filtert (BPULS-074/075).
--
-- Quelle ist der Seed `scope_stops` -- und der ist **dieselbe Datei**, die der
-- Collector liest (`config/scope_stops.csv`, ueber seed-paths eingebunden statt
-- kopiert). Eine zweite Liste danebenzulegen hiesse, dasselbe Gebiet zweimal zu
-- formulieren; sie liefen auseinander, und Collector und Dashboard zeigten
-- verschiedene Gebiete, ohne dass ein Test anschlaegt.
--
-- Zwei Schluessel, nicht einer: **stop_id und stop_name**. Die stop_id-Werte rotieren
-- zwischen den Fahrplan-Veroeffentlichungen fast vollstaendig (Q6, BPULS-023) -- ob ein
-- Halt im Gebiet liegt, aendert sich dadurch aber nicht. Waere die ID der einzige
-- Schluessel, fiele ein Gebietshalt allein deshalb aus dem Gebiet, weil er eine neue
-- Nummer bekommen hat. Der Name ist hier die stabilere Beschriftung; er stammt aus
-- demselben Feed wie die Namen in stg_de_static und ist deshalb zeichengleich.
--
-- Die Liste ist Konfiguration, nicht einkompiliert (ADR-008), und sie ist bewusst
-- **nicht** nach Verbund/Agency gebaut (CLAUDE.md Regel 7).

select
    stop_id,
    -- trim, weil die Liste aus einer CSV kommt: ein Leerzeichen am Rand macht aus einem
    -- Gebietshalt lautlos einen fremden.
    trim(stop_name) as stop_name

from {{ ref('scope_stops') }}
where stop_id is not null
