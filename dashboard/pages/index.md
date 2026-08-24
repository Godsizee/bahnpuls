---
title: Bahnpuls
description: Wo Verspätung im Schienenverkehr entsteht — auf der Strecke oder im Bahnhof
sidebar_position: 1
---

Ein Zug kommt zwölf Minuten zu spät an. Das steht in jeder Statistik. Was nirgends steht:
**wo diese zwölf Minuten entstanden sind.** Standen sie schon beim Start? Kamen sie auf
einem bestimmten Streckenabschnitt dazu? Oder sammelten sie sich in kleinen Portionen an
sechs Bahnhöfen, weil überall der Aufenthalt zu knapp bemessen ist?

Das sind drei völlig verschiedene Probleme mit drei verschiedenen Antworten. Wer nur die
Ankunftsverspätung kennt, kann sie nicht auseinanderhalten.

Bahnpuls rechnet genau das aus.

**Wer nur das Ergebnis will:** Auf der Seite [Befunde](/befunde) stehen drei Aussagen aus
den Daten — jede mit einer Zahl, einer Grafik und dem, was sie betrieblich bedeutet. Alles
Übrige auf diesen Seiten sind Werkzeuge, um sie nachzuprüfen.

## Wie das funktioniert

Für jeden Halt wird zweierlei festgehalten: **wie viel Verspätung ein Zug beim Ankommen
hatte** und **wie viel beim Weiterfahren**. Aus dem Vergleich ergibt sich, wo sie
entstanden ist:

- Wächst die Verspätung **zwischen zwei Bahnhöfen**, hat der Zug für die Strecke länger
  gebraucht als vorgesehen — Langsamfahrstelle, Umleitung, ein anderer Zug im Weg.
- Wächst sie **während des Halts**, hat der Aufenthalt länger gedauert als geplant —
  Fahrgastwechsel, Anschluss abwarten, Personalwechsel.
- Wird sie kleiner, hat der Zug **Reserve genutzt**, die im Fahrplan eingebaut ist. Das
  ist normal und kein Fehler.

Die Daten stammen nicht aus einer Auswertung der Bahn, sondern aus eigener Mitschrift:
Alle 30 Sekunden fragt ein Programm die öffentlichen Echtzeitdaten ab und notiert, was
sich seit dem letzten Mal geändert hat.

Warum dieser Umweg nötig ist: Echtzeitdaten sind **Vorhersagen**, die sich laufend ändern.
Eine Stunde vor der Abfahrt sagt der Feed etwas anderes als fünf Minuten vorher, und wenn
der Zug durch ist, verschwindet der Eintrag. Nur wer fortlaufend mitschreibt, kann
hinterher sagen, was tatsächlich passiert ist. Aufbewahrt wird das sonst nirgends.

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

Alle gemessenen Fahrten zusammengenommen: wie viele Minuten kamen unterwegs dazu, und wie
viele während der Halte. Aufgeholte Zeit ist dabei schon abgezogen — ein Minuswert
bedeutet also, dass unter dem Strich Reserve genutzt wurde.

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
ein Ausreißer schnell dabei.

<DataTable data={top_abschnitte} rows=10>
    <Column id=abschnitt title="Von — nach" />
    <Column id=betriebstag title="Tag" fmt='dd"."mm"."yyyy' />
    <Column id=zuege title="Züge" />
    <Column id=messbar title="davon messbar" />
    <Column id=unterwegs_min title="Unterwegs (Min. je Zug)" fmt="#,##0.0" contentType=colorscale colorScale=negative />
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

Wie es an einem bestimmten Bahnhof aussieht — und ob die Verspätung dort ankommt oder dort
entsteht —, steht auf den [Bahnhofsseiten](/bahnhoefe) — je eine für die größeren
Knoten in VRN und Rhein-Main. Wie eine einzelne Fahrt Halt für Halt verläuft, zeigt die Seite
[Laufweg einer Fahrt](/laufweg). Ob es Stellen im Netz gibt, an denen es immer wieder
klemmt, beantwortet [Engpässe im Netz](/engpaesse); wo der Fahrplan zu knappe oder zu
großzügige Zuschläge enthält, zeigt [Fahrplanreserve](/puffer). Was passiert, wenn ein Zug gar nicht
erst fährt — und warum Pünktlichkeitsquoten dadurch besser werden —, steht unter
[Pünktlichkeit und Ausfälle](/puenktlichkeit). Wer genau wissen will, wie gerechnet wird
— mit allen Annahmen und ihren Grenzen —, findet das auf der Seite [Methodik](/methodik).

Warum jemand, der sieben Jahre Züge gefahren hat, das ausrechnet, steht unter
[Über das Projekt](/ueber).

---

Daten von [gtfs.de](https://gtfs.de) (CC BY-SA 4.0 bzw. CC BY 4.0) — vollständige
Angaben unter [Lizenz und Quellen](/lizenz) · [Impressum](/impressum) ·
[Datenschutz](/datenschutz)
