---
title: Pünktlichkeit und Ausfälle
description: Zwei Quoten nebeneinander — die übliche und die, in der Ausfälle nicht verschwinden
sidebar_position: 7
---

**Diese Seite stellt zwei Pünktlichkeitsquoten nebeneinander: die übliche und die, in der
ausgefallene Züge nicht verschwinden.**

Ein ausgefallener Zug ist nie verspätet. Das klingt wie ein Wortspiel, hat aber eine
handfeste Folge. Eine Pünktlichkeitsquote zählt nur Züge, die gefahren sind. Wird ein Zug
gestrichen, fällt er aus der Rechnung — und die Quote wird dadurch **besser**.

Das ist kein Vorwurf an irgendjemanden. So ist die Kennzahl definiert, und sie beantwortet
ihre Frage korrekt: „Wie pünktlich waren die Züge, die fuhren?" Sie beantwortet nur nicht
die Frage, die auf dem Bahnsteig zählt: **Kam mein Zug, und kam er rechtzeitig?**

```sql gattungen
-- Nur die Auswahlliste: welche Verkehrsarten und Gattungen auf **dieser** Seite
-- ueberhaupt vorkommen (ADR-014). Eine Gattung anzubieten, die es hier nicht gibt,
-- waere ein Knopf, der in eine leere Tabelle fuehrt.
select verkehrsart, gattung
from bahnpuls.puenktlichkeit
group by verkehrsart, gattung
```

<Auswahlleiste data={gattungen} hinweis="Die Schwelle steht darunter." />

<!--
`${inputs.schwelle}` steht ohne `.value` -- <ButtonGroup> legt seinen Wert roh im
Eingabespeicher ab, genau wie <Slider>. Mit `.value` bliebe die Abfrage stumm stehen
(BPULS-084).
-->
<AdresseMerken eingabe="schwelle" vorgabe="6" let:vorauswahl>
<ButtonGroup name=schwelle title="Ab wann gilt ein Halt als verspätet?" defaultValue={vorauswahl}>
    <ButtonGroupItem value="1" valueLabel="1 Min." defaultValue={vorauswahl} />
    <ButtonGroupItem value="3" valueLabel="3 Min." defaultValue={vorauswahl} />
    <ButtonGroupItem value="6" valueLabel="6 Min." defaultValue={vorauswahl} />
    <ButtonGroupItem value="15" valueLabel="15 Min." defaultValue={vorauswahl} />
    <ButtonGroupItem value="60" valueLabel="60 Min." defaultValue={vorauswahl} />
</ButtonGroup>
</AdresseMerken>

```sql gewaehlte_schwelle
-- Die gewählte Schwelle als Zahl, damit sie im Text stehen kann, ohne dort
-- festgeschrieben zu sein. Bis zum 25.08.2026 stand dort „Sechs-Minuten-Grenze" —
-- ein Satz, der ab dem ersten Klick auf einen anderen Knopf falsch gewesen wäre.
select ${inputs.schwelle} as schwelle_min
```

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
where verkehrsart like '${inputs.verkehrsart}'
  and gattung in ${inputs.gattung.value}
group by schwelle_min
order by schwelle_min
```

```sql kurve_lang
select schwelle_min, 'nur gefahrene Halte' as lesart, quote_gemessen as quote from ${kurve}
union all
select schwelle_min, 'alle planmäßigen Halte', quote_planmaessig from ${kurve}
order by lesart, schwelle_min
```

**So liest du die beiden Linien.** Sie unterscheiden sich nur im Nenner. Die obere teilt
durch alle Halte, an denen ein Zug *tatsächlich gemessen* wurde. Die untere teilt durch
alle Halte, an denen planmäßig einer ankommen sollte — die ausgefallenen, die ausgelassenen
und die ohne Meldung eingeschlossen. Der Abstand zwischen den Linien ist das, was in der
oberen Zahl nicht vorkommt.

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
    emptySet=warn
    emptyMessage="Die Auswahl oben trifft keinen einzigen Halt. Stell die Verkehrsart auf „Alle“ oder nimm eine Gattung dazu."
/>

Die branchenübliche Grenze liegt bei **unter sechs Minuten**. Als einzige Zahl verdeckt sie
genau das, was Reisende trifft: 5:59 gilt als pünktlich, der Vier-Minuten-Anschluss ist
trotzdem weg. Deshalb stehen hier alle fünf Grenzen nebeneinander. Die Form der Kurve sagt
mehr als jeder einzelne Punkt auf ihr.

## Wohin die Halte fallen, die keine Zahl bekommen

```sql zustaende
select
    sum(halte_mit_ankunft)  as planmaessig,
    sum(halte_gemessen)     as gemessen,
    sum(halte_ausgefallen)  as ausgefallen,
    sum(halte_unbedienter_lauf) as unbedienter_lauf,
    sum(halte_verkuerzt)    as verkuerzt,
    sum(halte_ausgelassen)  as ausgelassen,
    sum(halte_mehrdeutig)   as mehrdeutig,
    sum(halte_ohne_meldung) as ohne_meldung,
    sum(fahrten)            as fahrten,
    sum(fahrten_ausgefallen) as fahrten_ausgefallen,
    sum(fahrten_unbedienter_lauf) as fahrten_unbedienter_lauf,
    sum(fahrten_unbedienter_lauf_bestaetigt) as fahrten_unbedienter_lauf_bestaetigt,
    sum(fahrten_verkuerzt)   as fahrten_verkuerzt
from bahnpuls.puenktlichkeit
-- Eine einzige Schwelle: die Zustände hängen nicht von ihr ab und stünden sonst fünffach
-- in der Summe. Genau dieser Fehler wäre unauffällig — die Zahlen sähen nur größer aus.
-- Welche der fünf es ist, ist deshalb gleichgültig; genommen wird die gewählte, damit
-- die Seite nicht an zwei Stellen von verschiedenen Schwellen spricht.
where schwelle_min = ${inputs.schwelle}
  and verkehrsart like '${inputs.verkehrsart}'
  and gattung in ${inputs.gattung.value}
```

<DataTable data={zustaende} rows=1 emptySet=warn
    emptyMessage="Die Auswahl oben trifft keinen einzigen Halt. Stell die Verkehrsart auf „Alle“ oder nimm eine Gattung dazu.">
    <Column id=planmaessig title="planmäßige Halte" />
    <Column id=gemessen title="gemessen" />
    <Column id=ausgefallen title="Ausfall gemeldet" />
    <Column id=unbedienter_lauf title="kein Halt bedient" />
    <Column id=verkuerzt title="Laufweg gekappt" />
    <Column id=ausgelassen title="Halt ausgelassen" />
    <Column id=mehrdeutig title="Zeitumstellung" />
    <Column id=ohne_meldung title="keine Meldung" />
</DataTable>

Die sieben Spalten schließen einander aus und ergeben zusammen genau die erste. Ein Halt
kann nicht zugleich als ausgefallen und als ausgelassen gezählt werden. Wo mehrere Gründe
zuträfen, gilt der schwerwiegendere.

<Alert status=warning>

**Warum hier zwei Spalten für dasselbe stehen — und warum die erste bei den deutschen
Daten leer bleibt.** „Ausfall gemeldet" zählt Züge, die die Quelle *ausdrücklich* als
ausgefallen meldet. „Kein Halt bedient" zählt Läufe, in denen **kein einziger** Halt
bedient wurde. Das eine ist ein Bericht, das andere eine Beobachtung — und die beiden
Zahlen nebeneinander sind ehrlicher als eine gemeinsame.

GTFS-Realtime lässt zwei Formen zu, einen Ausfall auszudrücken: eine Markierung an der
**ganzen Fahrt**, oder das Streichen **jedes einzelnen Halts**. Eine Auszählung des
vollständigen bundesweiten Feeds am 21.08.2026 ergab: von **49.133 Fahrten** trug **keine
einzige** die Markierung an der Fahrt. Gestrichene Halte gab es dagegen reichlich —
**12.747**, und bei **582 Fahrten** (1,2 %) war *jeder* Halt gestrichen. Dieser Feed
benutzt also die zweite Form. Die erste Spalte steht deshalb strukturell auf null; das
ist keine Aussage über den Betrieb.

**Was „kein Halt bedient" nicht behauptet:** dass der Zug nicht fuhr. Die Spalte sagt,
dass im *beobachteten* Lauf kein Halt bedient wurde. Wird eine Fahrt erst ab der Mitte
beobachtet und ist der Rest gestrichen, sieht eine gekappte Fahrt genauso aus. Deshalb
steht sie neben „Ausfall gemeldet" und nicht darin.

**Für einen Teil dieser Fahrten lässt sich der Zweifel ausräumen** — und die Tabelle je
Linie weiter unten weist ihn getrennt aus. Deckt der beobachtete Laufweg den
**planmäßigen vollständig** ab, wurde nicht nur ein gestrichenes Ende gesehen, sondern die
ganze Fahrt. Der Abgleich läuft gegen die zum Betriebstag gültige Fahrplan-Version, nicht
gegen die neueste. Was übrig bleibt, ist nicht Ungenauigkeit, sondern die Reichweite der
Beobachtung — und weil es dafür zwei ganz verschiedene Gründe gibt, steht dort eine dritte
Spalte: geprüft und widerlegt ist etwas anderes als gar nicht prüfbar.

Eine Lücke bleibt: ein Zug, über den der Feed **gar nichts** meldet, taucht nirgends auf.
Wie oft das vorkommt, ist offen.

</Alert>

**Vier davon sind Betrieb** und gehören zum Bild: Der Ausfall wurde gemeldet. Im ganzen
Lauf wurde kein Halt bedient. Der Laufweg wurde gekappt. Ein einzelner Halt wurde
übersprungen.

„Laufweg gekappt" heißt: Der Zug fuhr, aber nicht die ganze Strecke. Für Reisende an den
entfallenen Bahnhöfen ist das ein vollständiger Ausfall; in einer Ausfallquote je Zug
taucht es meist nicht auf. Ein Lauf ohne jeden bedienten Halt hat dagegen keinen Rand, der
gekappt sein könnte, und steht deshalb in einer eigenen Spalte.

**Zwei sind Messung.** In der Nacht der Zeitumstellung gibt es eine Stunde doppelt; die
Rechnung ist dann nicht eindeutig. Und „keine Meldung" heißt: Der Zug sollte planmäßig da
sein, war nicht ausgefallen — und trotzdem kam keine Ist-Zeit. Nur bei dieser letzten
Spalte bedeutet ein Anstieg ein Problem der Erhebung.

## Je Linie

```sql je_linie
select
    linie,
    sum(fahrten)             as fahrten,
    sum(fahrten_ausgefallen)      as ausgefallen,
    sum(fahrten_unbedienter_lauf)              as unbedient,
    sum(fahrten_unbedienter_lauf_bestaetigt)   as unbedient_belegt,
    sum(fahrten_unbedienter_lauf_nicht_pruefbar) as unbedient_ungeprueft,
    sum(fahrten_verkuerzt)                     as verkuerzt,
    sum(halte_mit_ankunft)   as halte,
    100.0 * sum(halte_puenktlich) / nullif(sum(halte_gemessen), 0)    as quote_gemessen,
    100.0 * sum(halte_puenktlich) / nullif(sum(halte_mit_ankunft), 0) as quote_planmaessig
from bahnpuls.puenktlichkeit
where schwelle_min = ${inputs.schwelle}
  and verkehrsart like '${inputs.verkehrsart}'
  and gattung in ${inputs.gattung.value}
group by linie
order by halte desc, linie
```

<DataTable data={je_linie} rows=15 search=true emptySet=warn
    emptyMessage="Zu dieser Auswahl fuhr im Zeitraum keine Linie. Stell die Verkehrsart auf „Alle“ oder nimm eine Gattung dazu.">
    <Column id=linie title="Linie" />
    <Column id=fahrten title="Fahrten" />
    <Column id=ausgefallen title="Ausfall gemeldet" />
    <Column id=unbedient title="kein Halt bedient" />
    <Column id=unbedient_belegt title="davon am Fahrplan belegt" />
    <Column id=unbedient_ungeprueft title="davon nicht prüfbar" />
    <Column id=verkuerzt title="davon gekappt" />
    <Column id=halte title="planmäßige Halte" />
    <Column id=quote_gemessen title="pünktlich, gefahrene (%)" fmt='#,##0.0' />
    <Column id=quote_planmaessig title="pünktlich, planmäßige (%)" fmt='#,##0.0' />
</DataTable>

Beide Quoten bei der oben gewählten Grenze von <Value data={gewaehlte_schwelle} column=schwelle_min/>
Minuten. Linien mit wenigen Halten stehen unten — bei
kleiner Grundmenge schwankt eine Quote stark, und eine Rangliste über solche Werte wäre
Zufall mit Nachkommastellen.

„Davon am Fahrplan belegt" heißt: der beobachtete Laufweg deckt den planmäßigen
vollständig ab, es wurde also nicht bloß ein gestrichenes Ende gesehen.

„Davon nicht prüfbar" ist die Gegenprobe dazu. Für diese Fahrten gibt es **überhaupt
keinen** Soll-Laufweg: Ihre Kennung kommt in keiner zum Betriebstag gültigen
Fahrplan-Version vor. Sie sind weder belegt noch widerlegt.

<Details title="Warum es diese dritte Spalte gibt">

Bis zum 22.08.2026 zählten diese Fahrten stillschweigend als „nicht belegt". Weil dieselbe
Quelle auch den Liniennamen liefert, traf das ausschließlich Fahrten ohne Liniennummer:
Über drei Betriebstage war dort **keine einzige** von 182 belegt, bei Fahrten mit
Liniennummer dagegen 97,6 bis 100 %.

Der Unterschied zwischen zwei Betriebstagen (84,4 % gegen 61,3 % belegt) bestand
vollständig daraus, wie groß diese Gruppe an dem Tag war. Er sagte nichts über den Betrieb.
Was die drei Spalten offen lassen, ist seither sichtbar statt eingerechnet.

Für Betriebstage vor der ersten Fahrplan-Ladung lässt sich ohnehin nichts belegen. Die
Aufzeichnung läuft erst seit dem 19.08.2026.

</Details>

**Diese Seite lässt sich verlinken.** Deine Auswahl steht in der Adresse
(`?art=…&gattung=…&schwelle=…`) und lässt sich so zitieren.

<Alert status=info>

**Zwei Grenzen dieser Seite, ausdrücklich.** Erstens: der Nenner ist der **beobachtete**
Laufweg, nicht der Fahrplan. Ein Zug, der komplett ausfiel und über den der Feed nur eine
Meldung über die ganze Fahrt schickte, fehlt auch hier — beide Quoten sind damit obere
Schranken und können nur besser aussehen als die Wirklichkeit, nie schlechter. Wie groß
diese Lücke bei den deutschen Daten derzeit ist, steht im Kasten weiter oben: sie umfasst
**sämtliche** Ausfälle. Zweitens: gezeigt werden die letzten 30 aufgezeichneten
Betriebstage.

Wie die Zahlen im Einzelnen zustande kommen, steht auf der Seite [Methodik](/methodik).

</Alert>

---

Daten von [gtfs.de](https://gtfs.de) (CC BY-SA 4.0 bzw. CC BY 4.0) — vollständige
Angaben unter [Lizenz und Quellen](/lizenz) · [Impressum](/impressum) ·
[Datenschutz](/datenschutz)
