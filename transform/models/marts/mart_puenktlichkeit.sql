{{ config(
    materialized='incremental',
    incremental_strategy='delete+insert',
    unique_key='betriebstag'
) }}

-- A5 (BPULS-032): Puenktlichkeit **und** das, was aus Puenktlichkeitsquoten
-- herausfaellt, in einer Tabelle. Ein ausgefallener Zug ist nie verspaetet -- eine Quote,
-- die Ausfaelle nicht danebenstellt, wird durch jede Streichung rechnerisch besser
-- (CLAUDE.md Regel 8, Bahnpuls_Analysen.md A5).
--
-- Korn: ein Betriebstag x eine Quelle x eine Linie x eine **Schwelle**.
--
-- Quelle ist mart_zuglauf, nicht int_segment_delta -- dieselbe Begruendung wie bei den
-- anderen Aggregaten: die Entwertungsregeln duerfen nur einmal existieren.
--
-- **Warum eine Kurve und nicht eine Zahl.** Die branchenuebliche Grenze liegt bei unter
-- sechs Minuten. Als einzige Zahl verdeckt sie genau die Faelle, um die es Reisenden
-- geht: 5:59 ist puenktlich, der Vier-Minuten-Anschluss ist trotzdem weg. Deshalb 1, 3,
-- 6, 15 und 60 Minuten nebeneinander.
--
-- **Zwei Nenner, bewusst beide.** `halte_gemessen` ist der uebliche: nur Halte, fuer die
-- eine Ankunftsverspaetung vorliegt. `halte_mit_ankunft` ist der ehrliche: alle Halte,
-- an denen planmaessig ein Zug ankommen sollte -- einschliesslich der ausgefallenen,
-- ausgelassenen und der ohne Meldung. Die Differenz zwischen beiden Quoten ist der
-- eigentliche Befund dieser Analyse.
--
-- **Die Zustaende schliessen einander aus** -- anders als in mart_datenqualitaet, wo die
-- Gruende einzeln gefuehrt und nie addiert werden. Hier ist die Zuordnung eindeutig,
-- weil sie einer festen Rangfolge folgt:
--
--     ausgefallen > unbedienter_lauf > verkuerzt > ausgelassen > mehrdeutig
--       > ohne_meldung > gemessen
--
-- Ein Zug, der ausfaellt *und* in der Umstellungsstunde liegt, zaehlt als ausgefallen.
-- Die sieben Zustaende ergeben zusammen exakt `halte_mit_ankunft`; ein Test prueft das.
--
-- **Warum `unbedienter_lauf` neben `ausgefallen` steht und nicht darin** (BPULS-064):
-- `zug_ausgefallen` heisst "die Quelle sagt, der Zug faellt aus". Dass in einem Lauf
-- kein einziger Halt bedient wurde, ist dagegen eine **Beobachtung an den Daten** --
-- ein starkes Indiz fuer einen Ausfall, aber kein Bericht darueber. Beides in eine
-- Spalte zu legen machte aus einer Messung eine Vermutung, ohne dass man es der
-- Spalte ansieht. Die Trennung kostet eine Spalte und erhaelt dafuer die Aussage:
-- gemeldet gegen abgeleitet, nebeneinander lesbar.
--
-- **Ueber Schwellen hinweg wird nie summiert.** Jede Zeile ist eine eigene Auswertung
-- derselben Grundmenge, die zaehlbaren Spalten wiederholen sich deshalb fuenfmal. Wer
-- sie ueber `schwelle_sek` aufaddiert, zaehlt jeden Halt fuenffach. Ein Test sichert ab,
-- dass diese Spalten innerhalb einer Gruppe tatsaechlich konstant sind.
--
-- **Was diese Zahlen nicht koennen** (gehoert auf die Methodik-Seite, nicht in eine
-- Fussnote): Der Nenner ist der **beobachtete** Laufweg, nicht der Fahrplan. Ein Halt,
-- den der Feed nie erwaehnt hat, fehlt auch hier -- ein vollstaendig ausgefallener Zug
-- ohne `stop_time_update` taucht gar nicht auf (BPULS-030, benannte Luecke). Die Quote
-- ist damit eine **obere Schranke**: sie kann nur besser aussehen als die Wirklichkeit,
-- nie schlechter. Zu schliessen ist das erst mit den Soll-Halten aus stop_times.txt,
-- die der Static-Loader heute bewusst nicht auspackt.
--
-- **halte_ausgefallen ist fuer die deutsche Quelle strukturell 0** -- und die Ursache
-- ist eine andere, als hier bis zum 2026-08-21 stand. GTFS-RT laesst zwei Formen zu:
-- eine Markierung an der ganzen Fahrt (trip.schedule_relationship = CANCELED) oder das
-- Streichen jedes einzelnen Halts (SKIPPED). zug_ausgefallen liest die erste; **dieser
-- Feed benutzt sie nicht.** Auszaehlung des vollstaendigen bundesweiten Feeds am
-- 2026-08-21: 49.133 Fahrten, davon **0 mit CANCELED** -- dagegen 12.747 gestrichene
-- Halte und 582 Fahrten (1,2 %), bei denen *jeder* Halt gestrichen war. Unabhaengig
-- bestaetigt durch drei Betriebstage Produktionsdaten (0 von 54.236 Fahrten).
--
-- **Folge fuer die Lesart:** diese Zuege fehlen **nicht** im Nenner. Sie landen als
-- halte_ausgelassen bzw. halte_verkuerzt und gehen in quote_planmaessig ein; es fehlt
-- allein das Etikett. Die frueher hier behauptete Aussage "beide Quoten sind zu guenstig,
-- die Ausfaelle fehlen im Nenner" war damit falsch.
--
-- Die Aufloesung ueber den Soll-Fahrplan (int_de_ausfaelle, BPULS-032) ist deshalb fuer
-- diesen Feed wirkungslos, nicht fehlerhaft: sie wartet auf eine Meldungsform, die nicht
-- kommt. Ob "alle Halte gestrichen" als Ausfall gewertet werden soll, ist eine fachliche
-- Entscheidung und steht als BPULS-064 offen.

{% set schwellen_sek = [60, 180, 360, 900, 3600] %}

with zuglauf as (

    select *
    from {{ ref('mart_zuglauf') }}

    {% if is_incremental() %}
    where betriebstag >= (
        select coalesce(max(betriebstag), date '1900-01-01') from {{ this }}
    )
    {% endif %}

),

laufweg as (

    -- Position des Halts im **beobachteten** Lauf. Nicht 1 und n: bei den deutschen
    -- Echtzeitdaten ist halt_nr die Fahrplannummer, und ein Zug, der beim
    -- Beobachtungsbeginn schon unterwegs war, taucht erst spaeter darin auf.
    select
        *,
        min(halt_nr) over (partition by trip_key) as erster_halt_nr,
        min(case when not halt_ausgelassen then halt_nr end)
            over (partition by trip_key)          as erster_bedienter,
        max(case when not halt_ausgelassen then halt_nr end)
            over (partition by trip_key)          as letzter_bedienter

    from zuglauf

),

eingeordnet as (

    select
        betriebstag,
        quelle,
        route_kurzname,
        trip_key,
        delay_an_sek,
        zug_ausgefallen,

        -- Am ersten Halt eines Laufs kommt planmaessig nichts an. Ihn mitzuzaehlen
        -- hiesse, eine Datenluecke zu messen, wo der Fahrplan nichts vorsieht
        -- (BPULS-015) -- und die Quote saenke allein dadurch, dass ein Tag mehr kurze
        -- Laeufe enthaelt.
        halt_nr > erster_halt_nr as hat_planmaessige_ankunft,

        case
            when zug_ausgefallen then 'ausgefallen'

            -- Kein einziger Halt des Laufs wurde bedient. In diesem Feed ist das die
            -- Form, in der ein vollstaendiger Ausfall ankommt: gemessen am
            -- 2026-08-21 setzt er `trip.schedule_relationship = CANCELED` nie
            -- (49.133 Fahrten, 0 Treffer), streicht dafuer aber die Halte einzeln.
            --
            -- Steht **vor** 'verkuerzt', weil "verkuerzt" einen Zug meint, der faehrt:
            -- ohne bedienten Halt gibt es keinen Rand, der gekappt sein koennte.
            --
            -- **Was diese Spalte nicht behauptet:** dass der Zug nicht fuhr. Sie sagt,
            -- dass im **beobachteten** Lauf kein Halt bedient wurde. Wurde eine Fahrt
            -- erst ab der Mitte beobachtet und war der Rest gestrichen, sieht eine
            -- gekappte Fahrt genauso aus. Zu trennen waere das ueber den Soll-Laufweg
            -- (stg_de_fahrplanhalt); bis dahin ist die Grenze benannt statt
            -- stillschweigend eingerechnet.
            when erster_bedienter is null then 'unbedienter_lauf'

            -- Ausgelassen am Anfang oder am Ende des Laufs heisst: der Zug faehrt, aber
            -- verkuerzt. Das ist ein anderer Vorgang als ein uebersprungener Halt
            -- mitten im Lauf, und fuer Reisende an den betroffenen Bahnhoefen ein
            -- vollstaendiger Ausfall.
            when halt_ausgelassen
                 and (halt_nr < erster_bedienter or halt_nr > letzter_bedienter)
                then 'verkuerzt'

            when halt_ausgelassen          then 'ausgelassen'
            when zeitumstellung_mehrdeutig then 'mehrdeutig'
            when delay_an_sek is null      then 'ohne_meldung'
            else 'gemessen'
        end as zustand

    from laufweg

),

-- Die Fahrtzustaende einmal je Fahrt, damit sie beim Zaehlen nicht an der Zahl der
-- Halte haengen: ein verkuerzter Lauf mit acht ausgelassenen Halten ist eine
-- verkuerzte Fahrt, nicht acht.
fahrtzustand as (

    select
        betriebstag,
        quelle,
        route_kurzname,
        trip_key,
        bool_or(zug_ausgefallen)                as fahrt_ausgefallen,
        bool_or(zustand = 'unbedienter_lauf')   as fahrt_unbedienter_lauf,
        bool_or(zustand = 'verkuerzt')          as fahrt_verkuerzt
    from eingeordnet
    group by 1, 2, 3, 4

),

schwellen as (

    select unnest([{{ schwellen_sek | join(', ') }}]) as schwelle_sek

),

gezaehlt as (

    select
        eingeordnet.betriebstag,
        eingeordnet.quelle,
        eingeordnet.route_kurzname,
        schwellen.schwelle_sek,

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

        -- Puenktlich heisst: weniger als die Schwelle zu spaet. Zu frueh ist puenktlich;
        -- das ist Absicht -- ein Zug vor der Zeit ist kein Puenktlichkeitsproblem,
        -- sondern gehoert nach A2 in den Pufferabbau.
        count(*) filter (
            where hat_planmaessige_ankunft
              and zustand = 'gemessen'
              and delay_an_sek < schwellen.schwelle_sek
        ) as halte_puenktlich

    from eingeordnet
    cross join schwellen
    group by 1, 2, 3, 4

)

select
    gezaehlt.betriebstag,
    gezaehlt.quelle,
    gezaehlt.route_kurzname,
    gezaehlt.schwelle_sek,

    fahrten.fahrten,
    fahrten.fahrten_ausgefallen,
    fahrten.fahrten_unbedienter_lauf,
    fahrten.fahrten_verkuerzt,

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
    -- Sie kann nie ueber der oberen liegen, und die Luecke zwischen beiden ist genau
    -- das, was uebliche Statistiken weglassen.
    case when gezaehlt.halte_mit_ankunft > 0
         then gezaehlt.halte_puenktlich::double / gezaehlt.halte_mit_ankunft end
        as quote_planmaessig

from gezaehlt
join (
    select
        betriebstag,
        quelle,
        route_kurzname,
        count(*)                                       as fahrten,
        count(*) filter (where fahrt_ausgefallen)      as fahrten_ausgefallen,
        count(*) filter (where fahrt_unbedienter_lauf) as fahrten_unbedienter_lauf,
        count(*) filter (where fahrt_verkuerzt)        as fahrten_verkuerzt
    from fahrtzustand
    group by 1, 2, 3
) as fahrten
  on  fahrten.betriebstag = gezaehlt.betriebstag
  and fahrten.quelle      = gezaehlt.quelle
  and fahrten.route_kurzname is not distinct from gezaehlt.route_kurzname
