---
title: Laufweg einer Fahrt
description: Der Verspätungsverlauf einer einzelnen Fahrt, zerlegt in Laufzeit- und Haltezeitanteil
---

Eine einzelne Fahrt, von Halt zu Halt nachgezeichnet. Statt einer Zahl am Ende — „zwölf
Minuten zu spät" — steht hier, an welcher Stelle diese Minuten dazugekommen sind, und ob
das unterwegs passierte oder während eines Aufenthalts.

**So liest man die Diagramme:** Das obere zeigt, was jeder einzelne Abschnitt und jeder
Halt beigetragen hat. Ein Balken nach oben heißt, dort ist Verspätung entstanden; ein
Balken nach unten heißt, dort wurde welche aufgeholt. Die Farbe sagt, ob es unterwegs
passierte oder im Bahnhof. Das untere Diagramm zeigt denselben Zug noch einmal anders: wie
viel Verspätung er zu jedem Zeitpunkt insgesamt mit sich trug.

<Alert status=info>

**Zur Auswahl steht nur ein Ausschnitt.** Diese Seite bietet eine Stichprobe von bis zu
150 Fahrten des zuletzt aufgezeichneten Tages an, nicht alle. Das liegt an der Technik,
nicht an fehlenden Daten: Die Diagramme rechnen direkt im Browser, und ein vollständiger
Tag wären mehrere hundert Megabyte, die jeder Besucher erst herunterladen müsste. Die
Zahlen auf der Startseite beruhen dagegen auf allem, was aufgezeichnet wurde.

</Alert>

```sql fahrten
-- Der erste Halt einer Fahrt ist der mit der kleinsten Nummer, nicht die 1: bei den
-- deutschen Echtzeitdaten ist halt_nr die Fahrplannummer und beginnt bei 0 oder höher.
-- Und er ist nicht zwangsläufig der Startbahnhof — ein Zug, der beim Beginn der
-- Beobachtung schon unterwegs war, taucht erst ab seinem nächsten Halt auf.
with erster_halt as (
    select trip_key, min(halt_nr) as halt_nr
    from bahnpuls.mart_zuglauf
    group by trip_key
)
select
    z.trip_key,
    -- Linienname und Stationsname fehlen bei der deutschen Quelle, solange der
    -- Fahrplan-Datensatz nicht angeschlossen ist. Dann steht hier die ID statt eines
    -- Namens — sichtbar, aber nicht kaputt.
    coalesce(z.route_kurzname, z.quelle) || ' · '
        || strftime(z.betriebstag, '%d.%m.%Y') || ' · ab '
        || coalesce(z.stop_name, z.stop_id) as bezeichnung
from bahnpuls.mart_zuglauf z
join erster_halt e on z.trip_key = e.trip_key and z.halt_nr = e.halt_nr
order by z.betriebstag, bezeichnung
```

<Dropdown data={fahrten} name=fahrt value=trip_key label=bezeichnung title="Fahrt" />

```sql schritte
with halte as (

    select *
    from bahnpuls.mart_zuglauf
    where trip_key = '${inputs.fahrt.value}'

),

grenzen as (

    -- Erster und letzter gelieferter Halt dieser Fahrt. Nicht 1 und n: die Nummer ist
    -- bei den deutschen Daten die Fahrplannummer, nicht die Position.
    select min(halt_nr) as erster, max(halt_nr) as letzter from halte

),

zerlegt as (

    -- Startverspätung: der Stand, mit dem die Fahrt beginnt
    select
        halt_nr * 10                             as reihenfolge,
        'Start ' || coalesce(stop_name, stop_id) as schritt,
        'Startverspätung'                        as art,
        coalesce(delay_an_sek, delay_ab_sek)     as beitrag_sek,
        coalesce(delay_an_sek, delay_ab_sek)     as stand_sek,
        zeitumstellung_mehrdeutig,
        zug_ausgefallen,
        halt_ausgelassen
    from halte, grenzen
    where halt_nr = grenzen.erster

    union all

    -- Laufzeitanteil: was auf dem Abschnitt vom Vorhalt hierher entstand.
    -- Der Stand davor ergibt sich aus dem Mart, ohne zweites Fenster:
    -- delay_an − laufzeit_delta ist genau die Abfahrtsverspätung des Vorhalts.
    select
        halt_nr * 10 + 1,
        '→ ' || coalesce(stop_name, stop_id),
        'Unterwegs',
        laufzeit_delta_sek,
        delay_an_sek,
        zeitumstellung_mehrdeutig,
        zug_ausgefallen,
        halt_ausgelassen
    from halte, grenzen
    where halt_nr > grenzen.erster

    union all

    -- Haltezeitanteil: was während des Halts entstand. Nur wo der Fahrplan
    -- überhaupt Ankunft und Abfahrt vorsieht -- am Start- und am Endhalt fehlt eine
    -- der beiden planmäßig, und das ist kein fehlender Messwert.
    select
        halt_nr * 10 + 2,
        'Halt ' || coalesce(stop_name, stop_id),
        'Im Bahnhof',
        haltezeit_delta_sek,
        delay_ab_sek,
        zeitumstellung_mehrdeutig,
        zug_ausgefallen,
        halt_ausgelassen
    from halte
    where soll_an is not null
      and soll_ab is not null

)

select
    reihenfolge,
    schritt,
    art,
    beitrag_sek / 60.0 as beitrag_min,
    stand_sek   / 60.0 as stand_min,
    case
        when zug_ausgefallen             then 'Zug ausgefallen'
        when halt_ausgelassen            then 'Halt ausgelassen'
        when zeitumstellung_mehrdeutig   then 'Nacht der Zeitumstellung — nicht eindeutig'
        when beitrag_sek is null         then 'keine Meldung'
    end as hinweis
from zerlegt
order by reihenfolge
```

## Wo die Minuten dazugekommen sind

```sql beitraege_chart
select schritt, reihenfolge, art, beitrag_min
from ${schritte}
where beitrag_min is not null
order by reihenfolge
```

<BarChart
    data={beitraege_chart}
    x=schritt
    y=beitrag_min
    series=art
    sort=false
    yAxisTitle="Minuten"
    title="Nach oben: dort entstanden. Nach unten: dort aufgeholt."
/>

Ein Balken nach unten ist kein Fehler, sondern der Normalfall: In jedem Fahrplan steckt
Reserve — etwas mehr Fahrzeit zwischen zwei Bahnhöfen, etwas längerer Aufenthalt als
nötig. Ein verspäteter Zug holt damit auf. Genau dafür ist sie da.

Wo für einen Abschnitt kein Balken erscheint, fehlt die Angabe. Sie wird dann **nicht als
Null gezeichnet**, denn Null hieße „hier hat sich nichts verändert" — und das ist etwas
anderes als „wir wissen es nicht".

## Wie viel Verspätung der Zug jeweils hatte

```sql verlauf
select schritt, reihenfolge, stand_min
from ${schritte}
where stand_min is not null
order by reihenfolge
```

<LineChart
    data={verlauf}
    x=schritt
    y=stand_min
    sort=false
    yAxisTitle="Minuten"
    markers=true
/>

Diese Linie stammt aus den tatsächlich gemeldeten Werten, nicht aus dem Aufaddieren der
Balken darüber. Das ist Absicht: Beide Wege müssten dasselbe ergeben, und wo sie es nicht
tun, fehlt eine Meldung. Deshalb bricht die Linie dort ab, statt eine Zwischenzahl zu
erfinden, die plausibel aussieht.

## Halt für Halt zum Nachlesen

<DataTable data={schritte} rows=20>
    <Column id=schritt title="Wo" />
    <Column id=art title="Unterwegs oder im Bahnhof" />
    <Column id=beitrag_min title="Dort dazugekommen (Min.)" fmt='#,##0.0' />
    <Column id=stand_min title="Verspätung danach (Min.)" fmt='#,##0.0' />
    <Column id=hinweis title="Warum keine Zahl" />
</DataTable>
