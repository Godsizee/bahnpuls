---
title: Bahnhöfe
description: Je eine Seite für die größeren Knoten in VRN und Rhein-Main — wie zuverlässig ein Zug dort ankommt und wie viel Verspätung der Halt selbst kostet
sidebar_position: 3
---

Die übrigen Seiten fragen nach Linien, Fahrten und Abschnitten. Diese fragt nach dem Ort:
**Wie zuverlässig kommt ein Zug an diesem Bahnhof an — und wie viel Verspätung entsteht
dort, wo er steht?**

```sql knoten
select
    bahnhof,
    verbund,
    '/bahnhof/' || slug                        as seite,
    count(distinct betriebstag)                as tage,
    sum(zuege)                                 as zuege,
    sum(halte_mit_ankunft)                     as halte,
    100.0 * sum(halte_puenktlich)
          / nullif(sum(halte_mit_ankunft), 0)  as quote_planmaessig,
    -- Über mehrere Tage aus Summe und Zähler neu gerechnet, nicht aus Mittelwerten
    -- gemittelt: sonst zählte ein ruhiger Sonntag so viel wie ein Werktag.
    sum(haltezeit_delta_sek_summe)
          / nullif(sum(haltezeit_messwerte), 0) as hier_sek

from bahnpuls.bahnhof
where schwelle_sek = 360
group by bahnhof, verbund, slug
order by verbund, bahnhof
```

<DataTable data={knoten} rows=15 search=true emptySet=warn
    emptyMessage="Für keinen Knoten liegen Zahlen vor — vermutlich ist der letzte Datenlauf nicht durchgelaufen.">
    <Column id=seite title="Bahnhof" contentType=link linkLabel=bahnhof />
    <Column id=verbund title="Verbund" />
    <Column id=zuege title="Züge" fmt="#,##0" />
    <Column id=halte title="Halte mit Ankunft" fmt="#,##0" wrapTitle=true />
    <Column id=quote_planmaessig title="pünktlich (6 Min.) %" fmt="#,##0.0" wrapTitle=true />
    <Column id=hier_sek title="im Bahnhof (s je Halt)" fmt="#,##0.0" wrapTitle=true contentType=bar barColor=verloren negativeBarColor=aufgeholt />
</DataTable>

**So liest sich die letzte Spalte.** Der Balken läuft nach rechts, wenn der Aufenthalt
Zeit **gekostet** hat, und nach links, wenn der Zug am Bahnsteig welche **aufgeholt** hat.
Die Null liegt in jeder Zeile an derselben Stelle — eine aufgeholte halbe Minute sieht
damit anders aus als eine verlorene, nicht nur blasser.

## Warum eine Auswahl und nicht jeder Halt

Der Feed nennt im Zielgebiet mehrere hundert Betriebsstellen beim Namen — von der
Frankfurter Stammstrecke bis zum Haltepunkt mit einer Handvoll Züge am Tag. Jede von ihnen
bekäme eine Seite, die niemand aufruft, und der Browser müsste für jeden Aufruf mehr Daten
laden.

Die Auswahl steht deshalb als Liste im Projekt und nicht als Bestenliste in den Daten. Das
ist keine Bequemlichkeit, sondern hat zwei Gründe:

- **Eine Bestenliste nach Verkehrsmenge wäre keine Auswahl über das Gebiet.** Die
  meistbefahrenen Halte liegen fast alle auf der Frankfurter Stammstrecke. Eine Seite je
  Bahnhof soll auch den Knoten zeigen, an dem jemand tatsächlich wartet.
- **Ein Link soll gelten.** Die Adresse einer Bahnhofsseite ist zitierbar. Käme die
  Auswahl aus den Daten, verschwände eine Seite in dem Moment, in dem ihr Bahnhof aus der
  Rangliste fällt.

Fehlt ein Bahnhof, der hierher gehört, ist das eine Zeile in der Liste — keine Änderung an
einer Kennzahl.

## Was auf diesen Seiten steht

Jede Bahnhofsseite trennt drei Dinge, die eine gewöhnliche Pünktlichkeitsstatistik in eine
Zahl wirft:

- **Mitgebracht** — mit welchem Rückstand die Züge ankommen. Das sagt etwas über die
  Strecke davor, nicht über den Bahnhof.
- **Hier entstanden** — was der Aufenthalt selbst kostet, gerechnet als Unterschied
  zwischen Ankunfts- und Abfahrtsverspätung.
- **Auf dem Weg hierher entstanden** — was der letzte Abschnitt vor der Einfahrt gekostet
  hat.

Dazu die beiden Pünktlichkeitsquoten nebeneinander: die übliche, die nur zählt, was
gemessen wurde, und die, in der auch Ausfälle und ausgelassene Halte im Nenner stehen. Wie
beides gerechnet wird, steht auf der [Methodik-Seite](/methodik).

**Alle Zahlen stehen auf den letzten 30 Betriebstagen** und auf einer Sammlung, die am
19.08.2026 begonnen hat. Für Aussagen über einen einzelnen Bahnhof über die Zeit ist das
kurz — man sieht Tage, keine Regelmäßigkeit.
