{{ config(
    materialized='incremental',
    incremental_strategy='delete+insert',
    unique_key='betriebstag'
) }}

-- A5 je Bahnhof statt je Linie (BPULS-061): wie zuverlaessig war ein Zug an *diesem*
-- Bahnsteig. Korn: ein Betriebstag x eine Quelle x ein Bahnhof x eine **Schwelle**.
--
-- Warum ueberhaupt ein eigenes Aggregat: mart_puenktlichkeit gruppiert nach Linie, und
-- eine Linienquote beantwortet die Frage nicht, die jemand an seinen Bahnhof hat. Die
-- Einordnung eines Halts ist in beiden dieselbe -- sie steht im Makro `halt_zustand()`
-- und ist deshalb nicht zweimal formuliert. Was hier dazukommt, ist die Trennung, die
-- dieses Projekt ausmacht (A1): **mitgebrachte** Verspaetung neben der, die **hier**
-- entsteht.
--
-- Der Schluessel ist der **Name**, nicht die stop_id. Die IDs rotieren zwischen
-- Fahrplanversionen (BPULS-073/075), ein Bahnhof wechselt dadurch nicht die Identitaet.
-- Halte ohne Namen fallen heraus, statt unter ihrer Nummer zu erscheinen: eine Seite
-- ueber "8000105" beantwortet niemandem eine Frage. Wie viele das sind, steht als
-- `namensquote` in mart_datenqualitaet (zuletzt 99,8 %).
--
-- **Ein Bahnhof ist hier, was der Feed einen Halt nennt.** `Frankfurt(Main)Hbf` und
-- `Frankfurt Hbf (tief)` sind zwei Zeilen, weil sie im Fahrplan zwei Betriebsstellen
-- sind -- oben Fern- und Regionalbahn, unten die S-Bahn. Sie zusammenzufassen waere
-- eine Entscheidung ueber Bahnsteige, die die Daten nicht hergeben.
--
-- **`ist_knoten` kommt aus der Konfiguration, nicht aus den Daten** (seed `knoten`).
-- Vorgerenderte Bahnhofsseiten gibt es nur fuer diese Auswahl: bei rund 830 benannten
-- Betriebsstellen (gemessen am 2026-08-24) ist eine Seite je Halt nicht tragbar, bei den Knoten, die jemand
-- nachschlaegt, sehr wohl. Eine datengetriebene Bestenliste waere die schlechtere Wahl
-- gewesen -- sie bestuende heute zu zwei Dritteln aus der Frankfurter Stammstrecke, und
-- ein zitierter Link liefe ins Leere, sobald ein Bahnhof aus ihr faellt (BPULS-077).
--
-- **Ueber Schwellen hinweg wird nie summiert** -- wie in mart_puenktlichkeit ist jede
-- Zeile eine eigene Auswertung derselben Grundmenge. Wer die zaehlbaren Spalten ueber
-- `schwelle_sek` aufaddiert, zaehlt jeden Halt fuenffach.
--
-- **Was diese Zahlen nicht koennen:** der Nenner ist der **beobachtete** Laufweg, nicht
-- der Fahrplan (BPULS-030). Ein Zug, von dem der Feed nie einen Halt gemeldet hat,
-- fehlt auch hier -- die Quote ist damit eine obere Schranke. Dieselbe Grenze wie bei
-- mart_puenktlichkeit, und sie steht auf der Methodik-Seite.

{% set schwellen_sek = [60, 180, 360, 900, 3600] %}

with zuglauf as (

    select *
    from {{ ref('mart_zuglauf') }}
    -- Keine Betriebstage mit bekannt unvollstaendiger Erhebung (BPULS-079). Eine
    -- Bahnhofsseite traefe es besonders hart: was am 22./23.08.2026 durchkam, kam ueber
    -- die wenigen grossen Knoten, die die Rotation ueberlebt haben.
    where erhebung_vollstaendig

    {% if is_incremental() %}
    and betriebstag >= (
        select coalesce(max(betriebstag), date '1900-01-01') from {{ this }}
    )
    {% endif %}

),

laufweg as (

    select
        *,
        {{ laufwegfenster() }}

    from zuglauf

),

eingeordnet as (

    select
        betriebstag,
        quelle,
        stop_name,
        trip_key,
        delay_an_sek,
        laufzeit_delta_sek,
        haltezeit_delta_sek,
        abschnitt_direkt,
        abschnitt_im_gebiet,
        halt_im_gebiet,
        fahrt_im_gebiet,

        {{ halt_zustand() }}

    from laufweg

),

schwellen as (

    select unnest([{{ schwellen_sek | join(', ') }}]) as schwelle_sek

),

gezaehlt as (

    select
        eingeordnet.betriebstag,
        eingeordnet.quelle,
        eingeordnet.stop_name as bahnhof,
        schwellen.schwelle_sek,

        count(distinct eingeordnet.trip_key) as zuege,

        count(*) filter (where hat_planmaessige_ankunft) as halte_mit_ankunft,

        count(*) filter (where hat_planmaessige_ankunft and zustand = 'ausgefallen')
            as halte_ausgefallen,
        count(*) filter (where hat_planmaessige_ankunft and zustand = 'unbedienter_lauf')
            as halte_unbedienter_lauf,
        count(*) filter (where hat_planmaessige_ankunft and zustand = 'verkuerzt')
            as halte_verkuerzt,
        count(*) filter (where hat_planmaessige_ankunft and zustand = 'ausgelassen')
            as halte_ausgelassen,
        count(*) filter (where hat_planmaessige_ankunft and zustand = 'mehrdeutig')
            as halte_mehrdeutig,
        count(*) filter (where hat_planmaessige_ankunft and zustand = 'ohne_meldung')
            as halte_ohne_meldung,
        count(*) filter (where hat_planmaessige_ankunft and zustand = 'gemessen')
            as halte_gemessen,

        -- Puenktlich heisst: weniger als die Schwelle zu spaet. Zu frueh ist puenktlich
        -- -- ein Zug vor der Zeit ist kein Puenktlichkeitsproblem, sondern gehoert nach
        -- A2 in den Pufferabbau.
        count(*) filter (
            where hat_planmaessige_ankunft
              and zustand = 'gemessen'
              and delay_an_sek < schwellen.schwelle_sek
        ) as halte_puenktlich,

        -- **Mitgebracht.** Der Verspaetungsstand bei der Ankunft, ueber die Halte, an
        -- denen er gemessen wurde. Summe und Zaehler getrennt, damit ueber mehrere Tage
        -- neu gerechnet werden kann, statt Mittelwerte zu mitteln.
        sum(delay_an_sek) filter (
            where hat_planmaessige_ankunft and zustand = 'gemessen'
        ) as verspaetung_an_sek_summe,
        count(*) filter (
            where hat_planmaessige_ankunft and zustand = 'gemessen'
        ) as verspaetung_an_messwerte,

        -- **Hier entstanden.** Die Differenz zwischen Ankunfts- und Abfahrtsverspaetung
        -- an genau diesem Halt (A1). Das ist die Zahl, die eine Bahnhofsseite von einer
        -- Puenktlichkeitstabelle unterscheidet.
        -- Ohne den ersten Halt eines Laufs: die Bereitstellungszeit im Ausgangsbahnhof
        -- ist eine andere Groesse als der Aufenthalt an einem Zwischenhalt und gehoert
        -- nicht in dieselbe Kennzahl -- dieselbe Grenze zieht mart_verspaetungsentstehung.
        sum(haltezeit_delta_sek) filter (where hat_planmaessige_ankunft)
            as haltezeit_delta_sek_summe,
        count(haltezeit_delta_sek) filter (where hat_planmaessige_ankunft)
            as haltezeit_messwerte,

        -- **Auf dem Weg hierher entstanden.** Gehoert dem Abschnitt davor, nicht dem
        -- Bahnhof -- steht hier, weil erst beide Zahlen nebeneinander die Frage
        -- beantworten, ob ein Zug den Rueckstand mitbringt oder hier aufsammelt. Nur
        -- lueckenlose Abschnitte im Gebiet: ohne Vorhalt beschreibt der Wert keine
        -- gefahrene Strecke (dieselbe Bedingung wie in mart_verspaetungsentstehung).
        sum(laufzeit_delta_sek) filter (
            where abschnitt_direkt and abschnitt_im_gebiet
        ) as laufzeit_delta_sek_summe,
        count(laufzeit_delta_sek) filter (
            where abschnitt_direkt and abschnitt_im_gebiet
        ) as laufzeit_messwerte

    from eingeordnet
    cross join schwellen
    -- Nur Halte im Zielgebiet (BPULS-075) und nur benannte: siehe Kopf.
    where eingeordnet.halt_im_gebiet
      and eingeordnet.fahrt_im_gebiet
      and eingeordnet.stop_name is not null
    group by 1, 2, 3, 4

)

select
    gezaehlt.betriebstag,
    gezaehlt.quelle,
    gezaehlt.bahnhof,
    gezaehlt.schwelle_sek,

    knoten.bahnhof is not null as ist_knoten,
    knoten.verbund,
    -- Die URL der Bahnhofsseite kommt aus der Konfiguration, nicht aus einer Ableitung
    -- des Namens: der Link wird zitiert (BPULS-077), und eine Ableitung aenderte ihn
    -- stillschweigend mit, sobald jemand die Umlautregel anfasst.
    knoten.slug,

    gezaehlt.zuege,
    gezaehlt.halte_mit_ankunft,
    gezaehlt.halte_ausgefallen,
    gezaehlt.halte_unbedienter_lauf,
    gezaehlt.halte_verkuerzt,
    gezaehlt.halte_ausgelassen,
    gezaehlt.halte_mehrdeutig,
    gezaehlt.halte_ohne_meldung,
    gezaehlt.halte_gemessen,
    gezaehlt.halte_puenktlich,

    -- Die uebliche Quote: gemessen an dem, was gemessen wurde.
    case when gezaehlt.halte_gemessen > 0
         then gezaehlt.halte_puenktlich::double / gezaehlt.halte_gemessen end
        as quote_gemessen,

    -- Die ehrliche Quote: gemessen an allem, wo planmaessig ein Zug ankommen sollte.
    -- Sie kann nie ueber der oberen liegen; die Luecke zwischen beiden ist das, was
    -- uebliche Statistiken weglassen.
    case when gezaehlt.halte_mit_ankunft > 0
         then gezaehlt.halte_puenktlich::double / gezaehlt.halte_mit_ankunft end
        as quote_planmaessig,

    gezaehlt.verspaetung_an_sek_summe,
    gezaehlt.verspaetung_an_messwerte,
    gezaehlt.haltezeit_delta_sek_summe,
    gezaehlt.haltezeit_messwerte,
    gezaehlt.laufzeit_delta_sek_summe,
    gezaehlt.laufzeit_messwerte,

    -- Je Halt normiert, nie als Rohsumme (CLAUDE.md, Coding-Prinzipien SQL): eine Summe
    -- setzt sonst den meistbefahrenen Bahnhof nach oben, egal wie gut er laeuft. Nur
    -- fuer die Ein-Tages-Sicht -- ueber mehrere Tage aus Summe und Zaehler neu rechnen,
    -- nicht diese Spalte mitteln.
    gezaehlt.verspaetung_an_sek_summe::double
        / nullif(gezaehlt.verspaetung_an_messwerte, 0)  as verspaetung_an_sek_je_halt,
    gezaehlt.haltezeit_delta_sek_summe::double
        / nullif(gezaehlt.haltezeit_messwerte, 0)       as haltezeit_delta_sek_je_halt,
    gezaehlt.laufzeit_delta_sek_summe::double
        / nullif(gezaehlt.laufzeit_messwerte, 0)        as laufzeit_delta_sek_je_halt

from gezaehlt
left join {{ ref('knoten') }} as knoten
  on knoten.bahnhof = gezaehlt.bahnhof
