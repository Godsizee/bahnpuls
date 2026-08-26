---
title: Fahrplanreserve
description: Wo Zuschläge wirken, wo sie fehlen und wo sie brachliegen
sidebar_position: 6
---

**Diese Seite zeigt, wo die eingeplante Reserve im Fahrplan wirkt, wo sie fehlt und wo sie
ungenutzt liegen bleibt.**

In jedem Fahrplan steckt Reserve. Die Fahrzeit zwischen zwei Bahnhöfen ist etwas länger
angesetzt, als ein Zug bei freier Fahrt bräuchte. Und der Aufenthalt dauert etwas länger,
als Ein- und Aussteigen brauchen.

Diese Zuschläge sind kein Schlendrian. Sie sind das Werkzeug, mit dem kleine Störungen
wieder eingefangen werden. Ohne sie schlüge jede Anschlussverzögerung bis zum Endbahnhof
durch.

**Ein Zug, der früher ankommt, ist deshalb kein Datenfehler.** Er hat Reserve gezogen.

```sql gattungen
-- Nur die Auswahlliste: welche Verkehrsarten und Gattungen auf **dieser** Seite
-- vorkommen (ADR-014).
select verkehrsart, gattung
from bahnpuls.pufferbilanz
group by verkehrsart, gattung
```

<Auswahlleiste data={gattungen} hinweis="Die Mindestzahl Durchfahrten steht darunter." />

<!--
Der Wert steht unten als `${inputs.mindestfahrten}` in den Abfragen, **ohne** `.value` --
anders als bei den Auswahllisten auf der Laufweg-Seite. Das ist kein Tippfehler:
`Slider` schreibt seinen Wert ueber den veralteten `getInputContext()` roh in den
Eingabespeicher, ohne die `{value, label}`-Huelle, die `Dropdown` ueber `getInputSetter`
anlegt. `.value` ist darauf `undefined`; der uebersetzte Seitencode setzt daraufhin
`noResolve` und fuehrt die Abfrage **nie** aus. Die Seite bleibt dann im gebauten Stand
bei ihren Ladekaesten stehen -- HTTP 200, richtiger Titel, keine Konsolenmeldung
(BPULS-084).
-->
<AdresseMerken eingabe="mindestfahrten" parameter="mindest" vorgabe={10} zahl=true let:vorauswahl>
<Slider
    name=mindestfahrten
    title="Mindestzahl bewertbarer Durchfahrten"
    min=1
    max=100
    step=1
    defaultValue={vorauswahl}
/>
</AdresseMerken>

```sql abschnitte
select
    von_bezeichnung || ' → ' || nach_bezeichnung as abschnitt,
    linie,
    bewertbar,
    verloren,
    aufgeholt,
    verspaetet_eingefahren,
    puenktlich_eingefahren,
    reserve_genutzt,
    reserve_ungenutzt,
    round(verlust_sek / 60.0, 1)           as verlust_min,
    round(reserve_genutzt_sek / 60.0, 1)   as genutzt_min,
    round(reserve_ungenutzt_sek / 60.0, 1) as ungenutzt_min,
    bezeichnung_vollstaendig,
    100.0 * verloren / nullif(bewertbar, 0)                        as verloren_anteil,
    100.0 * reserve_genutzt / nullif(verspaetet_eingefahren, 0)    as genutzt_anteil,
    100.0 * reserve_ungenutzt / nullif(puenktlich_eingefahren, 0)  as ungenutzt_anteil
from bahnpuls.pufferbilanz
where bewertbar >= ${inputs.mindestfahrten}
  and verkehrsart like '${inputs.verkehrsart}'
  and gattung in ${inputs.gattung.value}
```

## Wo die Fahrzeit zu knapp bemessen ist

```sql zu_knapp
select abschnitt, linie, bewertbar, verloren, round(verloren_anteil, 1) as verloren_anteil,
       verlust_min, bezeichnung_vollstaendig
from ${abschnitte}
where verloren_anteil is not null
order by verloren_anteil desc, verlust_min desc
limit 10
```

**So liest du die Tabelle.** „Davon mit Zeitverlust" ist der Anteil der Durchfahrten, bei
denen der Zug auf diesem Abschnitt Zeit verloren hat. Je dunkler das Feld, desto häufiger
passiert das. Verliert dort fast jeder Zug Zeit, ist die angesetzte Fahrzeit zu knapp.

<DataTable data={zu_knapp} rows=10 emptySet=warn
    emptyMessage="Kein Abschnitt erreicht die eingestellte Mindestzahl Durchfahrten. Zieh den Regler nach links, oder stell die Verkehrsart oben auf „Alle“.">
    <Column id=abschnitt title="Abschnitt" />
    <Column id=linie title="Linie" />
    <Column id=bewertbar title="Durchfahrten" />
    <Column id=verloren_anteil title="davon mit Zeitverlust (%)" fmt='#,##0.0' contentType=colorscale colorScale=verlust colorMin={0} colorMax={100} />
    <Column id=verlust_min title="verlorene Zeit gesamt (Min.)" fmt='#,##0.0' />
    <Column id=bezeichnung_vollstaendig title="Namen bekannt" />
</DataTable>

Das gilt unabhängig davon, ob die Züge verspätet oder pünktlich hineinfahren. Das ist der
Befund, an dem eine Fahrplanänderung ansetzen würde.

Die Farbe läuft in beiden Tabellen von 0 auf 100 %, nicht vom kleinsten zum größten Wert
der jeweiligen Liste. Sonst sähe die harmloseste Zeile einer schlechten Liste aus wie ein
Nullwert, und die beiden Tabellen ließen sich nicht nebeneinanderlegen.

## Wo Reserve wirkt

```sql wirkt
select abschnitt, linie, verspaetet_eingefahren, reserve_genutzt,
       round(genutzt_anteil, 1) as genutzt_anteil, genutzt_min
from ${abschnitte}
where genutzt_anteil is not null
  and verspaetet_eingefahren >= ${inputs.mindestfahrten}
order by genutzt_anteil desc, genutzt_min desc
limit 10
```

**Hier ist ein hoher Wert gut.** Er zählt Züge, die verspätet in den Abschnitt einfuhren
und dort Verspätung abgebaut haben. Genau dafür ist der Zuschlag da. Im Nenner stehen nur
die verspätet eingefahrenen Züge — pünktliche können nichts aufholen, was sie nicht haben.

<DataTable data={wirkt} rows=10 emptySet=warn
    emptyMessage="Kein Abschnitt hat so viele verspätet eingefahrene Züge. Zieh den Regler nach links, oder stell die Verkehrsart oben auf „Alle“.">
    <Column id=abschnitt title="Abschnitt" />
    <Column id=linie title="Linie" />
    <Column id=verspaetet_eingefahren title="verspätet eingefahren" />
    <Column id=reserve_genutzt title="davon aufgeholt" />
    <Column id=genutzt_anteil title="Anteil (%)" fmt='#,##0.0' contentType=colorscale colorScale=aufholung colorMin={0} colorMax={100} />
    <Column id=genutzt_min title="abgebaute Verspätung (Min.)" fmt='#,##0.0' />
</DataTable>

## Wo Reserve brachliegt

```sql brach
select abschnitt, linie, puenktlich_eingefahren, reserve_ungenutzt,
       round(ungenutzt_anteil, 1) as ungenutzt_anteil, ungenutzt_min
from ${abschnitte}
where ungenutzt_anteil is not null
  and puenktlich_eingefahren >= ${inputs.mindestfahrten}
order by ungenutzt_anteil desc, ungenutzt_min desc
limit 10
```

**So liest du die Tabelle.** Sie beschreibt den umgekehrten Fall: Züge, die **pünktlich** in
den Abschnitt einfuhren und trotzdem früher ankamen. Sie brauchten den Zuschlag nicht.

<DataTable data={brach} rows=10 emptySet=warn
    emptyMessage="Kein Abschnitt hat so viele pünktlich eingefahrene Züge. Zieh den Regler nach links, oder stell die Verkehrsart oben auf „Alle“.">
    <Column id=abschnitt title="Abschnitt" />
    <Column id=linie title="Linie" />
    <Column id=puenktlich_eingefahren title="pünktlich eingefahren" />
    <Column id=reserve_ungenutzt title="davon noch früher" />
    <Column id=ungenutzt_anteil title="Anteil (%)" fmt='#,##0.0' />
    <Column id=ungenutzt_min title="gewonnene Zeit (Min.)" fmt='#,##0.0' />
</DataTable>

Ein hoher Anteil heißt: Die Fahrzeit ist großzügiger bemessen als nötig. Der Zug steht dann
am nächsten Halt und wartet, und die Trasse ist für andere blockiert.

**Dieselbe Beobachtung, zwei gegensätzliche Befunde.** In beiden Tabellen wird ein Zug
schneller als geplant. Ob das gut oder schlecht ist, entscheidet allein eine Frage: mit
welcher Verspätung er eingefahren ist. Eine gemeinsame Kennzahl „Anteil aufholender Züge"
nähme für beide Fälle denselben Wert an und wäre damit wertlos.

## Aufholvermögen und Störungsanfall je Linie

```sql linien
select
    linie,
    zuege,
    bewertbar,
    100.0 * verloren / nullif(bewertbar, 0)                     as stoerungsanfall,
    100.0 * reserve_genutzt / nullif(verspaetet_eingefahren, 0) as aufholvermoegen,
    verspaetet_eingefahren,
    round(bilanz_sek / 60.0, 1) as bilanz_min
from bahnpuls.puffer_linien
where bewertbar >= ${inputs.mindestfahrten}
  and verspaetet_eingefahren > 0
  and verkehrsart like '${inputs.verkehrsart}'
  and gattung in ${inputs.gattung.value}
order by linie
```

**So liest du die Grafik.** Nach rechts wächst der Störungsanfall: wie oft eine Linie Zeit
verliert. Nach oben wächst das Aufholvermögen: wie oft sie eine Verspätung wieder
einfängt. Links oben steht die angenehme Lage, rechts unten die unangenehme.

<ScatterPlot
    data={linien}
    x=stoerungsanfall
    y=aufholvermoegen
    series=linie
    xAxisTitle="Störungsanfall: Anteil der Durchfahrten mit Zeitverlust (%)"
    yAxisTitle="Aufholvermögen: Anteil der verspäteten Züge, die aufholen (%)"
    title="Je Linie, über alle Abschnitte"
    emptySet=warn
    emptyMessage="Keine Linie erreicht die eingestellte Mindestzahl Durchfahrten. Zieh den Regler nach links, oder stell die Verkehrsart oben auf „Alle“."
/>

Rechts unten heißt: häufiger Zeitverlust bei geringem Aufholvermögen. Dort schleppt sich
eine Verspätung bis zum Ende durch.

Anders als die Abschnittstabellen rechnet diese Auswertung über **alle** Abschnitte einer
Linie, nicht nur über die meistbefahrenen. Eine Linie nur auf ihrem dichtesten Teil zu
beurteilen hieße, ausgerechnet die Nebenstrecke wegzulassen, auf der es klemmt.

**Diese Seite lässt sich verlinken.** Deine Auswahl steht in der Adresse
(`?art=…&gattung=…&mindest=…`) und lässt sich so zitieren.

<Alert status=info>

**Grenzen dieser Seite.** Die Abschnittstabellen zeigen die **200 meistbefahrenen**
Abschnitte der letzten 30 Betriebstage; ausgewählt wird nach Verkehrsmenge, nicht nach
Befund, sonst wäre der Ausschnitt zirkulär. Die Liniengrafik ist davon nicht betroffen.

Als „pünktlich eingefahren" gilt eine Eingangsverspätung von höchstens **60 Sekunden**.
Diese Grenze entscheidet, in welche der beiden Tabellen ein Zug fällt; sie ist eine
Annahme und steht auf der Seite [Methodik](/methodik).

Was hier **nicht** steht: die Haltezeitreserve. Ausgewertet wird der Laufzeitanteil
zwischen zwei Bahnhöfen, nicht der Aufenthalt im Bahnhof.

</Alert>

---

Daten von [gtfs.de](https://gtfs.de) (CC BY-SA 4.0 bzw. CC BY 4.0) — vollständige
Angaben unter [Lizenz und Quellen](/lizenz) · [Impressum](/impressum) ·
[Datenschutz](/datenschutz)
