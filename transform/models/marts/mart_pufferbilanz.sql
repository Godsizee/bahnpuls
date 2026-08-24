{{ config(
    materialized='incremental',
    incremental_strategy='delete+insert',
    unique_key='betriebstag'
) }}

-- A2 (BPULS-034): Pufferabbau und Fahrplanqualitaet. Fahrplaene enthalten Regelzuschlaege
-- -- Fahrzeit- und Haltezeitreserve, damit kleine Stoerungen aufgeholt werden koennen.
-- Ein negativer Laufzeitanteil aus A1 ist genau das: der Zug hat Reserve gezogen
-- (Bahnpuls_Analysen.md A2).
--
-- Korn: ein Betriebstag x eine Quelle x eine Linie x ein Abschnitt (von -> nach).
--
-- Die Linie gehoert ins Korn, weil A2 zwei Fragen auf verschiedenen Ebenen stellt: "wo
-- liegt zu viel oder zu wenig Reserve" ist eine Frage an den Abschnitt, "wie steht
-- Aufholvermoegen zu Stoerungsanfall" eine an die Linie. Ueber die Linie hinweg
-- aggregiert ergibt dieselbe Tabelle beides.
--
-- Abschnitte werden ueber den **Namen** geschluesselt, aus demselben Grund wie in
-- mart_engpassknoten: die stop_id-Namensraeume rotieren, ueber die ID zerfaellt ein
-- Abschnitt in mehrere Zeilen mit je einem Bruchteil der Zuege.
--
-- ---------------------------------------------------------------------------
-- **Der entscheidende Unterschied: mit welcher Verspaetung faehrt ein Zug ein.**
--
-- Dieselbe Beobachtung -- ein Zug wird auf einem Abschnitt schneller -- bedeutet zwei
-- voellig verschiedene Dinge, je nachdem, wie er hineingefahren ist:
--
--   * **Verspaetet eingefahren und aufgeholt:** die Reserve hat gewirkt. Das ist der
--     Zweck des Regelzuschlags, und ein hoher Anteil ist ein **gutes** Zeichen.
--   * **Puenktlich eingefahren und trotzdem frueher angekommen:** der Zug brauchte die
--     Reserve nicht und ist ihr davongefahren. Ein hoher Anteil heisst, dass die
--     Fahrzeit zu grosszuegig bemessen ist -- **Kapazitaet, die im Fahrplan verschenkt
--     wird**, und der Zug steht am naechsten Halt und wartet.
--
-- Wer beides in eine Kennzahl "Anteil aufholender Zuege" wirft, bekommt eine Zahl, die
-- fuer zwei gegensaetzliche Befunde denselben Wert annimmt. Deshalb werden beide Faelle
-- hier **getrennt gezaehlt** und nie summiert.
--
-- **Widerspruch in der Referenz, bewusst nicht stillschweigend aufgeloest:**
-- Bahnpuls_Analysen.md sagt einerseits "negative Deltas sind Puffernutzung" und
-- andererseits "ein Abschnitt, auf dem fast jeder Zug Reserve zieht, hat eine zu knapp
-- bemessene Fahrzeit". Beides zusammen geht nicht auf: wenn dort fast jeder Zug schneller
-- faehrt als der Fahrplan vorsieht, ist die Fahrzeit zu **grosszuegig**, nicht zu knapp.
-- Zu knapp bemessen ist eine Fahrzeit, auf der Zuege systematisch **verlieren** --
-- `verloren_anteil`, nicht `aufgeholt_anteil`. Das Modell rechnet die belastbare Lesart;
-- die Referenz ist entsprechend zu korrigieren.
-- ---------------------------------------------------------------------------

-- Ab wann ein Zug als verspaetet in den Abschnitt einfaehrt. Annahme, deshalb als
-- Variable und auf der Methodik-Seite ausgewiesen: sie entscheidet, welcher der beiden
-- Faelle oben zutrifft, und damit die Aussage.
{% set puenktlich_grenze = var('a2_puenktlich_grenze_sek', 60) %}

with zuglauf as (

    select *
    from {{ ref('mart_zuglauf') }}
    -- Ohne lueckenlose Folge beschreibt "von -> nach" keine gefahrene Strecke.
    -- Und nur Abschnitte, deren **beide** Endpunkte in VRN + RMV liegen (BPULS-075).
    -- Der Collector sammelt Fernverkehrsfahrten mit ihrem ganzen Laufweg; ohne diese
    -- Bedingung stuenden Abschnitte in der Rangliste, die das Zielgebiet nie beruehren.
    where abschnitt_direkt
      and abschnitt_im_gebiet
      -- Und keine Betriebstage mit bekannt unvollstaendiger Erhebung (BPULS-079). Am
      -- 22./23.08.2026 kam durch, was die Rotation der Haltestellennummern zufaellig
      -- ueberlebt hat -- ueberproportional grosse Bahnhoefe und Fernverkehr. Eine
      -- Rangliste ueber diesen Rest beschreibt nicht das Gebiet.
      and erhebung_vollstaendig

    {% if is_incremental() %}
    and betriebstag >= (
        select coalesce(max(betriebstag), date '1900-01-01') from {{ this }}
    )
    {% endif %}

),

eingang as (

    select
        betriebstag,
        quelle,
        route_kurzname,
        trip_key,
        coalesce(von_stop_name, von_stop_id) as von_bezeichnung,
        coalesce(stop_name, stop_id)         as nach_bezeichnung,
        von_stop_name is not null and stop_name is not null as bezeichnung_vollstaendig,

        laufzeit_delta_sek,

        -- Verspaetung beim Verlassen des Vorhalts, ohne zweites Fenster: der Mart fuehrt
        -- delay_an und laufzeit_delta, und delay_an - laufzeit_delta ist genau die
        -- Abfahrtsverspaetung am Vorhalt. Ist eines von beiden nicht bestimmbar, ist es
        -- auch der Eingangszustand -- dann faellt die Zeile aus der Auswertung, statt
        -- als "puenktlich eingefahren" gezaehlt zu werden.
        delay_an_sek - laufzeit_delta_sek as eingang_delay_sek

    from zuglauf

),

eingeordnet as (

    select
        *,
        eingang_delay_sek >  {{ puenktlich_grenze }} as verspaetet_eingefahren,
        eingang_delay_sek <= {{ puenktlich_grenze }} as puenktlich_eingefahren

    from eingang
    -- Nur bestimmbare Abschnitte. NULL heisst "nicht bestimmbar", nie 0 (Regel 8) --
    -- eine Zeile ohne Delta traegt zu keiner der beiden Fragen etwas bei.
    where laufzeit_delta_sek is not null
      and eingang_delay_sek  is not null

)

select
    betriebstag,
    quelle,
    route_kurzname,
    von_bezeichnung,
    nach_bezeichnung,
    bool_and(bezeichnung_vollstaendig) as bezeichnung_vollstaendig,

    count(distinct trip_key) as zuege,
    count(*)                 as abschnitte_bewertbar,

    -- Die drei Ausgaenge schliessen einander aus und ergeben zusammen
    -- abschnitte_bewertbar. Ein Test prueft das.
    count(*) filter (where laufzeit_delta_sek < 0) as aufgeholt,
    count(*) filter (where laufzeit_delta_sek > 0) as verloren,
    count(*) filter (where laufzeit_delta_sek = 0) as unveraendert,

    -- Eingangszustand, ebenfalls erschoepfend.
    count(*) filter (where verspaetet_eingefahren) as verspaetet_eingefahren,
    count(*) filter (where puenktlich_eingefahren) as puenktlich_eingefahren,

    -- **Reserve hat gewirkt**: verspaetet hinein, Verspaetung abgebaut.
    count(*) filter (where verspaetet_eingefahren and laufzeit_delta_sek < 0)
        as reserve_genutzt,
    -- Betrag der dabei abgebauten Verspaetung, als positive Zahl.
    coalesce(sum(-laufzeit_delta_sek) filter (
        where verspaetet_eingefahren and laufzeit_delta_sek < 0
    ), 0) as reserve_genutzt_sek,

    -- **Reserve lag brach**: puenktlich hinein, trotzdem frueher angekommen. Der Zug
    -- brauchte den Zuschlag nicht.
    count(*) filter (where puenktlich_eingefahren and laufzeit_delta_sek < 0)
        as reserve_ungenutzt,
    coalesce(sum(-laufzeit_delta_sek) filter (
        where puenktlich_eingefahren and laufzeit_delta_sek < 0
    ), 0) as reserve_ungenutzt_sek,

    -- **Zeit verloren**: der Abschnitt hat gekostet, unabhaengig vom Eingangszustand.
    -- Systematischer Verlust hier ist das Kennzeichen einer zu knapp bemessenen
    -- Fahrzeit -- nicht ein hoher Aufholanteil.
    coalesce(sum(laufzeit_delta_sek) filter (where laufzeit_delta_sek > 0), 0)
        as verlust_sek,

    -- Nettobilanz des Abschnitts. Positiv: hier geht Zeit verloren. Negativ: hier wird
    -- im Saldo aufgeholt. Bewusst zusaetzlich zu den Einzelrichtungen -- der Saldo
    -- allein verschweigt, ob sich zwei grosse Effekte aufheben oder nichts passiert.
    sum(laufzeit_delta_sek) as bilanz_sek

from eingeordnet
group by 1, 2, 3, 4, 5
