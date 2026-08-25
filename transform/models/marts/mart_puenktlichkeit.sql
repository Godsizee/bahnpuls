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
-- Gruende einzeln gefuehrt und nie addiert werden. Sie kommen aus dem Makro
-- `halt_zustand()`, das auch mart_bahnhof benutzt: die Rangfolge und ihre Begruendung
-- stehen dort, damit die Einordnung eines Halts nicht zweimal formuliert ist. Die sieben
-- Zustaende ergeben zusammen exakt `halte_mit_ankunft`; ein Test prueft das.
--
-- **Woher `laufweg_vollstaendig` kommt.** Dieses Modell liest sonst ausschliesslich
-- mart_zuglauf -- die Entwertungsregeln liegen genau einmal, und das bleibt so. Die
-- Laufwegdeckung ist keine Entwertung, sondern eine Zusatztatsache ueber die Fahrt, und
-- sie steht in int_de_soll_laufweg, weil sie den statischen Fahrplan braucht (den ein
-- Mart nicht anfassen soll). Der join ist bewusst der einzige.
--
-- **Warum `unbedienter_lauf` neben `ausgefallen` steht und nicht darin** (BPULS-064):
-- `zug_ausgefallen` heisst "die Quelle sagt, der Zug faellt aus". Dass in einem Lauf
-- kein einziger Halt bedient wurde, ist dagegen eine **Beobachtung an den Daten** --
-- ein starkes Indiz fuer einen Ausfall, aber kein Bericht darueber. Beides in eine
-- Spalte zu legen machte aus einer Messung eine Vermutung, ohne dass man es der
-- Spalte ansieht. Die Trennung kostet eine Spalte und erhaelt dafuer die Aussage:
-- gemeldet gegen abgeleitet, nebeneinander lesbar.
--
-- `fahrten_unbedienter_lauf_bestaetigt` ist die Teilmenge davon, bei der der
-- **beobachtete Laufweg den planmaessigen vollstaendig deckt**. Nur dort ist
-- ausgeschlossen, dass wir bloss das gestrichene Ende einer sonst gefahrenen Fahrt
-- gesehen haben. Die Differenz zwischen beiden Spalten ist keine Ungenauigkeit, die man
-- wegrechnet -- sie ist die Reichweite der Beobachtung, und die gehoert ausgewiesen.
--
-- **Und diese Differenz zerfaellt in zwei Dinge, die nichts miteinander zu tun haben**
-- (BPULS-066): eine Fahrt, deren Laufweg der Fahrplan **widerlegt**, und eine, zu der
-- es gar keinen Fahrplan gibt. `fahrten_unbedienter_lauf_nicht_pruefbar` zaehlt die
-- zweite Gruppe. Gemessen am 2026-08-22 war sie die vollstaendige Erklaerung fuer den
-- Unterschied zwischen zwei Betriebstagen (84,4 % gegen 61,3 %), und sie besteht
-- ausschliesslich aus Fahrten ohne Liniennummer -- der Linienname kommt aus derselben
-- Quelle wie der Soll-Laufweg.
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
    -- Keine Betriebstage mit bekannt unvollstaendiger Erhebung (BPULS-079). Der Grund
    -- trifft ausgerechnet diese Kennzahl am haertesten: was am 22./23.08.2026 durchkam,
    -- war ueberproportional Fernverkehr ueber grosse Knoten -- eine Quote darueber
    -- beschreibt diesen Rest und nicht das Gebiet. Der Tag bleibt in mart_zuglauf und
    -- in mart_datenqualitaet sichtbar, er geht nur in keine Quote ein.
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
        route_kurzname,
        -- Reisen ab hier ueberall mit, obwohl sie funktional an route_kurzname haengen.
        -- Sie trotzdem in jedes group by zu nehmen ist Absicht (ADR-014): sollte eine
        -- trip_id doch einmal in zwei Feeds stehen, bricht der Grain-Test -- statt die
        -- Mehrdeutigkeit stillschweigend auf eine Zeile zu falten.
        verkehrsart,
        gattung,
        trip_key,
        delay_an_sek,
        zug_ausgefallen,
        halt_im_gebiet,
        fahrt_im_gebiet,

        {{ halt_zustand() }}

    from laufweg

),

-- Die Fahrtzustaende einmal je Fahrt, damit sie beim Zaehlen nicht an der Zahl der
-- Halte haengen: ein verkuerzter Lauf mit acht ausgelassenen Halten ist eine
-- verkuerzte Fahrt, nicht acht.
fahrtzustand as (

    select
        eingeordnet.betriebstag,
        eingeordnet.quelle,
        eingeordnet.route_kurzname,
        eingeordnet.verkehrsart,
        eingeordnet.gattung,
        eingeordnet.trip_key,
        bool_or(eingeordnet.zug_ausgefallen)                as fahrt_ausgefallen,
        bool_or(eingeordnet.zustand = 'unbedienter_lauf')   as fahrt_unbedienter_lauf,
        bool_or(eingeordnet.zustand = 'verkuerzt')          as fahrt_verkuerzt,

        -- Drei Faelle, nicht zwei (BPULS-066): belegt, widerlegt, und **nicht pruefbar**,
        -- weil die trip_id in keiner zum Betriebstag gueltigen Fahrplan-Version steht.
        -- Der dritte in den zweiten zu falten war die urspruengliche Festlegung und hat
        -- sich an den Daten als falsch erwiesen: er traf ausschliesslich Fahrten ohne
        -- Liniennummer -- dieselbe Ursache, dieselbe Gruppe --, und liess einen
        -- Blindfleck wie eine Beobachtung aussehen.
        coalesce(bool_or(soll_laufweg.laufweg_pruefbar), false)
            as fahrt_laufweg_pruefbar,
        coalesce(bool_or(soll_laufweg.laufweg_vollstaendig), false)
            as fahrt_laufweg_vollstaendig
    from eingeordnet
    left join {{ ref('int_de_soll_laufweg') }} as soll_laufweg
      on  soll_laufweg.betriebstag = eingeordnet.betriebstag
      and soll_laufweg.trip_key    = eingeordnet.trip_key
    -- Fahrten ohne einen einzigen Halt im Gebiet zaehlen hier nicht mit: sie sind ueber
    -- eine Nummernkollision oder als reiner Durchlaeufer hereingekommen (BPULS-075).
    where eingeordnet.fahrt_im_gebiet
    group by 1, 2, 3, 4, 5, 6

),

schwellen as (

    select unnest([{{ schwellen_sek | join(', ') }}]) as schwelle_sek

),

gezaehlt as (

    select
        eingeordnet.betriebstag,
        eingeordnet.quelle,
        eingeordnet.route_kurzname,
        eingeordnet.verkehrsart,
        eingeordnet.gattung,
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
    -- Gezaehlt wird nur, was in VRN + RMV liegt (BPULS-075). Die Halte davor und danach
    -- stehen weiter in mart_zuglauf -- sie gehoeren zum Laufweg, aber nicht in eine
    -- Puenktlichkeitsquote ueber dieses Gebiet.
    where eingeordnet.halt_im_gebiet
    group by 1, 2, 3, 4, 5, 6

)

select
    gezaehlt.betriebstag,
    gezaehlt.quelle,
    gezaehlt.route_kurzname,
    gezaehlt.verkehrsart,
    gezaehlt.gattung,
    gezaehlt.schwelle_sek,

    fahrten.fahrten,
    fahrten.fahrten_ausgefallen,
    fahrten.fahrten_unbedienter_lauf,
    fahrten.fahrten_unbedienter_lauf_bestaetigt,
    fahrten.fahrten_unbedienter_lauf_nicht_pruefbar,
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
        verkehrsart,
        gattung,
        count(*)                                       as fahrten,
        count(*) filter (where fahrt_ausgefallen)      as fahrten_ausgefallen,
        count(*) filter (where fahrt_unbedienter_lauf) as fahrten_unbedienter_lauf,
        count(*) filter (
            where fahrt_unbedienter_lauf and fahrt_laufweg_vollstaendig
        ) as fahrten_unbedienter_lauf_bestaetigt,
        count(*) filter (
            where fahrt_unbedienter_lauf and not fahrt_laufweg_pruefbar
        ) as fahrten_unbedienter_lauf_nicht_pruefbar,
        count(*) filter (where fahrt_verkuerzt)        as fahrten_verkuerzt
    from fahrtzustand
    group by 1, 2, 3, 4, 5
) as fahrten
  on  fahrten.betriebstag = gezaehlt.betriebstag
  and fahrten.quelle      = gezaehlt.quelle
  and fahrten.route_kurzname is not distinct from gezaehlt.route_kurzname
  -- `is not distinct from`, nicht `=`: beide Spalten sind fuer Fahrten ohne bekannten
  -- Fahrplan NULL, und ein Gleichheitsvergleich liesse genau die Gruppe aus dem Join
  -- fallen, die BPULS-091 als Zahl ausweisen soll.
  and fahrten.verkehrsart is not distinct from gezaehlt.verkehrsart
  and fahrten.gattung is not distinct from gezaehlt.gattung
