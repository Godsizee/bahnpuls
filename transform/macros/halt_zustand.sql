{#
    Die Zustandslogik eines Halts -- einmal, fuer jedes Aggregat, das sie braucht.

    Zwei Makros, weil sie in zwei aufeinander folgende CTEs gehoeren: erst die
    Fensterfunktionen ueber den Lauf, dann die Einordnung, die auf ihr Ergebnis
    zugreift.

        {{ laufwegfenster() }}   -- in einem select ueber mart_zuglauf
        {{ halt_zustand() }}     -- in einem select ueber dessen Ergebnis

    **Warum als Makro und nicht als intermediate-Modell:** die Quelle ist mart_zuglauf,
    weil die Entwertungsregeln genau einmal existieren duerfen. Ein intermediate-Modell
    auf einem Mart drehte die Schichtrichtung um; ein zweites Mal ausgeschriebene
    Rangfolge liefe irgendwann auseinander, ohne dass ein Test es merkt. Beides ist
    schlechter als ein Makro, das den Wortlaut haelt.

    Benutzt von mart_puenktlichkeit (je Linie) und mart_bahnhof (je Bahnhof). Beide
    zaehlen dieselben sieben Zustaende; sie unterscheiden sich nur in der Gruppierung.
#}

{% macro laufwegfenster() -%}
    -- Position des Halts im **beobachteten** Lauf. Nicht 1 und n: bei den deutschen
    -- Echtzeitdaten ist halt_nr die Fahrplannummer, und ein Zug, der beim
    -- Beobachtungsbeginn schon unterwegs war, taucht erst spaeter darin auf.
    min(halt_nr) over (partition by trip_key) as erster_halt_nr,
    min(case when not halt_ausgelassen then halt_nr end)
        over (partition by trip_key)          as erster_bedienter,
    max(case when not halt_ausgelassen then halt_nr end)
        over (partition by trip_key)          as letzter_bedienter,

    -- Die Fensterfunktionen laufen bewusst ueber den **ganzen beobachteten Lauf**,
    -- auch ueber seine Halte ausserhalb von VRN + RMV. Erst danach wird auf das
    -- Gebiet eingeschraenkt (BPULS-075). Andersherum verlore der erste Gebietshalt
    -- eines einfahrenden Fernzuges seine planmaessige Ankunft -- und damit genau die
    -- Eingangsverspaetung, an der ein Zug, der die Verspaetung mitbringt, von einem
    -- zu unterscheiden ist, der sie im Gebiet aufsammelt.
    bool_or(halt_im_gebiet) over (partition by trip_key) as fahrt_im_gebiet
{%- endmacro %}

{% macro halt_zustand() -%}
    -- Am ersten Halt eines Laufs kommt planmaessig nichts an. Ihn mitzuzaehlen
    -- hiesse, eine Datenluecke zu messen, wo der Fahrplan nichts vorsieht
    -- (BPULS-015) -- und die Quote saenke allein dadurch, dass ein Tag mehr kurze
    -- Laeufe enthaelt.
    halt_nr > erster_halt_nr as hat_planmaessige_ankunft,

    -- Feste Rangfolge, die Zustaende schliessen einander aus:
    --
    --     ausgefallen > unbedienter_lauf > verkuerzt > ausgelassen > mehrdeutig
    --       > ohne_meldung > gemessen
    --
    -- Ein Zug, der ausfaellt *und* in der Umstellungsstunde liegt, zaehlt als
    -- ausgefallen. Die sieben ergeben zusammen exakt `halte_mit_ankunft`; in jedem
    -- Aggregat prueft das ein Test.
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
        -- **Was diese Einordnung nicht behauptet:** dass der Zug nicht fuhr. Sie sagt,
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
{%- endmacro %}
