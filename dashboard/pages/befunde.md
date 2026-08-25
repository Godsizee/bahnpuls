---
title: Befunde
description: Drei Aussagen aus den Daten — jede mit einer Zahl, einer Grafik und dem, was sie betrieblich bedeutet
sidebar_position: 2
---

Die übrigen Seiten sind Werkzeuge: Sie lassen eine Fahrt nachzeichnen, eine Rangliste
sortieren, eine Schwelle verschieben. Diese Seite tut das Gegenteil — sie **trifft drei
Aussagen** und legt daneben, woran sie sich messen lassen.

Der Ton ist dabei bewusst sachlich. Hinter jeder Verspätung stehen Randbedingungen, die
eine Zahl nicht kennt; wer daraus eine Anklage baut, überdehnt seine Datenbasis. Was hier
steht, ist gemessen, nicht gedeutet.

```sql fenster
-- Alle drei Befunde stehen auf **demselben** Zeitraum. Das ist keine Selbstverständlichkeit:
-- die Quellabfragen dieses Dashboards schneiden unterschiedlich zu (Pünktlichkeit und
-- Engpässe je 30 Betriebstage, die Entstehungssicht gar nicht). Drei Befunde auf drei
-- verschiedenen Fenstern wären drei Aussagen, die sich nicht aufeinander beziehen lassen.
select
    count(distinct betriebstag)               as tage,
    -- Als Text, nicht als Datum mit Anzeigeformat: die Formatierung von Datumswerten
    -- gehört hier in die Abfrage, sonst hängt die Schreibweise an einer Komponente.
    strftime(min(betriebstag), '%d.%m.%Y')    as von,
    strftime(max(betriebstag), '%d.%m.%Y')    as bis
from bahnpuls.puenktlichkeit
```

<Alert status=info>

**Grundlage:** <Value data={fenster} column=tage/> Betriebstage, vom
<Value data={fenster} column=von/> bis
<Value data={fenster} column=bis/>, aus eigener Mitschrift des
Echtzeit-Feeds für VRN und RMV. Zwei Betriebstage (22./23.08.2026) sind darin
<strong>nicht</strong> enthalten — an ihnen hat die Sammlung nachweislich schief
gegriffen, Einzelheiten auf der <a href="/methodik">Methodik-Seite</a>.

Für Aussagen über eine einzelne Linie oder einen bestimmten Bahnhof ist das noch zu kurz.
Für die drei Befunde unten reicht es, weil sie über das ganze Gebiet rechnen.

</Alert>

## Befund 1 — Die übliche Quote lässt aus, was nicht gefahren ist

```sql befund_puenktlich
-- Nur die Sechs-Minuten-Schwelle: die branchenübliche Grenze, damit die Zahl vergleichbar
-- bleibt. Über Schwellen hinweg darf nie summiert werden -- jede Zeile ist eine eigene
-- Auswertung derselben Grundmenge, eine Summe zählte jeden Halt fünffach.
select
    sum(halte_mit_ankunft)  as planmaessig,
    sum(halte_gemessen)     as gemessen,
    sum(halte_puenktlich)   as puenktlich,

    100.0 * sum(halte_puenktlich) / nullif(sum(halte_gemessen), 0)     as quote_gemessen,
    100.0 * sum(halte_puenktlich) / nullif(sum(halte_mit_ankunft), 0)  as quote_planmaessig,
    100.0 * sum(halte_puenktlich) / nullif(sum(halte_gemessen), 0)
      - 100.0 * sum(halte_puenktlich) / nullif(sum(halte_mit_ankunft), 0) as abstand_pp,

    -- Die Halte, die im üblichen Nenner gar nicht vorkommen. Das ist die eigentliche
    -- Zahl dieses Befunds -- der Prozentpunkt-Abstand ist nur ihre Wirkung.
    sum(halte_mit_ankunft) - sum(halte_gemessen)                         as nicht_im_nenner,
    100.0 * (sum(halte_mit_ankunft) - sum(halte_gemessen))
          / nullif(sum(halte_mit_ankunft), 0)                            as nicht_im_nenner_anteil

from bahnpuls.puenktlichkeit
where schwelle_min = 6
```

<BigValue
    data={befund_puenktlich}
    value=nicht_im_nenner
    fmt='#,##0'
    title="Halte, die in der üblichen Quote nicht vorkommen"
/>
<BigValue
    data={befund_puenktlich}
    value=abstand_pp
    fmt='#,##0.0'
    title="Prozentpunkte Unterschied zwischen beiden Lesarten"
/>

```sql befund_verbleib
-- Die sieben Zustände von mart_puenktlichkeit ergeben zusammen exakt halte_mit_ankunft.
-- Hier zu vier Gruppen zusammengefasst, damit die Grafik lesbar bleibt -- und zwar so,
-- dass die Summe erhalten bleibt: keine Gruppe fällt weg, keine zählt doppelt.
select 'pünktlich (unter 6 Min.)' as verbleib, 1 as reihenfolge,
       sum(halte_puenktlich) as halte
from bahnpuls.puenktlichkeit where schwelle_min = 6

union all
select 'verspätet', 2, sum(halte_gemessen) - sum(halte_puenktlich)
from bahnpuls.puenktlichkeit where schwelle_min = 6

union all
select 'Zug fuhr nicht oder hielt nicht', 3,
       sum(halte_ausgefallen) + sum(halte_unbedienter_lauf)
     + sum(halte_verkuerzt)   + sum(halte_ausgelassen)
from bahnpuls.puenktlichkeit where schwelle_min = 6

union all
select 'keine Meldung oder nicht bestimmbar', 4,
       sum(halte_ohne_meldung) + sum(halte_mehrdeutig)
from bahnpuls.puenktlichkeit where schwelle_min = 6

order by reihenfolge
```

<BarChart
    data={befund_verbleib}
    x=verbleib
    y=halte
    swapXY=true
    yAxisTitle="Halte"
    title="Was aus allen planmäßigen Ankünften wurde"
    sort=false
/>

**Die Zahl:** An <Value data={befund_puenktlich} column=nicht_im_nenner fmt='#,##0'/>
Halten sollte planmäßig ein Zug ankommen, ohne dass je einer gemessen wurde — das sind
<Value data={befund_puenktlich} column=nicht_im_nenner_anteil fmt='#,##0.0'/> % aller
planmäßigen Ankünfte. In der üblichen Pünktlichkeitsquote kommen sie
<strong>nicht vor</strong>, weder im Zähler noch im Nenner.

Rechnet man sie mit, waren
<Value data={befund_puenktlich} column=quote_planmaessig fmt='#,##0.0'/> % der planmäßigen
Ankünfte pünktlich. Die übliche Quote nennt
<Value data={befund_puenktlich} column=quote_gemessen fmt='#,##0.0'/> %.

**Was der Unterschied ist:** derselbe Zähler, ein anderer Nenner. Die übliche Quote teilt
durch die Halte, an denen ein Zug **tatsächlich gemessen** wurde. Die zweite teilt durch
alle, an denen planmäßig einer ankommen sollte — die gestrichenen, die ausgelassenen und
die ohne Meldung eingeschlossen.

**Was das betrieblich heißt:** Ein Zug, der nicht fährt, ist nie verspätet. Er fällt aus
der Rechnung, und die Quote wird dadurch **besser**. Das ist kein Rechenfehler und keine
Absicht — so ist die Kennzahl definiert, und sie beantwortet die Frage „wie pünktlich
waren die Züge, die fuhren" korrekt. Sie beantwortet nur nicht die Frage, die auf dem
Bahnsteig zählt. Die
<Value data={befund_puenktlich} column=abstand_pp fmt='#,##0.0'/> Prozentpunkte zwischen
beiden Zahlen sind genau das, was zwischen diesen beiden Fragen liegt.

Die Kurve über fünf Schwellen statt der einen Grenze steht auf der Seite
[Pünktlichkeit und Ausfälle](/puenktlichkeit).

## Befund 2 — Strecke und Bahnhof sind zwei verschiedene Probleme

```sql befund_ort
-- Auf dasselbe Fenster wie Befund 1 eingeschränkt: mart_verspaetungsentstehung ist als
-- Quelle nicht zugeschnitten, die Pünktlichkeitsquelle schon.
with fenster as (
    select min(betriebstag) as von from bahnpuls.puenktlichkeit
)

select
    sum(laufzeit_delta_sek_summe)  / 60.0 as laufzeit_min,
    sum(haltezeit_delta_sek_summe) / 60.0 as haltezeit_min,
    sum(laufzeit_messwerte)               as laufzeit_messwerte,
    sum(haltezeit_messwerte)              as haltezeit_messwerte,

    -- Je Abschnitt bzw. je Halt, nicht als Summe: die beiden Summen beruhen auf
    -- unterschiedlich vielen Messwerten und wären nebeneinander irreführend.
    sum(laufzeit_delta_sek_summe)  / nullif(sum(laufzeit_messwerte), 0)  as laufzeit_sek_je_abschnitt,
    sum(haltezeit_delta_sek_summe) / nullif(sum(haltezeit_messwerte), 0) as haltezeit_sek_je_halt,

    -- Welche der beiden Größen überwiegt, wird **aus den Daten abgeleitet** und nicht in
    -- den Satz geschrieben. Diese Seite wird stündlich neu gebaut; eine fest formulierte
    -- Richtung wäre irgendwann falsch, ohne dass es jemandem auffiele.
    case when sum(haltezeit_delta_sek_summe) / nullif(sum(haltezeit_messwerte), 0)
            > sum(laufzeit_delta_sek_summe)  / nullif(sum(laufzeit_messwerte), 0)
         then 'im Bahnhof, während des Halts'
         else 'unterwegs, zwischen zwei Bahnhöfen' end as ueberwiegt

from bahnpuls.mart_verspaetungsentstehung, fenster
where betriebstag >= fenster.von
```

```sql befund_ort_lang
select 'unterwegs, zwischen zwei Bahnhöfen' as ort, laufzeit_sek_je_abschnitt as sekunden from ${befund_ort}
union all
select 'im Bahnhof, während des Halts', haltezeit_sek_je_halt from ${befund_ort}
```

<BarChart
    data={befund_ort_lang}
    x=ort
    y=sekunden
    swapXY=true
    yAxisTitle="Sekunden je gemessenem Vorgang"
    title="Wo die Verspätung entsteht, je einzelnem Abschnitt und Halt"
    sort=false
/>

**Die Zahl:** Je gefahrenem Abschnitt kamen im Mittel
<Value data={befund_ort} column=laufzeit_sek_je_abschnitt fmt='#,##0.0'/> Sekunden dazu,
je Halt <Value data={befund_ort} column=haltezeit_sek_je_halt fmt='#,##0.0'/> Sekunden.
Mehr entsteht damit <strong><Value data={befund_ort} column=ueberwiegt/></strong> — und
das ist die Stelle, an der sich diese Auswertung von einer gewöhnlichen unterscheidet, denn eine
Ankunftsverspätung allein sagt darüber nichts. Ein negativer Wert bedeutet, dass dort unter
dem Strich Reserve genutzt und Verspätung abgebaut wurde.

**Was der Unterschied ist:** Für jeden Halt wird zweierlei festgehalten — wie viel
Verspätung ein Zug beim Ankommen hatte und wie viel beim Weiterfahren. Wächst sie
**zwischen** zwei Bahnhöfen, hat die Fahrt länger gedauert als vorgesehen. Wächst sie
**während** des Halts, hat der Aufenthalt länger gedauert.

**Was das betrieblich heißt:** Das sind zwei verschiedene Probleme mit zwei verschiedenen
Maßnahmen. Laufzeitverlust deutet auf Trassenkonflikt, Langsamfahrstelle, Überholung oder
Baustelle — also auf Infrastruktur und Trassenlage. Haltezeitverlust deutet auf
Fahrgastwechsel, Anschlusswarten, Disposition oder Personalwechsel. Eine Ankunftsverspätung
allein trennt die beiden nicht, und genau deshalb rechnet dieses Projekt sie auseinander.

Der Verlauf an einer einzelnen Fahrt steht auf der Seite
[Laufweg einer Fahrt](/laufweg).

## Befund 3 — Es klemmt an wenigen Stellen, und zwar wiederholt

```sql befund_engpass
select
    von_bezeichnung || ' → ' || nach_bezeichnung as abschnitt,
    sum(zuege)                                   as zuege,
    sum(laufzeit_messwerte)                      as messbar,
    sum(laufzeit_summe)  / nullif(sum(laufzeit_messwerte), 0)  / 60.0 as laufzeit_min,
    sum(haltezeit_summe) / nullif(sum(haltezeit_messwerte), 0) / 60.0 as haltezeit_min

from bahnpuls.engpassknoten
where bezeichnung_vollstaendig
group by 1
-- Ohne Untergrenze stünde hier der Abschnitt mit drei Zügen und einem gestörten davon.
-- Die Grenze ist bewusst niedrig: die Quelle liefert ohnehin nur die 200
-- meistbefahrenen Abschnitte, greift also schon vor. Sie steht trotzdem hier, weil diese
-- Vorauswahl eine Eigenschaft der Quelle ist und keine dieser Seite -- ändert sie sich,
-- soll der Befund nicht lautlos auf drei Zügen stehen.
having sum(laufzeit_messwerte) >= 100
order by laufzeit_min desc
limit 5
```

<DataTable data={befund_engpass} rows=5 emptySet=warn
    emptyMessage="Kein Abschnitt erreicht im Zeitraum 100 messbare Fahrten.">
    <Column id=abschnitt title="Abschnitt" />
    <Column id=zuege title="Züge" />
    <Column id=messbar title="davon messbar" />
    <Column id=laufzeit_min title="unterwegs dazu (Min./Zug)" fmt='#,##0.00' contentType=bar barColor=verloren negativeBarColor=aufgeholt />
    <Column id=haltezeit_min title="im Bahnhof dazu (Min./Zug)" fmt='#,##0.00' />
</DataTable>

```sql befund_engpass_spitze
select abschnitt, laufzeit_min, zuege, messbar
from ${befund_engpass}
limit 1
```

```sql befund_engpass_stunden
-- Der Tagesverlauf desselben Abschnitts. Ein Engpass, der über alle Stunden gleich
-- aussieht, ist ein anderer Vorgang als einer, der nur in der Spitze auftritt.
select
    engpass.stunde,
    sum(engpass.zuege)                                            as zuege,
    sum(engpass.laufzeit_summe) / nullif(sum(engpass.laufzeit_messwerte), 0) / 60.0
        as laufzeit_min

from bahnpuls.engpassknoten as engpass
where engpass.von_bezeichnung || ' → ' || engpass.nach_bezeichnung
      = (select abschnitt from ${befund_engpass_spitze})
  -- Halte ohne bekannte Soll-Zeit tragen keine Tagesstunde. Sie hier wegzulassen ist
  -- keine Filterung des Befunds, sondern die Feststellung, dass eine unbekannte Stunde
  -- keine Stunde ist -- dieselbe Regel wie auf der Engpass-Seite.
  and engpass.stunde is not null
group by 1
order by 1
```

<LineChart
    data={befund_engpass_stunden}
    emptySet=warn
    emptyMessage="Kein Abschnitt erreicht im Zeitraum 100 messbare Fahrten."
    x=stunde
    y=laufzeit_min
    yAxisTitle="Minuten je Zug"
    xAxisTitle="Tagesstunde"
    markers=true
    title="Der Abschnitt an der Spitze, über den Tag"
/>

**Die Zahl:** Auf dem Abschnitt
<Value data={befund_engpass_spitze} column=abschnitt emptySet=warn emptyMessage="(keiner)"/>
kommen im Mittel
<Value data={befund_engpass_spitze} column=laufzeit_min fmt='#,##0.00' emptySet=warn emptyMessage="—"/>
Minuten je Zug unterwegs dazu, gemessen an
<Value data={befund_engpass_spitze} column=messbar fmt='#,##0' emptySet=warn emptyMessage="—"/>
Fahrten.

**Was gerechnet wird:** die neu entstandene Verspätung **je Zug**, nie als Summe. Eine
Summe rankt zwangsläufig den dichtest befahrenen Abschnitt nach oben — der hat mehr Züge,
nicht mehr Probleme. Diese eine Regel entscheidet, ob die Rangliste etwas aussagt.

**Was das betrieblich heißt:** Verspätung verteilt sich nicht gleichmäßig über das Netz.
Sie sammelt sich an wenigen Stellen — und die Tagesganglinie darüber wird mit wachsender
Aufzeichnung zur eigentlich interessanten Grafik: Ausgeprägte Spitzen deuten auf
Kapazität, die nur in den Hauptverkehrszeiten nicht reicht; ein über den Tag flaches Bild
deutet eher auf eine bauliche oder fahrplanseitige Ursache, die immer wirkt.

**Noch ist sie das nicht.** Bei wenigen Betriebstagen stehen hinter jeder Stunde nur
einige Züge; einzelne Ausschläge sind dann Zufall und keine Tagesspitze. Die Linie ist
deshalb hier als das zu lesen, was sie ist — eine erste Form, keine Aussage über
Tageszeiten.

Die vollständige Rangliste mit einstellbarer Untergrenze, dazu die Auswertung nach
Fahrtrichtung, steht auf der Seite [Engpässe im Netz](/engpaesse).

## Was diese drei Befunde nicht sagen

Dieser Abschnitt ist kein Anhängsel. Wer die Zahlen prüft, muss die Grenzen von hier
erfahren und nicht selbst finden.

- **Es sind Tage, keine Regelmäßigkeit.** <Value data={fenster} column=tage/> Betriebstage
  tragen eine Aussage über das Gebiet, aber keine über einen einzelnen Bahnhof, eine
  einzelne Linie oder einen Wochentag.
- **Die Pünktlichkeitsquote ist eine obere Schranke.** Der Nenner ist der *beobachtete*
  Laufweg, nicht der Fahrplan. Ein Zug, den der Feed nie erwähnt hat, fehlt auch hier —
  die Quote kann dadurch nur besser aussehen als die Wirklichkeit, nie schlechter.
- **Die Engpass-Rangliste sieht nur die 200 meistbefahrenen Abschnitte.** Das ist bewusst
  so: Würde nach Verspätung vorausgewählt, suchte die Rangliste in einer Menge, die schon
  nach demselben Kriterium sortiert wurde. Der Preis ist, dass ein Engpass auf einer wenig
  befahrenen Strecke hier nicht auftaucht.
- **Verspätung ist hier Abweichung vom Fahrplan, nicht Schuld.** Ob ein Fahrplan
  realistisch war, ob eine Baustelle angekündigt oder eine Störung fremdverursacht war,
  steht in keiner dieser Zahlen.

Wie jede Kennzahl gerechnet wird und welche Annahmen darin stecken, steht vollständig auf
der [Methodik-Seite](/methodik).
