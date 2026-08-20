{{ config(materialized='view') }}

-- Vereinigt die statischen Fahrplaene ueber **alle** Versionen zu je einer Zuordnung
-- pro Schluessel (BPULS-023, Q6).
--
-- Warum vereinigen und nicht die neueste Version nehmen: die stop_id-Werte rotieren
-- zwischen Veroeffentlichungen fast vollstaendig -- von 836 Werten fand sich in einem
-- frischen Download genau einer wieder -- und der Echtzeit-Feed referenziert die
-- Namensraeume **gleichzeitig** weiter. Wer nur die neueste Version nimmt, laesst genau
-- die Halte namenlos, die aus dem alten Namensraum weitergemeldet werden.
--
-- Das ist keine Verletzung von Regel 9. Die Regel verlangt, Ist-Daten gegen die zum
-- Ereigniszeitpunkt gueltige Version zu joinen, und sie zielt auf **Fahrplaninhalte**
-- (Soll-Zeiten, Halteabfolge), die sich mit der Version aendern. Ein Stationsname ist
-- dagegen eine Beschriftung; ihn aus der Vereinigung zu ziehen, verfaelscht keine
-- Kennzahl. Fuer alles, was den Fahrplan selbst betrifft, bleibt die Versionierung.

with stops_roh as (

    select
        stop_id,
        stop_name,
        regexp_extract(filename, 'v=([0-9-]+)', 1) as static_version

    from {{ source('de_static', 'stops') }}
    where stop_id is not null and stop_name is not null

),

stops as (

    select
        stop_id,
        -- Bei Uneinigkeit gewinnt die neueste Version. Dass es Uneinigkeit ueberhaupt
        -- gibt, meldet assert_de_static_namen_eindeutig -- eine wiederverwendete ID mit
        -- neuer Bedeutung waere ein anderer Fall als eine blosse Umbenennung, und den
        -- wuerde diese Vereinigung stillschweigend falsch aufloesen.
        max(stop_name)      as stop_name,
        count(distinct stop_name) as namensvarianten,
        min(static_version) as zuerst_gesehen,
        max(static_version) as zuletzt_gesehen

    from stops_roh
    group by stop_id

),

-- route_id ist im Echtzeit-Feed leer (gemessen 2026-08-20: 0 von 2.346 Fahrten im
-- Scope). Der Weg zum Liniennamen fuehrt deshalb ueber die trip_id.
linien as (

    select
        trips.trip_id,
        max(routes.route_short_name) as route_kurzname,
        count(distinct routes.route_short_name) as namensvarianten

    from {{ source('de_static', 'trips') }} as trips
    join {{ source('de_static', 'routes') }} as routes
      on  trips.route_id = routes.route_id
      -- Version **und** Feed muessen uebereinstimmen. route_id ist je Feed ein eigener
      -- Namensraum: dieselbe Nummer steht im Regional- und im Fernverkehrsdatensatz fuer
      -- verschiedene Linien. Ohne den Feed im Join bekam eine Regionalfahrt den Namen
      -- einer Fernverkehrslinie -- 14.344 Fahrten mit mehrdeutigem Namen, gemeldet vom
      -- eigenen Test, nicht in den Fixtures aufgefallen (dort waren die IDs zufaellig
      -- disjunkt).
      and {{ static_herkunft('trips.filename') }} = {{ static_herkunft('routes.filename') }}
    where trips.trip_id is not null
      and routes.route_short_name is not null
    group by trips.trip_id

)

select
    'stop'                as art,
    stop_id               as schluessel,
    stop_name             as bezeichnung,
    namensvarianten,
    zuerst_gesehen,
    zuletzt_gesehen
from stops

union all

select
    'linie',
    trip_id,
    route_kurzname,
    namensvarianten,
    cast(null as varchar),
    cast(null as varchar)
from linien
