{{ config(materialized='table') }}

-- Verdichtet die GTFS-RT-Momentaufnahmen auf **ein Halt-Ereignis je Halt** und bringt
-- sie damit auf das fct_stop_events-Schema (BPULS-030).
--
-- Warum ein eigenes Modell und nicht direkt in stg_de_gtfsrt: das hier ist
-- Zustandslogik -- aus vielen Prognosen wird ein Ist -- und die gehoert nach CLAUDE.md
-- nicht in den Staging-Layer. Die CH-Quelle braucht diesen Schritt nicht, weil ihre
-- Zeile bereits ein Halt-Ereignis ist; deshalb haengt fct_stop_events fuer CH am
-- Staging-Modell und fuer DE hier.
--
-- Die Regel (Bahnpuls_Datenmodell.md): als Ist gilt der **zeitlich letzte** Wert, der
-- bis kurz nach dem Soll-Zeitpunkt gemeldet wurde. Die Karenz faengt ab, dass die
-- letzte Meldung leicht nach dem Ereignis eintrifft. Sie ist eine **Annahme**, steht
-- deshalb als Variable hier und auf der Methodik-Seite -- sie beeinflusst jede
-- nachgelagerte Kennzahl.

{% set karenz = var('de_ist_karenz_minuten', 5) %}

-- Plausibilitaetsfenster fuer Verspaetungswerte. Gemessen am 2026-08-20 ueber 3.986.272
-- Rohzeilen: die Maxima sind unauffaellig (+17.820 s Ankunft, +18.120 s Abfahrt -- fuenf
-- Stunden Verspaetung gibt es), die Minima nicht: **-19.611 s bei der Ankunft und
-- -83.050 s bei der Abfahrt**. Ein Zug, der 23 Stunden zu frueh ist, existiert nicht;
-- das sind Artefakte, vermutlich Fahrten mit einer Prognosezeit auf einem anderen
-- Betriebstag.
--
-- Sie werden **entwertet, nicht korrigiert** (CLAUDE.md Regel 8): ein unplausibler Wert
-- ist nicht bestimmbar, nicht "sehr puenktlich". Wuerde man ihn stehen lassen, zoege er
-- jeden Durchschnitt nach unten -- also in die schmeichelhafte Richtung, was bei einem
-- Projekt ueber Verspaetungen die schlechteste aller Fehlerrichtungen waere.
--
-- Mit entwertet wird die **Soll-Zeit**: sie ist aus Prognose minus Verspaetung
-- abgeleitet, ist die Verspaetung Muell, ist es die Soll-Zeit auch. Der Halt bleibt als
-- Zeile stehen und traegt NULL; mart_datenqualitaet zaehlt ihn damit unter den Halten
-- ohne Ist-Meldung, wo er hingehoert -- das ist ein Problem der Erhebung, keines des
-- Betriebs.

with snapshots as (

    select * from {{ ref('stg_de_gtfsrt') }}

),

-- Fahrten, die gar kein Bahnverkehr im Zielgebiet sind, sondern ueber eine
-- Nummernkollision in den Scope-Filter geraten sind (BPULS-070). Sie werden hier
-- ausgeschlossen und nicht entwertet: eine Hannoveraner Buslinie ist kein Halt ohne
-- Messwert, sie gehoert nicht in diesen Datensatz. Gezaehlt werden sie trotzdem --
-- mart_datenqualitaet weist sie aus, damit der Ausschluss sichtbar bleibt.
fremde_fahrten as (

    select betriebstag, trip_key
    from {{ ref('int_de_gebietsfremd') }}
    where gebietsfremd

),

-- Jeder Halt, der ueberhaupt je gemeldet wurde. Basis, damit auch Halte bestehen
-- bleiben, fuer die kein Wert die Regel erfuellt -- die Zeile bleibt stehen und traegt
-- NULL, statt aus dem Laufweg zu verschwinden (CLAUDE.md Regel 8, Fallstrick A1).
halte as (

    -- Der Schluessel eines Halts ist die Fahrplannummer `stop_sequence`; die stop_id
    -- ist eine Beschriftung daran. Der Feed nennt sie nicht in jeder Meldung und
    -- wechselt sie gelegentlich mitten in der Fahrt -- ein `select distinct` ueber
    -- beide Spalten machte daraus **zwei** Halte, und zwar lautlos: die zweite Zeile
    -- traegt dieselben Zeiten und sieht plausibel aus. Nachgelagert zaehlte jeder
    -- solche Halt doppelt (BPULS-065).
    --
    -- `arg_max` uebergeht NULL-Werte und liefert die zuletzt genannte stop_id -- nach
    -- derselben Regel, nach der weiter unten auch der Ist-Wert bestimmt wird.
    select
        betriebstag,
        trip_key,
        trip_id,
        stop_sequence,
        arg_max(stop_id, snapshot_ts) as stop_id,
        quelle

    from snapshots
    group by betriebstag, trip_key, trip_id, stop_sequence, quelle

),

-- Letzter Zustand je Halt, unabhaengig von der Karenz: ob ausgelassen oder ausgefallen
-- ist eine Aussage ueber den Halt, keine Prognose auf einen Zeitpunkt.
zustand as (

    select
        trip_key,
        stop_sequence,
        halt_ausgelassen,
        zug_ausgefallen,
        snapshot_ts as letzter_snapshot_ts

    from snapshots
    qualify row_number() over (
        partition by trip_key, stop_sequence order by snapshot_ts desc
    ) = 1

),

-- Soll getrennt von Ist: die Soll-Zeit ist eine Fahrplantatsache, keine Prognose auf
-- einen Zeitpunkt, und darf deshalb nicht an der Karenz haengen. Zoege man sie aus
-- demselben gefilterten Kandidaten, verloere ein Halt, dessen einziger Snapshot zu spaet
-- kam, auch seine Soll-Zeit -- er fiele aus dem Nenner von mart_datenqualitaet heraus,
-- und die verpasste Messung machte sich damit selbst unsichtbar.
soll as (

    select
        trip_key,
        stop_sequence,
        max(soll_an) filter (where {{ ist_plausible_verspaetung('delay_an_sek') }}) as soll_an,
        max(soll_ab) filter (where {{ ist_plausible_verspaetung('delay_ab_sek') }}) as soll_ab

    from snapshots
    group by trip_key, stop_sequence

),

ankunft as (

    select
        trip_key,
        stop_sequence,
        ist_an,
        delay_an_sek,
        snapshot_ts as an_snapshot_ts

    from snapshots
    -- Ohne Soll-Zeit ist die Regel nicht anwendbar: der Feed liefert keine, sie wird
    -- aus Prognose minus Verspaetung rekonstruiert, und fehlt eines von beiden, gibt
    -- es keinen Bezugspunkt. Dann bleibt der Wert nicht bestimmbar statt geraten.
    where soll_an is not null
      and {{ ist_plausible_verspaetung('delay_an_sek') }}
      and snapshot_ts <= soll_an + interval {{ karenz }} minute
    qualify row_number() over (
        partition by trip_key, stop_sequence order by snapshot_ts desc
    ) = 1

),

abfahrt as (

    select
        trip_key,
        stop_sequence,
        ist_ab,
        delay_ab_sek,
        snapshot_ts as ab_snapshot_ts

    from snapshots
    where soll_ab is not null
      and {{ ist_plausible_verspaetung('delay_ab_sek') }}
      and snapshot_ts <= soll_ab + interval {{ karenz }} minute
    qualify row_number() over (
        partition by trip_key, stop_sequence order by snapshot_ts desc
    ) = 1

),

-- Die beiden Wege in dieselbe Menge -- beobachtete Halte und aufgeloeste Ausfaelle --
-- stehen als CTE, damit die Gebietszugehoerigkeit **einmal** darauf entschieden wird
-- und nicht in jedem Zweig noch einmal.
ereignisse as (

    select
        halte.betriebstag,
        halte.trip_key,
        halte.stop_sequence::bigint as stop_sequence,
        halte.stop_id,

        -- Name aus den statischen Fahrplaenen, vereinigt ueber alle Versionen (BPULS-023).
        -- Bleibt NULL, wo keine Version den Halt kennt -- eine ID als Namen auszugeben waere
        -- eine Luege im Dashboard, dort steht dann bewusst die ID als solche.
        halte_name.bezeichnung as stop_name,

        soll.soll_an,
        soll.soll_ab,
        ankunft.ist_an,
        abfahrt.ist_ab,
        ankunft.delay_an_sek::bigint as delay_an_sek,
        abfahrt.delay_ab_sek::bigint as delay_ab_sek,

        -- Endgueltig ist ein Wert, wenn ueber den Stichtag hinaus beobachtet wurde: dann
        -- kann keine spaetere Meldung mehr kommen. Endet die Beobachtung vorher -- laufender
        -- Betriebstag, oder der Collector stand still --, ist der Wert noch in Bewegung.
        coalesce(
            zustand.letzter_snapshot_ts >= coalesce(soll.soll_ab, soll.soll_an)
                + interval {{ karenz }} minute,
            false
        ) as ist_endgueltig,

        coalesce(zustand.halt_ausgelassen, false) as halt_ausgelassen,
        coalesce(zustand.zug_ausgefallen, false)  as zug_ausgefallen,

        -- route_id ist im Echtzeitfeed zu 100 % leer (gemessen 2026-08-20 an 2.346 Fahrten
        -- im Scope), der Weg fuehrt deshalb ueber die trip_id in trips.txt. block_id liefert
        -- die Quelle gar nicht (BPULS-003).
        linien_name.bezeichnung as route_kurzname,
        cast(null as varchar) as block_id,

        halte.quelle

    from halte
    left join {{ ref('stg_de_static') }} as halte_name
      on  halte_name.art        = 'stop'
      and halte_name.schluessel = halte.stop_id
    left join {{ ref('stg_de_static') }} as linien_name
      on  linien_name.art        = 'linie'
      and linien_name.schluessel = halte.trip_id
    left join soll
      on  halte.trip_key      = soll.trip_key
      and halte.stop_sequence = soll.stop_sequence
    left join zustand
      on  halte.trip_key      = zustand.trip_key
      and halte.stop_sequence = zustand.stop_sequence
    left join ankunft
      on  halte.trip_key      = ankunft.trip_key
      and halte.stop_sequence = ankunft.stop_sequence
    left join abfahrt
      on  halte.trip_key      = abfahrt.trip_key
      and halte.stop_sequence = abfahrt.stop_sequence
    where not exists (
        select 1 from fremde_fahrten
        where fremde_fahrten.betriebstag = halte.betriebstag
          and fremde_fahrten.trip_key    = halte.trip_key
    )

    union all by name

    -- Dritter Weg in dieselbe Menge: vollstaendig ausgefallene Fahrten, die im Feed
    -- **ohne** Halte gemeldet werden und deshalb weiter oben gar nicht vorkommen
    -- koennen. Sie werden in int_de_ausfaelle aus dem Soll-Fahrplan aufgeloest
    -- (BPULS-032).
    --
    -- Der union steht hier und nicht in fct_stop_events: die Nahtstelle traegt einen
    -- Zweig je **Quelle**, nicht je Meldungsform. Fuer Downstream ist ein aufgeloester
    -- Ausfall ein Halt-Ereignis wie jedes andere -- mit NULL-Verspaetungen und
    -- zug_ausgefallen = true.
    --
    -- Dubletten sind ausgeschlossen: int_de_ausfaelle nimmt nur Fahrten, zu denen es
    -- **keine** beobachteten Halte gibt.
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

    from {{ ref('int_de_ausfaelle') }} as ausfaelle
    where not exists (
        select 1 from fremde_fahrten
        where fremde_fahrten.betriebstag = ausfaelle.betriebstag
          and fremde_fahrten.trip_key    = ausfaelle.trip_key
    )

),

-- Liegt der Halt in VRN + RMV (BPULS-075)? Zwei Schluessel, weil die stop_id zwischen
-- Fahrplanversionen rotiert und der Name das stabilere Merkmal ist -- die Begruendung
-- steht in stg_de_gebietshalt.
--
-- **Entwertet, nicht gefiltert** (CLAUDE.md Regel 8, Fallstrick A1): faellt ein Halt aus
-- der Reihenfolge heraus, spannt das lag() in int_segment_delta den Abschnitt darueber
-- hinweg und weist zwei nicht benachbarte Betriebsstellen als direkte Fahrt aus -- still
-- und plausibel aussehend. Der Halt bleibt deshalb stehen und traegt eine
-- Kennzeichnung; die Aggregate rechnen mit ihr, das Abdeckungsprotokoll zaehlt sie.
--
-- Ein Halt ohne bekannten Namen und mit unbekannter ID gilt als **nicht im Gebiet**.
-- Das ist die Gegenrichtung zu int_de_gebietsfremd ("nicht pruefbar ist nicht
-- widerlegt") und hier bewusst so: dort geht es darum, eine ganze Fahrt zu verwerfen,
-- hier darum, einen einzelnen Halt in eine Gebietskennzahl einzurechnen. Bei einer
-- Namensquote von 99,4 % betrifft das unter einem Prozent der Halte, und
-- mart_datenqualitaet weist sie aus.
gebiet_id as (

    select distinct stop_id from {{ ref('stg_de_gebietshalt') }}

),

gebiet_name as (

    select distinct stop_name from {{ ref('stg_de_gebietshalt') }}

)

select
    ereignisse.*,
    gebiet_id.stop_id is not null or gebiet_name.stop_name is not null as halt_im_gebiet

from ereignisse
left join gebiet_id
  on gebiet_id.stop_id = ereignisse.stop_id
left join gebiet_name
  on gebiet_name.stop_name = ereignisse.stop_name
