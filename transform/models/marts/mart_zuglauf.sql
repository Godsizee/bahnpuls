{{ config(
    materialized='incremental',
    incremental_strategy='delete+insert',
    unique_key='betriebstag'
) }}

-- A1 in der Detailsicht: der Verlauf einer einzelnen Fahrt, aus dem sich der
-- Wasserfall eines Laufwegs lesen laesst (Bahnpuls_Analysen.md). Existiert als
-- eigener Mart, weil das Dashboard ausschliesslich marts abfragen darf (CLAUDE.md
-- Regel 11) -- int_segment_delta bleibt fuer Evidence unsichtbar.
--
-- Inkrementell ab dem ersten Mart (BPULS-016): ein naechtlicher Vollaufbau waechst
-- linear mit der Historie und ist spaeter nur mit Teilumbau zu reparieren.
-- delete+insert ersetzt ganze Tagespartitionen. Der zuletzt geladene Betriebstag
-- wird dabei bewusst jedes Mal neu gebaut: ein Betriebstag reicht bis zu 30 h und
-- ist beim ersten Lauf regelmaessig noch unvollstaendig.

with segment_delta as (

    select *
    from {{ ref('int_segment_delta') }}

    {% if is_incremental() %}
    -- >= statt >: der Grenztag wird neu aufgebaut, nicht ergaenzt -- delete+insert
    -- raeumt ihn vorher weg, sonst stuenden Nachtfahrten doppelt in der Tabelle.
    where betriebstag >= (
        select coalesce(max(betriebstag), date '1900-01-01') from {{ this }}
    )
    {% endif %}

),

markiert as (

    select
        *,
        -- Liegt eine Soll-Zeit in der Umstellungsstunde, kann die Verspaetung um
        -- genau 3.600 s danebenliegen und ist nicht rekonstruierbar (BPULS-013,
        -- Fallstricke in Bahnpuls_Datenmodell.md). Definition im Makro, weil
        -- assert_keine_stille_zeitumstellung genau dieselben Halte meldet.
        {{ ist_umstellungszeit('soll_an') }}
            or {{ ist_umstellungszeit('soll_ab') }} as zeitumstellung_mehrdeutig

    from segment_delta

),

mit_vorhalt as (

    select
        *,
        -- Der Laufzeitanteil rechnet gegen die Abfahrtsverspaetung des Vorhalts.
        -- Ist die mehrdeutig, ist auch dieser Abschnitt unbrauchbar -- sonst
        -- wandert der Fehler eine Zeile weiter und faellt nirgends auf.
        coalesce(lag(zeitumstellung_mehrdeutig) over (
            partition by trip_key order by nach_stop_sequence
        ), false) as vorhalt_zeitumstellung

    from markiert

)

select
    betriebstag,
    trip_key,
    quelle,
    route_kurzname,
    nach_stop_sequence as halt_nr,
    von_stop_id,
    von_stop_name,
    nach_stop_id       as stop_id,
    nach_stop_name     as stop_name,
    abschnitt_direkt,
    soll_an,
    soll_ab,

    -- Alle Kennzahlen werden entwertet, nie korrigiert: NULL heisst durchgehend
    -- "nicht bestimmbar", nie 0 (CLAUDE.md Regel 8). Ausfaelle und ausgelassene
    -- Halte tragen bereits aus int_segment_delta NULL, hier kommt die
    -- Umstellungsstunde dazu.
    case when zeitumstellung_mehrdeutig then null else delay_an_sek end
        as delay_an_sek,
    case when zeitumstellung_mehrdeutig then null else delay_ab_sek end
        as delay_ab_sek,
    case when zeitumstellung_mehrdeutig or vorhalt_zeitumstellung
         then null else laufzeit_delta_sek end
        as laufzeit_delta_sek,
    case when zeitumstellung_mehrdeutig then null else haltezeit_delta_sek end
        as haltezeit_delta_sek,

    halt_ausgelassen,
    zug_ausgefallen,
    ist_endgueltig,
    -- Bleibt als Spalte stehen, statt die Zeile zu entfernen: der Laufweg muss
    -- lueckenlos lesbar bleiben, und mart_datenqualitaet (BPULS-024) zaehlt hier ab.
    zeitumstellung_mehrdeutig

from mit_vorhalt
