{{ config(materialized='table') }}

-- Zentrale Faktentabelle: ein Halt-Ereignis = ein Zug an einer Betriebsstelle, mit
-- Soll und Ist fuer Ankunft und Abfahrt (Schema siehe Bahnpuls_Datenmodell.md).
--
-- Dieses Modell ist die OCP-Nahtstelle des Projekts: eine neue Quelle wird
-- ausschliesslich hier als weiterer union-Zweig angehaengt (naechster Zweig:
-- stg_de_gtfsrt, BPULS-030), Intermediate und Marts bleiben unberuehrt. Die
-- Spaltenliste ist deshalb bewusst explizit ausgeschrieben statt select * -- eine
-- Quelle, die eine Spalte umbenennt oder ergaenzt, soll hier laut auffallen.

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
    quelle

from {{ ref('stg_ch_istdaten') }}
