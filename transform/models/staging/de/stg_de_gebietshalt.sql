{{ config(materialized='view') }}

-- Die Gebietsliste VRN + RMV, wie sie der Collector filtert (BPULS-074/075).
--
-- Quelle ist der Seed `scope_stops` -- und der ist **dieselbe Datei**, die der
-- Collector liest (`config/scope_stops.csv`, ueber seed-paths eingebunden statt
-- kopiert). Eine zweite Liste danebenzulegen hiesse, dasselbe Gebiet zweimal zu
-- formulieren; sie liefen auseinander, und Collector und Dashboard zeigten
-- verschiedene Gebiete, ohne dass ein Test anschlaegt.
--
-- Zwei Schluessel, aber **nicht gleichrangig**: wo ein Name bekannt ist, entscheidet
-- der Name; die stop_id traegt nur die Halte, die keine Fahrplanversion benennt.
--
-- Warum der Name ueberhaupt gebraucht wird: die stop_id-Werte rotieren zwischen den
-- Veroeffentlichungen fast vollstaendig (Q6, BPULS-023) -- ob ein Halt im Gebiet liegt,
-- aendert sich dadurch nicht. Waere die ID der einzige Schluessel, fiele ein Gebietshalt
-- allein deshalb heraus, weil er eine neue Nummer bekommen hat.
--
-- Warum die ID nicht gleichrangig danebenstehen darf: die Nummernkreise kollidieren
-- (BPULS-070). Gleichrangig gepruegt kamen so `Klandorf` (Brandenburg) und `Pernink`
-- (Tschechien) ins Gebiet -- gemessen am 2026-08-23 an Produktionsdaten.
--
-- Der Name stammt aus demselben Feed wie die Namen in stg_de_static und ist deshalb
-- zeichengleich.
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
