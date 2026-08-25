---
title: Bahnpuls
description: Wo Verspätung im Schienenverkehr entsteht — auf der Strecke oder im Bahnhof
sidebar_position: 1
---

Ein Zug kommt zwölf Minuten zu spät an. Das steht in jeder Statistik. Was nirgends steht:
**wo diese zwölf Minuten entstanden sind.** Standen sie schon beim Start? Kamen sie auf
einem bestimmten Streckenabschnitt dazu? Oder sammelten sie sich in kleinen Portionen an
sechs Bahnhöfen, weil überall der Aufenthalt zu knapp bemessen ist?

Das sind drei völlig verschiedene Probleme mit drei verschiedenen Antworten, und wer nur
die Ankunftsverspätung kennt, kann sie nicht auseinanderhalten. **Bahnpuls hält sie
auseinander** — Halt für Halt, für jede Fahrt in VRN und RMV.

<div style="overflow-x:auto; margin:1.75rem 0 1.25rem;">
<svg viewBox="0 0 720 290" role="img" aria-label="Schematischer Verlauf einer Fahrt über vier Halte: Die Verspätung wächst auf zwei Abschnitten und während zweier Aufenthalte, auf einem Abschnitt wird Zeit aufgeholt. Am Ziel stehen zwölf Minuten, davon sieben unterwegs und fünf im Bahnhof entstanden." style="width:100%; min-width:620px; height:auto; font-family:inherit;">
<line x1="80" y1="240" x2="700" y2="240" style="stroke:var(--base-content-muted, #71717a)" stroke-width="1" stroke-dasharray="3 4" />
<line x1="74" y1="160" x2="80" y2="160" style="stroke:var(--base-content-muted, #71717a)" stroke-width="1" />
<line x1="74" y1="80" x2="80" y2="80" style="stroke:var(--base-content-muted, #71717a)" stroke-width="1" />
<text x="80" y="26" text-anchor="start" font-size="12" style="fill:var(--base-content-muted, #71717a)">Verspätung gegenüber Fahrplan (Minuten)</text>
<text x="68" y="240" dy="0.32em" text-anchor="end" font-size="12" style="fill:var(--base-content-muted, #71717a)">0</text>
<text x="68" y="160" dy="0.32em" text-anchor="end" font-size="12" style="fill:var(--base-content-muted, #71717a)">5</text>
<text x="68" y="80" dy="0.32em" text-anchor="end" font-size="12" style="fill:var(--base-content-muted, #71717a)">10</text>
<line x1="300" y1="164" x2="300" y2="236" style="stroke:var(--base-content-muted, #71717a)" stroke-width="1" stroke-dasharray="2 4" opacity="0.55" />
<line x1="490" y1="164" x2="490" y2="236" style="stroke:var(--base-content-muted, #71717a)" stroke-width="1" stroke-dasharray="2 4" opacity="0.55" />
<line x1="660" y1="52" x2="660" y2="236" style="stroke:var(--base-content-muted, #71717a)" stroke-width="1" stroke-dasharray="2 4" opacity="0.55" />
<line x1="110" y1="240" x2="300" y2="160" style="stroke:var(--verloren-stark, #8f3d56)" stroke-width="3" stroke-linecap="round" />
<line x1="300" y1="160" x2="300" y2="128" style="stroke:var(--verloren-stark, #8f3d56)" stroke-width="3" stroke-linecap="round" />
<line x1="300" y1="128" x2="490" y2="160" style="stroke:var(--aufgeholt-stark, #236aa4)" stroke-width="3" stroke-linecap="round" />
<line x1="490" y1="160" x2="490" y2="112" style="stroke:var(--verloren-stark, #8f3d56)" stroke-width="3" stroke-linecap="round" />
<line x1="490" y1="112" x2="660" y2="48" style="stroke:var(--verloren-stark, #8f3d56)" stroke-width="3" stroke-linecap="round" />
<circle cx="110" cy="240" r="4" style="fill:var(--base-content, #27272a)" />
<circle cx="660" cy="48" r="5" style="fill:var(--verloren-stark, #8f3d56)" />
<text x="205" y="186" text-anchor="middle" font-size="13" style="fill:var(--verloren-stark, #8f3d56)">+5 unterwegs</text>
<text x="292" y="148" text-anchor="end" font-size="13" style="fill:var(--verloren-stark, #8f3d56)">+2 im Halt</text>
<text x="395" y="132" text-anchor="middle" font-size="13" style="fill:var(--aufgeholt-stark, #236aa4)">−2 aufgeholt</text>
<text x="502" y="140" text-anchor="start" font-size="13" style="fill:var(--verloren-stark, #8f3d56)">+3 im Halt</text>
<text x="555" y="58" text-anchor="middle" font-size="13" style="fill:var(--verloren-stark, #8f3d56)">+4 unterwegs</text>
<text x="660" y="28" text-anchor="middle" font-size="14" font-weight="600" style="fill:var(--verloren-stark, #8f3d56)">+12</text>
<text x="110" y="264" text-anchor="middle" font-size="12.5" style="fill:var(--base-content, #27272a)">Start</text>
<text x="300" y="264" text-anchor="middle" font-size="12.5" style="fill:var(--base-content, #27272a)">Halt 1</text>
<text x="490" y="264" text-anchor="middle" font-size="12.5" style="fill:var(--base-content, #27272a)">Halt 2</text>
<text x="660" y="264" text-anchor="middle" font-size="12.5" style="fill:var(--base-content, #27272a)">Ziel</text>
</svg>
</div>

**Das ist ein Schema, keine Messung** — die Zahlen in der Skizze sind erfunden, sie zeigen
nur, wie gelesen wird. **Schräg** heißt: entstanden zwischen zwei Bahnhöfen. **Senkrecht**
heißt: entstanden während des Halts, während der Zug stand. Rot ist dazugekommene Zeit,
blau aufgeholte. Am Ziel stehen zwölf Minuten — sieben davon unterwegs, fünf im Bahnhof.

**Diese Aufteilung steht in keiner öffentlichen Statistik.** Sie ist der Unterschied
zwischen „der Zug war zu spät" und „der Zug hat auf diesem Abschnitt Zeit verloren und an
jenem Bahnsteig noch einmal" — zwei Befunde, die auf zwei verschiedene Maßnahmen zeigen.
Jede Zahl auf den folgenden Seiten ist gemessen, nicht geschätzt.

## Was diese Seite dafür tut

**Erstens: mitschreiben.** Alle 30 Sekunden fragt ein Programm die öffentlichen
Echtzeitdaten für VRN und RMV ab und notiert, was sich seit dem letzten Mal geändert hat.
Für jeden Halt jedes Zuges stehen am Ende vier Zeiten fest: wann er ankommen sollte, wann
er ankam, wann er abfahren sollte, wann er abfuhr.

Warum dieser Umweg nötig ist: Echtzeitdaten sind **Vorhersagen**, die sich laufend ändern.
Eine Stunde vor der Abfahrt sagt der Feed etwas anderes als fünf Minuten vorher, und wenn
der Zug durch ist, verschwindet der Eintrag. Nur wer fortlaufend mitschreibt, kann
hinterher sagen, was tatsächlich passiert ist. Aufbewahrt wird das sonst nirgends.

**Zweitens: auseinanderrechnen.** Aus diesen vier Zeiten ergeben sich die beiden Größen
aus der Skizze. Wächst die Verspätung **zwischen zwei Bahnhöfen**, hat der Zug für die
Strecke länger gebraucht als vorgesehen — Langsamfahrstelle, Umleitung, ein anderer Zug im
Weg. Wächst sie **während des Halts**, hat der Aufenthalt länger gedauert als geplant —
Fahrgastwechsel, Anschluss abwarten, Personalwechsel. Wird sie kleiner, hat der Zug
**Reserve genutzt**, die im Fahrplan eingebaut ist. Das ist normal und kein Fehler.

**Drittens: zeigen.** Was dabei herauskommt, steht auf diesen Seiten:

- **[Befunde](/befunde)** — drei Aussagen aus den Daten, jede mit einer Zahl, einer Grafik
  und dem, was sie betrieblich bedeutet. Wer nur das Ergebnis will, liest diese eine Seite.
- **[Bahnhöfe](/bahnhoefe)** — je eine Seite für die größeren Knoten in VRN und Rhein-Main:
  kommt die Verspätung dort an, oder entsteht sie dort?
- **[Laufweg einer Fahrt](/laufweg)** — die Skizze von oben mit gemessenen Zahlen, an einer
  einzelnen Fahrt. Sie öffnet auf dem jüngsten vollständig erhobenen Betriebstag, ohne dass
  man erst etwas auswählen müsste.
- **[Engpässe im Netz](/engpaesse)** und **[Fahrplanreserve](/puffer)** — viele Fahrten
  übereinandergelegt: wo es wiederholt klemmt, und wo der Fahrplan zu knappe oder zu
  großzügige Zuschläge enthält.
- **[Pünktlichkeit und Ausfälle](/puenktlichkeit)** — warum eine Pünktlichkeitsquote besser
  wird, wenn Züge ausfallen.
- **[Methodik](/methodik)** — wie jede Zahl gerechnet wird, mit allen Annahmen und ihren
  Grenzen.

Der Rest dieser Seite ist der Beleg dafür: was aufgezeichnet ist, wie sich die Verspätung
im Ganzen aufteilt, und wie lückenlos gemessen wurde.

## Was bisher aufgezeichnet ist

```sql datenstand
select
    count(*)         as tage,
    sum(fahrten)     as fahrten,
    sum(halte)       as halte,
    min(betriebstag) as von,
    max(betriebstag) as bis
from bahnpuls.mart_datenqualitaet
```

<Alert status=info>

**Die Aufzeichnung ist jung.** Sie läuft seit dem 19. August 2026 — für Aussagen über eine
einzelne Linie oder einen bestimmten Bahnhof ist das noch zu kurz; man sieht ein paar Tage,
keine Regelmäßigkeit. Was hier steht, ist trotzdem gemessen und nicht geschätzt: jede Zahl
stammt aus der eigenen Mitschrift des Echtzeit-Feeds.

</Alert>

<BigValue data={datenstand} value=fahrten title="Aufgezeichnete Fahrten" />
<BigValue data={datenstand} value=halte title="Davon einzelne Halte" />
<BigValue data={datenstand} value=bis title="Aufgezeichnet bis" />

## Wo entsteht die Verspätung?

```sql aufteilung
select
    sum(laufzeit_delta_sek_summe)  / 60.0 as strecke_min,
    sum(haltezeit_delta_sek_summe) / 60.0 as bahnhof_min,
    sum(ausgefallene_halte)               as ausgefallene_halte
from bahnpuls.mart_verspaetungsentstehung
```

Dieselbe Aufteilung wie in der Skizze oben, nur über alle gemessenen Fahrten statt über
eine: wie viele Minuten kamen unterwegs dazu, und wie viele während der Halte. Aufgeholte
Zeit ist dabei schon abgezogen — ein Minuswert bedeutet also, dass unter dem Strich
Reserve genutzt wurde.

<BigValue data={aufteilung} value=strecke_min title="Unterwegs dazugekommen (Minuten)" fmt="#,##0.0" />
<BigValue data={aufteilung} value=bahnhof_min title="An Bahnhöfen dazugekommen (Minuten)" fmt="#,##0.0" />
<BigValue data={aufteilung} value=ausgefallene_halte title="Halte ausgefallener Züge" />

**Ausgefallene Züge stehen daneben, nicht mittendrin.** Ein Zug, der nicht fährt, hat
keine Verspätung — er hat gar nichts. Würde man ihn als null Minuten mitzählen,
verbesserte jede Streichung die Statistik. Genau das soll hier nicht passieren.

## Welche Abschnitte kosten am meisten Zeit?

```sql top_abschnitte
select
    coalesce(von_stop_name, von_stop_id) || ' → ' || coalesce(nach_stop_name, nach_stop_id) as abschnitt,
    betriebstag,
    zuege,
    laufzeit_messwerte                             as messbar,
    laufzeit_delta_sek_je_zug  / 60.0              as unterwegs_min,
    haltezeit_delta_sek_je_zug / 60.0              as bahnhof_min
from bahnpuls.mart_verspaetungsentstehung
where laufzeit_messwerte > 0
order by laufzeit_delta_sek_je_zug desc
limit 10
```

Sortiert danach, was ein Zug auf diesem Abschnitt **im Durchschnitt** verliert — nicht
danach, wie viel dort insgesamt zusammenkommt. Der Unterschied ist wichtig: Eine Summe
setzt immer die viel befahrenen Abschnitte nach oben, ganz gleich wie gut sie laufen. Der
Durchschnitt zeigt, wo es für den einzelnen Zug klemmt.

Die Spalte „messbar" sagt, auf wie vielen Fahrten der Wert beruht. Bei wenigen Fahrten ist
ein Ausreißer schnell dabei. Der Balken läuft nach rechts, wenn unterwegs Zeit verloren
ging, und nach links, wenn welche aufgeholt wurde — die Null liegt in jeder Zeile an
derselben Stelle.

<DataTable data={top_abschnitte} rows=10>
    <Column id=abschnitt title="Von — nach" />
    <Column id=betriebstag title="Tag" fmt='dd"."mm"."yyyy' />
    <Column id=zuege title="Züge" />
    <Column id=messbar title="davon messbar" />
    <Column id=unterwegs_min title="Unterwegs (Min. je Zug)" fmt="#,##0.0" contentType=bar barColor=verloren negativeBarColor=aufgeholt />
    <Column id=bahnhof_min title="Im Bahnhof (Min. je Zug)" fmt="#,##0.0" />
</DataTable>

Wo statt eines Bahnhofsnamens eine Nummer steht, ist der Name schlicht nicht bekannt: Der
Echtzeit-Feed liefert nur Kennnummern, und der amtliche Fahrplandatensatz vergibt diese
Nummern bei jeder Neuveröffentlichung anders. Der Echtzeit-Feed benutzt dabei mehrere
Nummernkreise nebeneinander, ein einzelner Fahrplandatensatz kennt also nur einen Teil
davon — zurzeit rund ein Drittel.

Deshalb wird jede Woche ein neuer Fahrplandatensatz geholt und **zu den bisherigen
hinzugefügt**, statt sie zu ersetzen. Mit jeder Woche werden mehr Nummern auflösbar. Wie
weit das gediehen ist, steht unten in der Spalte „Bahnhofsname bekannt".

## Wie verlässlich ist das?

```sql abdeckung
select
    betriebstag,
    halte,
    round(100 * abdeckung_an, 1) as gemessen_an,
    round(100 * abdeckung_ab, 1) as gemessen_ab,
    halte_ohne_ist_an + halte_ohne_ist_ab as keine_meldung,
    round(100 * namensquote, 1) as name_bekannt,
    ausgefallene_halte,
    ausgelassene_halte,
    halte_gebietsfremd,
    fahrten_gebietsfremd,
    case when erhebung_vollstaendig then '' else 'unvollständig' end as erhebung
from bahnpuls.mart_datenqualitaet
order by betriebstag desc
```

Keine Auswertung ist besser als ihre Datengrundlage. Deshalb steht hier offen, für wie
viele Halte überhaupt ein Wert vorlag — und woran es lag, wenn nicht.

Vier Gründe kann es haben, dass ein Halt keine Zahl trägt: Der Zug ist **ausgefallen**,
der Halt wurde **ausgelassen**, die Zeit fiel in die Nacht der **Zeitumstellung** (dort
gibt es eine Stunde doppelt, die Rechnung ist dann nicht eindeutig) — oder es kam
**einfach keine Meldung**. Nur der letzte Fall ist ein Problem der Messung. Die anderen
drei sind Betrieb und gehören zum Bild.

<DataTable data={abdeckung} rows=10>
    <Column id=betriebstag title="Tag" fmt='dd"."mm"."yyyy' />
    <Column id=halte title="Halte" />
    <Column id=gemessen_an title="Ankunft gemessen %" fmt="#,##0.0" />
    <Column id=gemessen_ab title="Abfahrt gemessen %" fmt="#,##0.0" />
    <Column id=keine_meldung title="keine Meldung" />
    <Column id=name_bekannt title="Bahnhofsname bekannt %" fmt="#,##0.0" />
    <Column id=ausgefallene_halte title="Ausfälle" />
    <Column id=ausgelassene_halte title="ausgelassen" />
    <Column id=halte_gebietsfremd title="Halte außerhalb" />
    <Column id=fahrten_gebietsfremd title="aussortiert" />
    <Column id=erhebung title="Erhebung" />
</DataTable>

**Halte außerhalb** sind Halte in den Daten, die nicht in VRN oder RMV liegen. Sie kommen
mit den Fernzügen herein: Gesammelt wird eine Fahrt, sobald sie einen Bahnhof im Gebiet
berührt — und zwar mit ihrem ganzen Laufweg, also auch mit München, Köln oder Hamburg.
Diese Halte bleiben in den Daten stehen, damit ein Laufweg lückenlos lesbar bleibt, gehen
aber in keine Kennzahl ein. Was ein Zug an Verspätung **mitbringt**, geht dabei nicht
verloren: sie steht an seinem ersten Halt im Gebiet.

Die letzte Spalte zählt Fahrten, die **gar nicht hierher gehören** und deshalb aus allen
Zahlen genommen wurden. Wie sie hereinkommen: gesammelt wird über eine Liste von
Bahnhöfen im Gebiet, und zwar über deren Nummern. Der Datenanbieter vergibt diese Nummern
je Datensatz neu — im Datensatz für Busse und Straßenbahnen trägt eine Haltestelle in
Hannover zufällig dieselbe Nummer wie ein Bahnhof hier. Für die Sammlung sieht das aus
wie ein Treffer.

Erkennen lässt sich das nur an der ganzen Fahrt: gehen mehr ihrer Halte im Nahverkehr
auf als im Bahnfahrplan, ist es keine Bahnfahrt im Gebiet. Steht hier eine 0, wurde
entweder nichts aussortiert — oder die Vergleichsliste fehlt gerade; dann sagt das der
Bauprotokoll-Eintrag, nicht diese Tabelle.

Steht in der Spalte **Erhebung** ein „unvollständig", hat die Sammlung an diesem Tag
nachweislich schief gegriffen. Der Tag steht deshalb hier, geht aber in **keine** Kennzahl
auf diesen Seiten ein. Betroffen sind der 22. und 23.08.2026: Der Datenanbieter vergab an
diesem Wochenende die Bahnhofsnummern neu, und die Sammlung lief danach gegen eine
veraltete Liste. Aufgezeichnet ist an beiden Tagen rund die Hälfte der planmäßigen
Fahrten — und zwar nicht irgendeine Hälfte, sondern überwiegend Fernverkehr über große
Knoten. Eine Quote darüber beschriebe diesen Rest und nicht das Gebiet, ohne dabei falsch
auszusehen. Warum der Tag trotzdem stehen bleibt und was seither anders läuft, steht auf
der [Methodik-Seite](/methodik) unter „Zwei Betriebstage, die nicht mitzählen“.

### Und hat der Sammler durchgehalten?

Die Tabelle oben zeigt, was in den Daten steht. Sie kann nicht zeigen, was **nicht** darin
steht: ein Poll, der ausfällt, hinterlässt keine Zeile, die man zählen könnte — er
hinterlässt eine Lücke zwischen zwei Zeitpunkten. Deshalb steht die Erhebung hier separat.

```sql erhebung_tage
select
    kalendertag,
    sum(polls_beobachtet) filter (where stunde_vollstaendig)        as polls,
    count(*) filter (where stunde_vollstaendig)                     as stunden,
    100.0 * sum(polls_beobachtet) filter (where stunde_vollstaendig)
          / nullif(sum(polls_erwartet) filter (where stunde_vollstaendig), 0) as abdeckung,
    count(*) filter (where stunde_vollstaendig and polls_beobachtet = 0)      as stunden_ohne_poll,
    max(groesste_luecke_sek)                                        as groesste_luecke,
    avg(feed_alter_schnitt_sek)                                     as feed_alter
from bahnpuls.erhebung
group by kalendertag
order by kalendertag desc
```

<DataTable data={erhebung_tage} rows=10>
    <Column id=kalendertag title="Tag" />
    <Column id=stunden title="volle Stunden" />
    <Column id=polls title="Abrufe" fmt="#,##0" />
    <Column id=abdeckung title="Abdeckung %" fmt="#,##0.0" />
    <Column id=stunden_ohne_poll title="Stunden ohne Abruf" />
    <Column id=groesste_luecke title="größte Lücke (s)" fmt="#,##0" />
    <Column id=feed_alter title="Alter der Daten (s)" fmt="#,##0" />
</DataTable>

Erwartet werden **120 Abrufe je Stunde**, einer alle 30 Sekunden. Gezählt sind nur
abgeschlossene Stunden — die laufende ist naturgemäß unvollständig und wäre sonst jeden
Tag ein Befund.

Drei Einschränkungen, damit die Spalten nicht mehr versprechen, als sie halten:

- **„Abdeckung" ist eine untere Schranke.** Gezählt werden Abrufe, die eine Änderung
  gebracht haben. Ein Abruf, bei dem sich nichts geändert hat, hinterlässt nichts und
  fehlt hier — praktisch kommt das nicht vor, selbst die ruhigste Nachtstunde bringt
  Änderungen, aber versprochen ist es nicht.
- **Über 100 % ist möglich.** Beim Ausrollen einer neuen Fassung laufen kurz zwei
  Sammler gleichzeitig. Der Wert wird bewusst nicht gedeckelt: ein gedeckelter Wert sähe
  aus wie eine normale Stunde und verbärge genau den Vorgang, der ihn erzeugt hat.
- **„Größte Lücke" ist der längste Abstand zwischen zwei Abrufen** an diesem Tag. Bei 30
  Sekunden Takt ist alles darüber ein Aussetzer — meist ein Zeitüberschreitung beim
  Abruf, die den nächsten Versuch verzögert.

Warum das hier steht und nicht in einem Betriebsprotokoll: eine Lücke in der Erhebung
sieht in jeder Auswertung darüber aus wie ruhiger Betrieb. Wer die Zahlen dieser Seite
liest, soll sehen können, ob sie auf lückenloser Beobachtung beruhen.

---

Warum jemand, der sieben Jahre Züge gefahren hat, das ausrechnet, steht unter
[Über das Projekt](/ueber).

---

Daten von [gtfs.de](https://gtfs.de) (CC BY-SA 4.0 bzw. CC BY 4.0) — vollständige
Angaben unter [Lizenz und Quellen](/lizenz) · [Impressum](/impressum) ·
[Datenschutz](/datenschutz)
