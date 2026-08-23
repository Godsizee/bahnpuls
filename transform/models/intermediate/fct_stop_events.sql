{{ config(materialized='table') }}

-- Zentrale Faktentabelle: ein Halt-Ereignis = ein Zug an einer Betriebsstelle, mit
-- Soll und Ist fuer Ankunft und Abfahrt (Schema siehe Bahnpuls_Datenmodell.md).
--
-- Dieses Modell ist die OCP-Nahtstelle des Projekts: eine neue Quelle wird
-- ausschliesslich hier als weiterer union-Zweig angehaengt, Intermediate und Marts
-- bleiben unberuehrt. Die Spaltenliste ist deshalb bewusst explizit ausgeschrieben
-- statt select * -- eine Quelle, die eine Spalte umbenennt oder ergaenzt, soll hier
-- laut auffallen.
--
-- Aktuell haengt genau ein Zweig daran, das Modell ist also fachlich ein
-- Pass-Through. Es existiert wegen dieser Naht, nicht als Vorratsabstraktion: der
-- CH-Zweig hat hier gehangen und ist am 2026-08-23 entfernt worden (die Quelle war
-- synthetisch und trug nichts zu einer Aussage ueber echten Betrieb bei).
--
-- Der Zweig haengt an int_de_stop_events statt an einem Staging-Modell, weil GTFS-RT
-- Snapshots liefert und die Verdichtung auf ein Halt-Ereignis Zustandslogik ist --
-- die gehoert nicht in den Staging-Layer.

select
    betriebstag,
    trip_key,
    stop_sequence,
    stop_id,
    stop_name,
    soll_an,
    soll_ab,
    ist_an,
    ist_ab,
    delay_an_sek,
    delay_ab_sek,
    ist_endgueltig,
    halt_ausgelassen,
    zug_ausgefallen,
    route_kurzname,
    block_id,
    -- Liegt der Halt in VRN + RMV (BPULS-075)? Eine Quelle, die das nicht beantworten
    -- kann, muss hier Stellung beziehen statt die Spalte wegzulassen -- sonst rechnete
    -- sie stillschweigend ausserhalb des Gebiets mit.
    halt_im_gebiet,
    quelle

from {{ ref('int_de_stop_events') }}
