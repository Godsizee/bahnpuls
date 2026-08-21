---
title: Pünktlichkeit und Ausfälle
description: Zwei Quoten nebeneinander — die übliche und die, in der Ausfälle nicht verschwinden
sidebar_position: 5
---

Ein ausgefallener Zug ist nie verspätet. Das klingt wie ein Wortspiel, hat aber eine
handfeste Folge: Eine Pünktlichkeitsquote zählt nur Züge, die gefahren sind. Wird ein Zug
gestrichen, fällt er aus der Rechnung — und die Quote wird dadurch **besser**.

Das ist kein Vorwurf an irgendjemanden; so ist die Kennzahl definiert, und sie beantwortet
die Frage „wie pünktlich waren die Züge, die fuhren" korrekt. Sie beantwortet nur nicht
die Frage, die auf dem Bahnsteig zählt: **kam mein Zug, und kam er rechtzeitig?**

Diese Seite stellt beide Antworten nebeneinander.

```sql herkuenfte
select
    quelle,
    case quelle
        when 'de_gtfsrt'   then 'Deutschland — eigene Aufzeichnung'
        when 'ch_istdaten' then 'Schweiz — konstruierte Testfälle'
        else quelle
    end                      as bezeichnung,
    count(distinct betriebstag) as tage
from bahnpuls.puenktlichkeit
group by quelle
order by quelle desc
```

<Dropdown data={herkuenfte} name=herkunft value=quelle label=bezeichnung title="Herkunft" />

## Die Kurve, nicht die eine Zahl

```sql kurve
select
    schwelle_min,
    sum(halte_puenktlich)                                as puenktlich,
    sum(halte_gemessen)                                  as gemessen,
    sum(halte_mit_ankunft)                               as planmaessig,
    100.0 * sum(halte_puenktlich) / nullif(sum(halte_gemessen), 0)    as quote_gemessen,
    100.0 * sum(halte_puenktlich) / nullif(sum(halte_mit_ankunft), 0) as quote_planmaessig
from bahnpuls.puenktlichkeit
where quelle = '${inputs.herkunft.value}'
group by schwelle_min
order by schwelle_min
```

```sql kurve_lang
select schwelle_min, 'nur gefahrene Halte' as lesart, quote_gemessen as quote from ${kurve}
union all
select schwelle_min, 'alle planmäßigen Halte', quote_planmaessig from ${kurve}
order by lesart, schwelle_min
```

<LineChart
    data={kurve_lang}
    x=schwelle_min
    y=quote
    series=lesart
    yAxisTitle="Prozent"
    xAxisTitle="Schwelle in Minuten"
    yMin=0
    yMax=100
    markers=true
    title="Anteil pünktlicher Halte, je nachdem wo man die Grenze zieht"
/>

Die branchenübliche Grenze liegt bei **unter sechs Minuten**. Als einzige Zahl verdeckt
sie genau das, was Reisende trifft: 5:59 gilt als pünktlich, der Vier-Minuten-Anschluss
ist trotzdem weg. Deshalb stehen hier fünf Grenzen nebeneinander — die Form der Kurve sagt
mehr als jeder einzelne Punkt auf ihr.

**Die beiden Linien unterscheiden sich nur im Nenner.** Oben: alle Halte, an denen ein
Zug *tatsächlich gemessen* wurde. Unten: alle Halte, an denen planmäßig einer ankommen
sollte — die ausgefallenen, die ausgelassenen und die ohne Meldung eingeschlossen. Der
Abstand zwischen den Linien ist das, was in der oberen Zahl nicht vorkommt.

## Wohin die Halte fallen, die keine Zahl bekommen

```sql zustaende
select
    sum(halte_mit_ankunft)  as planmaessig,
    sum(halte_gemessen)     as gemessen,
    sum(halte_ausgefallen)  as ausgefallen,
    sum(halte_verkuerzt)    as verkuerzt,
    sum(halte_ausgelassen)  as ausgelassen,
    sum(halte_mehrdeutig)   as mehrdeutig,
    sum(halte_ohne_meldung) as ohne_meldung,
    sum(fahrten)            as fahrten,
    sum(fahrten_ausgefallen) as fahrten_ausgefallen,
    sum(fahrten_verkuerzt)   as fahrten_verkuerzt
from bahnpuls.puenktlichkeit
-- Eine einzige Schwelle: die Zustände hängen nicht von ihr ab und stünden sonst fünffach
-- in der Summe. Genau dieser Fehler wäre unauffällig — die Zahlen sähen nur größer aus.
where quelle = '${inputs.herkunft.value}'
  and schwelle_sek = 360
```

<DataTable data={zustaende} rows=1>
    <Column id=planmaessig title="planmäßige Halte" />
    <Column id=gemessen title="gemessen" />
    <Column id=ausgefallen title="Zug ausgefallen" />
    <Column id=verkuerzt title="Laufweg gekappt" />
    <Column id=ausgelassen title="Halt ausgelassen" />
    <Column id=mehrdeutig title="Zeitumstellung" />
    <Column id=ohne_meldung title="keine Meldung" />
</DataTable>

Die sechs Spalten schließen einander aus und ergeben zusammen genau die erste. Ein Halt
kann nicht zugleich ausgefallen und ausgelassen gezählt werden; wo mehrere Gründe
zuträfen, gilt der schwerwiegendere.

Drei davon sind **Betrieb** und gehören zum Bild: der Zug fiel aus, sein Laufweg wurde
gekappt, ein Halt wurde übersprungen. „Laufweg gekappt" heißt, dass der Zug fuhr, aber
nicht die ganze Strecke — für Reisende an den entfallenen Bahnhöfen ist das ein
vollständiger Ausfall, in einer Ausfallquote je Zug taucht es meist nicht auf.

Zwei sind **Messung**: In der Nacht der Zeitumstellung gibt es eine Stunde doppelt, die
Rechnung ist dann nicht eindeutig. Und „keine Meldung" heißt, dass der Zug planmäßig da
sein sollte, nicht ausgefallen war — und trotzdem keine Ist-Zeit kam. Nur bei dieser
letzten Spalte bedeutet ein Anstieg ein Problem der Erhebung.

## Je Linie

```sql je_linie
select
    linie,
    sum(fahrten)             as fahrten,
    sum(fahrten_ausgefallen) as ausgefallen,
    sum(fahrten_verkuerzt)   as verkuerzt,
    sum(halte_mit_ankunft)   as halte,
    100.0 * sum(halte_puenktlich) / nullif(sum(halte_gemessen), 0)    as quote_gemessen,
    100.0 * sum(halte_puenktlich) / nullif(sum(halte_mit_ankunft), 0) as quote_planmaessig
from bahnpuls.puenktlichkeit
where quelle = '${inputs.herkunft.value}'
  and schwelle_sek = 360
group by linie
order by halte desc, linie
```

<DataTable data={je_linie} rows=15 search=true>
    <Column id=linie title="Linie" />
    <Column id=fahrten title="Fahrten" />
    <Column id=ausgefallen title="davon ausgefallen" />
    <Column id=verkuerzt title="davon gekappt" />
    <Column id=halte title="planmäßige Halte" />
    <Column id=quote_gemessen title="pünktlich, gefahrene (%)" fmt='#,##0.0' />
    <Column id=quote_planmaessig title="pünktlich, planmäßige (%)" fmt='#,##0.0' />
</DataTable>

Beide Quoten bei der Sechs-Minuten-Grenze. Linien mit wenigen Halten stehen unten — bei
kleiner Grundmenge schwankt eine Quote stark, und eine Rangliste über solche Werte wäre
Zufall mit Nachkommastellen.

<Alert status=info>

**Zwei Grenzen dieser Seite, ausdrücklich.** Erstens: der Nenner ist der **beobachtete**
Laufweg, nicht der Fahrplan. Ein Zug, der komplett ausfiel und über den der Feed gar nichts
mehr meldete, fehlt auch hier — beide Quoten sind damit obere Schranken und können nur
besser aussehen als die Wirklichkeit, nie schlechter. Zweitens: gezeigt werden die letzten
30 aufgezeichneten Betriebstage.

Wie die Zahlen im Einzelnen zustande kommen, steht auf der Seite [Methodik](/methodik).

</Alert>

---

Daten von [gtfs.de](https://gtfs.de) (CC BY-SA 4.0 bzw. CC BY 4.0) — vollständige
Angaben unter [Lizenz und Quellen](/lizenz) · [Impressum](/impressum) ·
[Datenschutz](/datenschutz)
