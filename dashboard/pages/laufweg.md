---
title: Laufweg einer Fahrt
description: Der Verspätungsverlauf einer einzelnen Fahrt, zerlegt in Laufzeit- und Haltezeitanteil
sidebar_position: 2
---

Eine einzelne Fahrt, von Halt zu Halt nachgezeichnet. Statt einer Zahl am Ende — „zwölf
Minuten zu spät" — steht hier, an welcher Stelle diese Minuten dazugekommen sind, und ob
das unterwegs passierte oder während eines Aufenthalts.

**Gezeigt wird der Laufweg innerhalb von VRN und RMV.** Ein Fernzug fährt weiter, als
hier zu sehen ist — seine Halte außerhalb des Gebiets stehen in den Daten, aber nicht auf
dieser Seite. Was er an Verspätung mitbringt, ist trotzdem abzulesen: Sie steht als
Ankunftsverspätung an seinem ersten Halt hier. Nur der Laufzeitanteil des
Einfahrtsabschnitts fehlt, weil er auf einer Strecke entstanden ist, die diese Seite nicht
zeigt (siehe [Methodik](/methodik)).

**So liest man die Diagramme:** Das obere zeigt, was jeder einzelne Abschnitt und jeder
Halt beigetragen hat. Ein Balken nach oben heißt, dort ist Verspätung entstanden; ein
Balken nach unten heißt, dort wurde welche aufgeholt. Die Farbe sagt, ob es unterwegs
passierte oder im Bahnhof. Das untere Diagramm zeigt denselben Zug noch einmal anders: wie
viel Verspätung er zu jedem Zeitpunkt insgesamt mit sich trug.

## Fahrt auswählen

```sql tage
-- Der Betriebstag wird als **Text** ausgewählt, nicht als Datum: der Wert eines
-- Dropdowns landet über eine Zeichenkette wieder in der Abfrage, und ein Datum wird
-- dabei zu dem, was der Browser daraus macht ("Thu Aug 13 2026 …"). Der Vergleich liefe
-- dann leer — ohne Fehlermeldung, nur mit leerer Seite.
select
    strftime(betriebstag, '%Y-%m-%d')  as tag,
    -- Ein Tag mit unvollstaendiger Erhebung bleibt waehlbar und sagt es in der
    -- Beschriftung (BPULS-079). Die einzelne Fahrt ist richtig aufgezeichnet; schief
    -- ist, welche Fahrten an diesem Tag ueberhaupt aufgezeichnet wurden.
    strftime(max(betriebstag), '%d.%m.%Y')
        || case when bool_and(erhebung_vollstaendig) then ''
                else ' — Erhebung unvollständig' end as beschriftung,
    max(betriebstag)                   as sortierung,
    count(distinct trip_key)           as fahrten
from bahnpuls.zuglauf_auswahl
group by strftime(betriebstag, '%Y-%m-%d')
order by sortierung desc
```

```sql linien
-- Die Linienliste folgt der Tagesauswahl. Zöge sie ihre Werte aus dem ungefilterten
-- Bestand, ließen sich Tag und Linie zu einer Kombination zusammenstellen, die keine
-- einzige Fahrt trifft — die Seite stünde dann leer da, ohne dass erkennbar wäre, warum.
select linie, count(distinct trip_key) as fahrten
from bahnpuls.zuglauf_auswahl
where strftime(betriebstag, '%Y-%m-%d') = '${inputs.tag.value}'
group by linie
order by linie
```

```sql fahrten
with gefiltert as (

    select *
    from bahnpuls.zuglauf_auswahl
    where strftime(betriebstag, '%Y-%m-%d') = '${inputs.tag.value}'
      and linie like '${inputs.linie.value}'

),

grenzen as (

    -- Erster und letzter **gelieferter** Halt, nicht 1 und n: bei den deutschen
    -- Echtzeitdaten ist halt_nr die Fahrplannummer, nicht die Position, und ein Zug,
    -- der beim Beobachtungsbeginn schon unterwegs war, taucht erst später darin auf.
    select
        trip_key,
        min(halt_nr)           as erster,
        max(halt_nr)           as letzter,
        count(*)               as halte,
        any_value(linie)       as linie,
        any_value(ab_soll)     as ab_soll,
        any_value(betriebstag) as betriebstag
    from gefiltert
    group by trip_key

)

select
    grenzen.trip_key,
    grenzen.linie || ' · ab '
        || coalesce(strftime(grenzen.ab_soll, '%H:%M'), '--:--') || ' · '
        || start.halt || ' → ' || ziel.halt as bezeichnung,
    grenzen.halte
from grenzen
join gefiltert as start
  on  start.trip_key = grenzen.trip_key and start.halt_nr = grenzen.erster
join gefiltert as ziel
  on  ziel.trip_key  = grenzen.trip_key and ziel.halt_nr  = grenzen.letzter
order by grenzen.ab_soll nulls last, bezeichnung
```

<Dropdown data={tage} name=tag value=tag label=beschriftung title="Betriebstag" />

<Dropdown data={linien} name=linie value=linie title="Linie">
    <DropdownOption value="%" valueLabel="alle Linien" />
</Dropdown>

<Dropdown data={fahrten} name=fahrt value=trip_key label=bezeichnung title="Fahrt" />

<Alert status=info>

**Zur Auswahl steht ein Ausschnitt, kein Gesamtbestand.** Angeboten werden
die letzten drei aufgezeichneten Betriebstage, darin je Tag und Linie die ersten sechs
Fahrten nach planmäßiger Abfahrt. Das liegt an der Technik, nicht an fehlenden Daten:
Die Diagramme rechnen direkt im Browser, und ein vollständiger Betriebstag wären mehrere
hundert Megabyte, die jeder Besucher erst herunterladen müsste. Die Zahlen auf der
[Startseite](/) beruhen dagegen auf allem, was aufgezeichnet wurde.

Die Quote gilt **je Linie**, damit jede Linie überhaupt in der Auswahl vorkommt. Ein
Schnitt über alle Fahrten hinweg wäre einfacher gewesen und hätte den Linienfilter
darüber wertlos gemacht — er kennte dann die halben Linien gar nicht. Aus demselben Grund
ist die Fahrt eines Tages, die hier fehlt, **nicht** als „nicht aufgezeichnet" zu lesen:
sie ist nur nicht in dieser Auswahl.

Steht hinter einem Betriebstag **„Erhebung unvollständig"**, hat die Sammlung an diesem
Tag nicht alle Züge erwischt — die hier gezeigten Fahrten sind trotzdem richtig
aufgezeichnet, denn schief ist die Auswahl, nicht die Messung. In den Kennzahlen auf den
übrigen Seiten kommen diese Tage nicht vor; warum, steht auf der
[Methodik-Seite](/methodik) unter „Zwei Betriebstage, die nicht mitzählen“.

</Alert>

```sql schritte
with halte as (

    select *
    from bahnpuls.zuglauf_auswahl
    where trip_key = '${inputs.fahrt.value}'

),

benannt as (

    select
        *,
        min(halt_nr) over ()                                   as erster,
        count(*)     over (partition by halt)                  as vorkommen,
        row_number() over (partition by halt order by halt_nr) as lauf
    from halte

),

etikettiert as (

    -- Ein Bahnhof kann in einem Laufweg **zweimal** vorkommen: Kopfmachen, Ringlauf,
    -- Wendefahrt. Die Daten unterscheiden die beiden Halte über halt_nr, eine
    -- Diagrammachse über den Namen aber nicht — beide Schritte fielen dort auf dieselbe
    -- Kategorie und würden stillschweigend zusammengezählt. Deshalb bekommt der Name
    -- eine Nummer, aber nur dort, wo er mehrdeutig ist.
    select
        *,
        case when vorkommen > 1 then halt || ' (' || lauf || '. Mal)' else halt end
            as halt_eindeutig
    from benannt

),

zerlegt as (

    -- Startverspätung: der Stand, mit dem die Fahrt in die Beobachtung eintritt
    select
        halt_nr * 10                         as reihenfolge,
        'Start ' || halt_eindeutig           as schritt,
        'Startverspätung'                    as art,
        coalesce(delay_an_sek, delay_ab_sek) as beitrag_sek,
        coalesce(delay_an_sek, delay_ab_sek) as stand_sek,
        zeitumstellung_mehrdeutig,
        zug_ausgefallen,
        halt_ausgelassen
    from etikettiert
    where halt_nr = erster

    union all

    -- Laufzeitanteil: was auf dem Abschnitt vom Vorhalt hierher entstand.
    -- Der Stand davor ergibt sich aus dem Mart, ohne zweites Fenster:
    -- delay_an − laufzeit_delta ist genau die Abfahrtsverspätung des Vorhalts.
    select
        halt_nr * 10 + 1,
        '→ ' || halt_eindeutig,
        'Unterwegs',
        laufzeit_delta_sek,
        delay_an_sek,
        zeitumstellung_mehrdeutig,
        zug_ausgefallen,
        halt_ausgelassen
    from etikettiert
    where halt_nr > erster

    union all

    -- Haltezeitanteil: was während des Halts entstand. Nur wo der Fahrplan überhaupt
    -- Ankunft und Abfahrt vorsieht — am Start- und am Endhalt fehlt eine der beiden
    -- planmäßig, und das ist kein fehlender Messwert.
    select
        halt_nr * 10 + 2,
        'Halt ' || halt_eindeutig,
        'Im Bahnhof',
        haltezeit_delta_sek,
        delay_ab_sek,
        zeitumstellung_mehrdeutig,
        zug_ausgefallen,
        halt_ausgelassen
    from etikettiert
    where halt_mit_aufenthalt

)

select
    reihenfolge,
    schritt,
    art,
    beitrag_sek / 60.0 as beitrag_min,
    stand_sek   / 60.0 as stand_min,
    case
        when zug_ausgefallen           then 'Zug ausgefallen'
        when halt_ausgelassen          then 'Halt ausgelassen'
        when zeitumstellung_mehrdeutig then 'Nacht der Zeitumstellung — nicht eindeutig'
        when beitrag_sek is null       then 'keine Meldung'
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

Fährt ein Zug denselben Bahnhof zweimal an — beim Kopfmachen oder auf einer Wendefahrt —,
steht hinter dem Namen, das wievielte Mal es ist. Ohne diese Unterscheidung fielen beide
Halte auf dieselbe Stelle der Achse und würden zusammengezählt.

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

---

Daten von [gtfs.de](https://gtfs.de) (CC BY-SA 4.0 bzw. CC BY 4.0) — vollständige
Angaben unter [Lizenz und Quellen](/lizenz) · [Impressum](/impressum) ·
[Datenschutz](/datenschutz)
