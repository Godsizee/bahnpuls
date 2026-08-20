---
title: Laufweg einer Fahrt
description: Der Verspätungsverlauf einer einzelnen Fahrt, zerlegt in Laufzeit- und Haltezeitanteil
---

Eine einzelne Fahrt, Halt für Halt: Wo kam Verspätung dazu, wo wurde welche abgebaut —
und ob das auf der Strecke oder im Bahnhof passierte. Die Rechenwege stehen auf der
[Methodik](/methodik).

```sql fahrten
-- halt_nr = 1 ist der Startbahnhof der Fahrt
select
    trip_key,
    route_kurzname || ' · ' || strftime(betriebstag, '%d.%m.%Y')
        || ' · ab ' || stop_name as bezeichnung
from bahnpuls.mart_zuglauf
where halt_nr = 1
order by betriebstag, route_kurzname, trip_key
```

<Dropdown data={fahrten} name=fahrt value=trip_key label=bezeichnung title="Fahrt" />

```sql schritte
with halte as (

    select *
    from bahnpuls.mart_zuglauf
    where trip_key = '${inputs.fahrt.value}'

),

zerlegt as (

    -- Startverspätung: der Stand, mit dem die Fahrt beginnt
    select
        halt_nr * 10                             as reihenfolge,
        'Start ' || stop_name                    as schritt,
        'Startverspätung'                        as art,
        coalesce(delay_an_sek, delay_ab_sek)     as beitrag_sek,
        coalesce(delay_an_sek, delay_ab_sek)     as stand_sek,
        zeitumstellung_mehrdeutig,
        zug_ausgefallen,
        halt_ausgelassen
    from halte
    where halt_nr = 1

    union all

    -- Laufzeitanteil: was auf dem Abschnitt vom Vorhalt hierher entstand.
    -- Der Stand davor ergibt sich aus dem Mart, ohne zweites Fenster:
    -- delay_an − laufzeit_delta ist genau die Abfahrtsverspätung des Vorhalts.
    select
        halt_nr * 10 + 1,
        '→ ' || stop_name,
        'Laufzeit (Strecke)',
        laufzeit_delta_sek,
        delay_an_sek,
        zeitumstellung_mehrdeutig,
        zug_ausgefallen,
        halt_ausgelassen
    from halte
    where halt_nr > 1

    union all

    -- Haltezeitanteil: was während des Halts entstand. Nur wo der Fahrplan
    -- überhaupt Ankunft und Abfahrt vorsieht -- am Start- und am Endhalt fehlt eine
    -- der beiden planmäßig, und das ist kein fehlender Messwert.
    select
        halt_nr * 10 + 2,
        'Halt ' || stop_name,
        'Haltezeit (Bahnhof)',
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
        when zeitumstellung_mehrdeutig   then 'Zeitumstellung — nicht bestimmbar'
        when beitrag_sek is null         then 'nicht bestimmbar'
    end as hinweis
from zerlegt
order by reihenfolge
```

## Beiträge je Abschnitt und Halt

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
    title="Positiv = neu entstanden, negativ = aufgeholt"
/>

Ein negativer Balken ist kein Fehler, sondern **Pufferabbau**: Fahrpläne enthalten
Fahrzeit- und Haltezeitreserve, und der Zug hat sie hier genutzt. Wo ein Beitrag fehlt,
war er nicht bestimmbar — er wird nicht als 0 dargestellt, sondern gar nicht.

## Verspätungsstand entlang des Laufwegs

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

Der Stand stammt jeweils aus der gemessenen Ankunfts- bzw. Abfahrtsverspätung, nicht aus
der Fortschreibung der Beiträge. Wo eine Meldung fehlt, bricht die Linie ab, statt eine
Zwischenzahl zu erfinden.

## Protokoll

<DataTable data={schritte} rows=20>
    <Column id=schritt title="Schritt" />
    <Column id=art title="Art" />
    <Column id=beitrag_min title="Beitrag (Min.)" fmt='#,##0.0' />
    <Column id=stand_min title="Stand danach (Min.)" fmt='#,##0.0' />
    <Column id=hinweis title="Hinweis" />
</DataTable>
