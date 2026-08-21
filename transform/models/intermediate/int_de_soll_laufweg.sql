{{ config(materialized='table') }}

-- Haelt den **beobachteten** Laufweg gegen den **planmaessigen** -- und zwar nur fuer
-- die Fahrten, bei denen es auf den Unterschied ankommt (BPULS-064).
--
-- **Wofuer:** mart_puenktlichkeit fuehrt seit dem 2026-08-21 den Zustand
-- `unbedienter_lauf` -- ein Lauf, in dem kein einziger Halt bedient wurde. In diesem
-- Feed ist das die Form, in der ein vollstaendiger Ausfall ankommt: er setzt
-- `trip.schedule_relationship = CANCELED` nie (gemessen am 2026-08-21: 49.133 Fahrten,
-- 0 Treffer), streicht dafuer die Halte einzeln.
--
-- **Die Schwaeche dieses Zustands ist die Beobachtungsluecke**, und die schliesst dieses
-- Modell: `halt_nr` ist die Fahrplannummer, und ein Zug, der beim Beobachtungsbeginn
-- schon unterwegs war, taucht erst ab seinem naechsten Halt in den Daten auf. Waeren
-- davon nur gestrichene Halte uebrig, saehe eine **gekappte** Fahrt aus wie eine
-- **ganz ausgefallene**. Erst der Soll-Laufweg trennt die beiden Faelle.
--
-- **Warum nur die Kandidaten und nicht alle Fahrten:** der Soll-Fahrplan hat rund 1,65
-- Mio. Zeilen je Version, die Kandidaten sind rund ein Prozent der Fahrten. Alles
-- Uebrige zu joinen kostet Zeit fuer eine Frage, die dort niemand stellt (YAGNI). Kommt
-- eine zweite Frage an den Soll-Laufweg dazu, wird dieses Modell verbreitert -- der
-- Filter steht in einer eigenen CTE und ist genau eine Zeile.

with lauf as (

    select
        betriebstag,
        trip_key,
        count(*)                   as beobachtete_halte,
        bool_and(halt_ausgelassen) as alle_ausgelassen,
        bool_or(zug_ausgefallen)   as irgendwo_ausgefallen

    from {{ ref('int_de_stop_events') }}
    group by 1, 2

),

-- trip_id kommt aus dem Staging und nicht aus dem trip_key: der Schluessel ist
-- `betriebstag || '_' || trip_id`, und eine trip_id, die selbst einen Unterstrich
-- enthaelt, wuerde beim Zerlegen still abgeschnitten.
trip_ids as (

    select distinct trip_key, trip_id
    from {{ ref('stg_de_gtfsrt') }}

),

kandidaten as (

    select
        lauf.betriebstag,
        lauf.trip_key,
        trip_ids.trip_id,
        lauf.beobachtete_halte

    from lauf
    join trip_ids on trip_ids.trip_key = lauf.trip_key
    -- Ausgefallene Fahrten sind bereits ueber die Meldung aufgeloest und tragen in
    -- mart_puenktlichkeit den hoeheren Zustand; sie hier zu pruefen aendert nichts.
    where lauf.alle_ausgelassen
      and not lauf.irgendwo_ausgefallen

),

-- Regel 9 im Makro, gemeinsam mit int_de_ausfaelle. Fahrten ohne eindeutige Zuordnung
-- (kein aelterer Fahrplan, trip_id unbekannt, trip_id in beiden Feeds) fallen hier
-- **ganz heraus** -- dieses Modell enthaelt dann keine Zeile fuer sie. Nachgelagert wirkt
-- das wie "nicht belegt", und genau so soll es sein: belegt ist nur, was belegbar war.
zuordnung as (

    {{ gueltige_fahrplanversion('kandidaten') }}

),

beobachtete_positionen as (

    -- Auf die Kandidaten eingeschraenkt: ohne den Filter waere das ein distinct ueber
    -- den gesamten Halt-Bestand (Millionen Zeilen, stuendlich im Container), fuer eine
    -- Frage, die nur rund ein Prozent der Fahrten betrifft.
    select distinct trip_key, stop_sequence
    from {{ ref('int_de_stop_events') }}
    where trip_key in (select trip_key from kandidaten)

),

abdeckung as (

    select
        kandidaten.betriebstag,
        kandidaten.trip_key,
        zuordnung.static_version,
        zuordnung.feed,
        kandidaten.beobachtete_halte,

        count(*) as soll_halte,

        -- Gezaehlt wird die **Deckung der Soll-Halte durch beobachtete**, nicht ein
        -- Vergleich zweier Anzahlen. Zwei gleich grosse, aber verschiedene Mengen
        -- gaeben sonst "vollstaendig" aus, und genau dieser Fall -- vorne fehlt ein
        -- Halt, hinten ist einer zu viel -- ist der, um den es geht.
        count(*) filter (where beobachtete_positionen.stop_sequence is not null)
            as soll_halte_beobachtet

    from kandidaten
    join zuordnung
      on zuordnung.trip_key = kandidaten.trip_key
    join {{ ref('stg_de_fahrplanhalt') }} as fahrplan
      on  fahrplan.static_version = zuordnung.static_version
      and fahrplan.feed           = zuordnung.feed
      and fahrplan.trip_id        = kandidaten.trip_id
    left join beobachtete_positionen
      on  beobachtete_positionen.trip_key      = kandidaten.trip_key
      and beobachtete_positionen.stop_sequence = fahrplan.stop_sequence
    group by 1, 2, 3, 4, 5

)

select
    betriebstag,
    trip_key,
    static_version,
    feed,
    beobachtete_halte,
    soll_halte,
    soll_halte_beobachtet,
    soll_halte_beobachtet = soll_halte as laufweg_vollstaendig

from abdeckung
