{{ config(
    materialized='incremental',
    incremental_strategy='delete+insert',
    unique_key='betriebstag'
) }}

-- Das Abdeckungsprotokoll (BPULS-024). Kein Nice-to-have: ohne Beleg, dass die
-- Datenbasis lueckenlos war, ist jede andere Zahl angreifbar
-- (Bahnpuls_Datenmodell.md).
--
-- Korn: ein Betriebstag x eine Quelle.
--
-- Quelle ist mart_zuglauf, nicht int_segment_delta -- dieselbe Begruendung wie bei
-- mart_verspaetungsentstehung: die Entwertungsregeln duerfen nur einmal existieren.
-- Zaehlte dieser Mart auf der Zwischenschicht, meldete er eine Abdeckung, die das
-- Dashboard nie zu sehen bekommt.
--
-- Die zentrale Unterscheidung dieses Modells: **planmaessig nicht vorhanden ist
-- nicht dasselbe wie nicht bestimmbar** (BPULS-015). Am Startbahnhof gibt es keine
-- Ankunft, am Endbahnhof keine Abfahrt. Wer beides in denselben Nenner wirft, misst
-- eine Datenluecke, wo der Fahrplan schlicht nichts vorsieht, und redet die
-- Abdeckung systematisch schlecht.
--
-- Was hier noch fehlt: **Feed-Luecken**, also fehlende oder ausgefallene Polls der
-- GTFS-RT-Sammlung. Die sind aus den Ist-Daten allein nicht sichtbar, sie stecken in
-- den Rohdatei-Partitionen der Sammlung; sie kommen mit stg_de_gtfsrt (BPULS-030).
-- Fuer die CH-Tagesdateien existiert das Problem nicht -- dort ist eine Luecke eine
-- fehlende Datei, kein fehlender Snapshot.

with zuglauf as (

    select *
    from {{ ref('mart_zuglauf') }}

    {% if is_incremental() %}
    where betriebstag >= (
        select coalesce(max(betriebstag), date '1900-01-01') from {{ this }}
    )
    {% endif %}

),

-- Was der Fremdverkehrsfilter aussortiert hat (BPULS-070). Diese Fahrten stehen in
-- keinem anderen Mart -- sie sind aus int_de_stop_events ausgeschlossen --, und genau
-- deshalb gehoeren sie hierher: ein Ausschluss, der nirgends auftaucht, ist von einem
-- Datenverlust nicht zu unterscheiden.
--
-- Nur die deutsche Quelle: die Kollision entsteht im gemeinsamen Nummernkreis des
-- gtfs.de-Feeds, die CH-Quelle kennt sie nicht.
aussortiert as (

    select
        betriebstag,
        'de_gtfsrt' as quelle,
        count(*)    as fahrten_gebietsfremd

    from {{ ref('int_de_gebietsfremd') }}
    where gebietsfremd

    {% if is_incremental() %}
    and betriebstag >= (
        select coalesce(max(betriebstag), date '1900-01-01') from {{ this }}
    )
    {% endif %}

    group by 1, 2

),

gezaehlt as (

    select
        betriebstag,
        quelle,

        count(distinct trip_key) as fahrten,
        count(*)                 as halte,

        -- Nenner: nur Halte, fuer die der Fahrplan das Ereignis ueberhaupt vorsieht.
        count(*) filter (where soll_an is not null) as halte_mit_soll_an,
        count(*) filter (where soll_ab is not null) as halte_mit_soll_ab,

        -- Zaehler: count(spalte) zaehlt NULL nicht mit, und NULL heisst in allen
        -- Marts "nicht bestimmbar" (CLAUDE.md Regel 8).
        count(delay_an_sek) as delay_an_messwerte,
        count(delay_ab_sek) as delay_ab_messwerte,

        -- Die Gruende, aufgeschluesselt statt summiert. Sie ueberschneiden sich
        -- bewusst: ein ausgefallener Zug kann zugleich in der Umstellungsstunde
        -- liegen. Wer sie addiert, zaehlt doppelt -- deshalb stehen sie nebeneinander
        -- und werden nie zu einer Kennzahl verrechnet.
        count(*) filter (where zug_ausgefallen)           as ausgefallene_halte,
        count(*) filter (where halt_ausgelassen)          as ausgelassene_halte,
        count(*) filter (where zeitumstellung_mehrdeutig) as halte_zeitumstellung,

        -- Der Rest: Halt planmaessig da, nicht ausgefallen, nicht ausgelassen, nicht
        -- mehrdeutig -- und trotzdem kein Wert. Das ist die eigentlich interessante
        -- Zahl, denn hier fehlt die Ist-Meldung selbst (CH: Prognosestatus != REAL).
        count(*) filter (
            where soll_an is not null
              and delay_an_sek is null
              and not zug_ausgefallen
              and not halt_ausgelassen
              and not zeitumstellung_mehrdeutig
        ) as halte_ohne_ist_an,
        count(*) filter (
            where soll_ab is not null
              and delay_ab_sek is null
              and not zug_ausgefallen
              and not halt_ausgelassen
              and not zeitumstellung_mehrdeutig
        ) as halte_ohne_ist_ab,

        -- Lueckenhafte Laufwege: fehlt zwischen zwei Halten einer, beschreibt
        -- "von -> nach" keine gefahrene Strecke. halt_nr = 1 hat planmaessig keinen
        -- Vorhalt und zaehlt deshalb nicht als Luecke.
        count(*) filter (where halt_nr > 1 and not abschnitt_direkt) as abschnitte_mit_luecke,

        -- Wie viele Halte ueberhaupt einen Namen tragen. Mit einer einzigen
        -- Fahrplan-Version waren es am 2026-08-20 nur **31,4 %**: der Echtzeit-Feed
        -- referenziert mehrere stop_id-Namensraeume gleichzeitig, ein Datensatz deckt
        -- nur einen Teil ab (Q6). Die Quote muss mit jeder woechentlichen Version
        -- steigen -- diese Spalte ist der Kanal, an dem sich das ablesen laesst, statt
        -- es zu hoffen.
        count(stop_name) as halte_mit_name,

        -- Halte ausserhalb VRN + RMV (BPULS-075). Sie stehen weiter in mart_zuglauf --
        -- der Laufweg eines Fernzuges soll lueckenlos lesbar bleiben --, gehen aber in
        -- keine Kennzahl ein. Ein Ausschluss, der nirgends auftaucht, ist von einem
        -- Datenverlust nicht zu unterscheiden; das ist derselbe Grund, aus dem
        -- fahrten_gebietsfremd danebensteht.
        count(*) filter (where not halt_im_gebiet) as halte_gebietsfremd,

        -- Nicht endgueltige Werte sind noch in Bewegung: eine Aussage ueber heute
        -- steht auf anderem Grund als eine ueber vorgestern.
        count(*) filter (where not ist_endgueltig) as halte_nicht_endgueltig

    from zuglauf
    group by all

)

select
    gezaehlt.*,

    -- coalesce, nicht NULL: an einem Tag ohne Fremdverkehr ist die richtige Antwort
    -- "keine", nicht "unbekannt". Fehlt dagegen die Nahverkehrs-Halteliste ganz, steht
    -- hier ebenfalls 0 -- das ist derselbe Blindfleck wie bei der Ausfall-Null aus
    -- BPULS-064, und er wird an seiner Stelle gemeldet: stg_de_nahverkehrshalt warnt
    -- im Lauf, wenn die Liste fehlt.
    coalesce(aussortiert.fahrten_gebietsfremd, 0) as fahrten_gebietsfremd,

    -- Der Tag mit bekannt unvollstaendiger Erhebung bleibt hier stehen -- und zwar
    -- gerade hier (BPULS-079). Aus den Aggregaten ist er ausgeschlossen; faellt er
    -- auch aus dem Abdeckungsprotokoll, ist eine Schieflage in der Erhebung von einem
    -- stillstehenden Collector nicht mehr zu unterscheiden. Das ist derselbe Grund,
    -- aus dem fahrten_gebietsfremd und halte_gebietsfremd danebenstehen.
    luecke.betriebstag is null as erhebung_vollstaendig,
    luecke.grund               as erhebung_grund,
    luecke.referenz            as erhebung_referenz,

    -- Die Abdeckungsquote, um die es geht. Nenner sind ausschliesslich die
    -- planmaessig vorhandenen Ereignisse -- sonst driftet die Quote mit dem Anteil
    -- der Start- und Endbahnhoefe, also mit der Laenge der Laufwege.
    delay_an_messwerte / nullif(halte_mit_soll_an, 0)::double as abdeckung_an,
    delay_ab_messwerte / nullif(halte_mit_soll_ab, 0)::double as abdeckung_ab,
    halte_mit_name     / nullif(halte, 0)::double            as namensquote

from gezaehlt
left join aussortiert
  on  aussortiert.betriebstag = gezaehlt.betriebstag
  and aussortiert.quelle      = gezaehlt.quelle
left join {{ ref('int_erhebungsluecke') }} as luecke
  on  luecke.betriebstag = gezaehlt.betriebstag
