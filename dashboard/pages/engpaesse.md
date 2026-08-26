---
title: Engpässe im Netz
description: Wo je Zug die meiste Verspätung neu entsteht — nach Abschnitt, Tagesstunde und Fahrtrichtung
sidebar_position: 5
---

**Diese Seite zeigt, auf welchen Streckenabschnitten Züge immer wieder Zeit verlieren.**

Die Seite [Laufweg einer Fahrt](/laufweg) zeigt eine einzelne Fahrt. Diese hier legt viele
übereinander.

**Gerechnet wird je Zug, nie als Summe.** Ohne diese Regel wäre das Ergebnis wertlos: Eine
Summe setzt zwangsläufig den dichtest befahrenen Abschnitt nach oben. Der hat schlicht mehr
Züge, nicht mehr Probleme.

```sql gattungen
-- Nur die Auswahlliste: welche Verkehrsarten und Gattungen auf **dieser** Seite
-- vorkommen (ADR-014).
select verkehrsart, gattung
from bahnpuls.engpassknoten
group by verkehrsart, gattung
```

<Auswahlleiste data={gattungen} hinweis="Die Mindestzahl Züge steht darunter." />

<!--
`${inputs.mindestzuege}` steht in den Abfragen ohne `.value` -- Begruendung siehe
`puffer.md` an derselben Stelle: der `Slider` legt seinen Wert roh ab, `.value` waere
`undefined` und die Abfrage liefe nie (BPULS-084).
-->
<AdresseMerken eingabe="mindestzuege" parameter="mindest" vorgabe={5} zahl=true let:vorauswahl>
<Slider
    name=mindestzuege
    title="Mindestzahl Züge je Abschnitt"
    min=1
    max=50
    step=1
    defaultValue={vorauswahl}
/>
</AdresseMerken>

```sql abschnitte
select
    von_bezeichnung || ' → ' || nach_bezeichnung as abschnitt,
    von_bezeichnung,
    nach_bezeichnung,
    abschnitt_paar,
    richtung_hin,
    bool_and(bezeichnung_vollstaendig) as namen_bekannt,
    sum(zuege)                         as zuege,
    -- Über Stunden hinweg wird aus Summe und Zähler neu gerechnet, nicht über
    -- Stundenmittel gemittelt: sonst zählte die Stunde mit zwei Zügen so viel wie die
    -- mit vierzig.
    sum(laufzeit_summe)  / nullif(sum(laufzeit_messwerte), 0)  as laufzeit_je_zug,
    sum(haltezeit_summe) / nullif(sum(haltezeit_messwerte), 0) as haltezeit_je_zug,
    sum(laufzeit_messwerte)  as laufzeit_messwerte,
    sum(ausgefallene_halte)  as ausgefallene_halte,
    sum(ausgelassene_halte)  as ausgelassene_halte
from bahnpuls.engpassknoten
where verkehrsart like '${inputs.verkehrsart}'
  and gattung in ${inputs.gattung.value}
group by all
```

## Die Abschnitte, auf denen am meisten dazukommt

```sql rangliste
select
    abschnitt,
    zuege,
    round(laufzeit_je_zug / 60.0, 2)  as laufzeit_min,
    round(haltezeit_je_zug / 60.0, 2) as haltezeit_min,
    laufzeit_messwerte,
    namen_bekannt,
    ausgefallene_halte,
    ausgelassene_halte
from ${abschnitte}
where laufzeit_je_zug is not null
  and zuege >= ${inputs.mindestzuege}
order by laufzeit_je_zug desc
limit 10
```

**So liest du die Tabelle.** Die Spalte „unterwegs dazu" zeigt, was ein Zug auf diesem
Abschnitt im Mittel verliert. Der Balken läuft nach rechts, wenn Zeit **dazukam**, und nach
links, wenn welche **aufgeholt** wurde. Ein Wert nach links ist kein Fehler: Dort steckt
Reserve im Fahrplan, und genau dafür ist sie da.

Die Spalte „davon messbar" steht bewusst neben der Zugzahl. Der Durchschnitt wird über die
Fahrten gebildet, für die sich der Wert **tatsächlich bestimmen ließ**, nicht über alle.
Liegen die beiden Zahlen weit auseinander, beruht der Mittelwert auf weniger Beobachtung,
als die Zugzahl vermuten lässt.

<DataTable data={rangliste} rows=10 emptySet=warn
    emptyMessage="Kein Abschnitt erreicht die eingestellte Mindestzahl Züge. Zieh den Regler nach links, oder stell die Verkehrsart oben auf „Alle“.">
    <Column id=abschnitt title="Abschnitt" />
    <Column id=zuege title="Züge" />
    <Column id=laufzeit_min title="unterwegs dazu (Min./Zug)" fmt='#,##0.00' contentType=bar barColor=verloren negativeBarColor=aufgeholt />
    <Column id=laufzeit_messwerte title="davon messbar" />
    <Column id=haltezeit_min title="im Bahnhof dazu (Min./Zug)" fmt='#,##0.00' />
    <Column id=ausgefallene_halte title="Ausfälle" />
    <Column id=ausgelassene_halte title="ausgelassen" />
    <Column id=namen_bekannt title="Namen bekannt" />
</DataTable>

**Der Schieberegler ist kein Zierrat.** Ein Abschnitt, über den drei Züge gefahren sind,
kann rechnerisch an der Spitze stehen, ohne dass das etwas bedeutet — ein einzelner
gestörter Zug reicht dafür. Je höher die Mindestzahl, desto belastbarer die Reihenfolge und
desto kürzer die Liste. Unter etwa fünf Zügen ist ein Mittelwert Zufall mit
Nachkommastellen.

## Wann es klemmt

```sql heatmap
select
    von_bezeichnung || ' → ' || nach_bezeichnung as abschnitt,
    stunde,
    sum(laufzeit_summe) / nullif(sum(laufzeit_messwerte), 0) / 60.0 as laufzeit_min,
    sum(zuege) as zuege
from bahnpuls.engpassknoten
where stunde is not null
  and verkehrsart like '${inputs.verkehrsart}'
  and gattung in ${inputs.gattung.value}
group by all
having sum(laufzeit_messwerte) > 0
```

```sql heatmap_top
-- `order by` qualifiziert: beide Seiten des Joins fuehren `abschnitt`, unqualifiziert ist
-- der Bezug mehrdeutig und DuckDB bricht ab. Aufgefallen ist das erst, als die Abfrage
-- ueberhaupt zum Laufen kam -- sie haengt ueber `rangliste` an der Schiebereglereingabe
-- und wurde vorher gar nicht erst ausgefuehrt (BPULS-084).
select h.*
from ${heatmap} h
join (
    select abschnitt from ${rangliste}
) auswahl on auswahl.abschnitt = h.abschnitt
order by h.abschnitt, h.stunde
```

**So liest du die Grafik.** Jede Zeile ist ein Abschnitt aus der Rangliste oben, jede
Spalte eine Stunde des Tages. Je dunkler ein Feld, desto mehr Zeit kam dort im Mittel
dazu.

Leere Felder heißen: In dieser Stunde fuhr dort kein Zug, oder es lag kein Messwert vor.
Sie sind **nicht** als Null zu lesen.

Die Farbe ist eine Rangfolge **innerhalb dieser Grafik**. Sie läuft vom kleinsten zum
größten Wert der gezeigten Auswahl. Ein Nullpunkt steckt nicht darin: Ob auf einem Feld
aufgeholt wurde, steht in der Zahl und nicht in der Farbe. Eine Skala mit fester Null
bräuchte feste Grenzen, und die würden mit den Daten nicht mitwandern.

<Heatmap
    data={heatmap_top}
    x=stunde
    y=abschnitt
    value=laufzeit_min
    valueFmt='#,##0.0'
    title="Unterwegs neu entstandene Verspätung je Zug (Minuten), nach Tagesstunde"
    colorScale=verlust
    emptySet=warn
    emptyMessage="Zur Rangliste darüber gibt es keine Stundenwerte. Zieh den Regler nach links, oder stell die Verkehrsart oben auf „Alle“."
/>

Die Stunde ist die **planmäßige Ankunftszeit** am Ende des Abschnitts, als Uhrzeit gelesen.
Ein Nachtzug, der um 01:30 ankommt, steht deshalb bei Stunde 1 — und gehört trotzdem zum
Betriebstag davor. Für die Frage, wann im Tagesverlauf eine Strecke klemmt, ist genau das
die richtige Zuordnung.

## Fährt es in eine Richtung schlechter?

```sql richtungen
select
    abschnitt_paar,
    max(case when richtung_hin then laufzeit_je_zug end) / 60.0     as hin_min,
    max(case when not richtung_hin then laufzeit_je_zug end) / 60.0 as rueck_min,
    min(zuege)                                                      as zuege_schwaechere_richtung
from ${abschnitte}
group by abschnitt_paar
having count(*) = 2
   and max(case when richtung_hin then laufzeit_je_zug end) is not null
   and max(case when not richtung_hin then laufzeit_je_zug end) is not null
```

```sql asymmetrie
select
    abschnitt_paar,
    round(hin_min, 2)               as hin_min,
    round(rueck_min, 2)             as rueck_min,
    round(abs(hin_min - rueck_min), 2) as unterschied_min,
    zuege_schwaechere_richtung
from ${richtungen}
where zuege_schwaechere_richtung >= ${inputs.mindestzuege}
order by abs(hin_min - rueck_min) desc
limit 10
```

<DataTable data={asymmetrie} rows=10 emptySet=warn
    emptyMessage="Kein Abschnitt ist in beiden Richtungen oft genug befahren worden. Zieh den Regler nach links, oder stell die Verkehrsart oben auf „Alle“.">
    <Column id=abschnitt_paar title="Abschnitt (beide Richtungen)" />
    <Column id=hin_min title="Richtung A→B (Min./Zug)" fmt='#,##0.00' />
    <Column id=rueck_min title="Richtung B→A (Min./Zug)" fmt='#,##0.00' />
    <Column id=unterschied_min title="Unterschied" fmt='#,##0.00' />
    <Column id=zuege_schwaechere_richtung title="Züge (schwächere Richtung)" />
</DataTable>

Ein Abschnitt, auf dem es in eine Richtung deutlich schlechter läuft als in die andere, ist
ein anderer Befund als ein Abschnitt, der insgesamt langsam ist. Bei einer zweigleisigen
Strecke sind beide Richtungen weitgehend unabhängig. Ein einseitiger Unterschied deutet
deshalb eher auf die Fahrplanlage hin — Kreuzungen, Überholungen, knappe Anschlüsse in eine
Richtung — als auf die Infrastruktur selbst.

Das ist ein **Hinweis, keine Diagnose.** Woran es liegt, sagen diese Daten nicht; dafür
braucht es Streckenkenntnis und den Fahrplan.

**Diese Seite lässt sich verlinken.** Deine Auswahl steht in der Adresse
(`?art=…&gattung=…&mindest=…`) und lässt sich so zitieren.

<Alert status=info>

**Drei Grenzen dieser Seite.** Erstens: gezeigt werden die **200 meistbefahrenen**
Abschnitte der letzten 30 Betriebstage. Ausgewählt wird nach Verkehrsmenge, nicht nach
Verspätung — andersherum wäre der Ausschnitt zirkulär und jede Zahl darin sähe schlimmer
aus, als sie ist. Der Preis: **ein Engpass auf einer wenig befahrenen Strecke taucht hier
nicht auf.**

Zweitens: Abschnitte werden über den **Bahnhofsnamen** zusammengefasst. Wo kein Name
bekannt ist, steht die Haltestellen-ID, und derselbe Bahnhof kann dann unter mehreren IDs
mehrfach erscheinen — die Spalte „Namen bekannt" in der Rangliste zeigt das an.

Drittens: die Auswahl oben trennt Fern- von Nahverkehr und darin die Zuggattungen. Sie
wird **nicht** aus dem Liniennamen geraten — die Verkehrsart kommt aus der Fahrplandatei,
in der die Fahrt steht, die Gattung aus dem Anfang des Liniennamens. Wo der Fahrplan eine
Fahrt gar nicht kennt, steht **ohne Angabe**; diese Gruppe ist in „Alle“ enthalten und
fällt bei *Nahverkehr* oder *Fernverkehr* heraus. Wie groß sie ist, steht auf der Seite
[Methodik](/methodik).

</Alert>

---

Daten von [gtfs.de](https://gtfs.de) (CC BY-SA 4.0 bzw. CC BY 4.0) — vollständige
Angaben unter [Lizenz und Quellen](/lizenz) · [Impressum](/impressum) ·
[Datenschutz](/datenschutz)
