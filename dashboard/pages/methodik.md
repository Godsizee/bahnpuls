---
title: Methodik
description: Wie die Kennzahlen gerechnet werden — und was sie bewusst nicht behaupten
sidebar_position: 3
---

Eine Zahl ohne offengelegte Definition ist eine Behauptung. Diese Seite beschreibt jede
Kennzahl, die im Dashboard vorkommt, und benennt die Annahmen dahinter. Sie wird
zusammen mit den Kennzahlen gepflegt, nicht nachträglich.

**Diese Seite muss man nicht lesen, um das Dashboard zu verstehen.** Sie ist für alle da,
die eine Zahl nachprüfen oder ihr widersprechen wollen — und dafür wissen müssen, wie
genau sie zustande kam. Wer nur wissen will, worum es geht, ist auf der
[Startseite](/) besser aufgehoben.

Ein Hinweis vorweg, weil er alles Weitere prägt: Wo etwas nicht bestimmbar ist, bleibt es
hier leer. Es wird **nie** durch eine Null ersetzt. Null wäre eine Aussage — „es hat sich
nichts verändert" — und das ist etwas völlig anderes als „wir wissen es nicht". Diese
Unterscheidung zieht sich durch jede Kennzahl auf diesen Seiten.

## Datenstand

Diese Seiten sind eine **Vorschau im Aufbau**. Sie zeigen zwei Quellen nebeneinander, und
die beiden stehen auf sehr unterschiedlichem Grund — wer eine Zahl liest, muss wissen,
welche davon er vor sich hat:

- **Deutsche Echtzeitdaten: echt**, aus der eigenen Mitschrift seit dem 19.08.2026. Die
  Sammlung läuft erst wenige Tage; für Aussagen über Linien oder Bahnhöfe ist das zu kurz.
  Wo statt eines Bahnhofsnamens eine Nummer steht, kannte der Fahrplandatensatz diesen Halt
  noch nicht — der Echtzeit-Feed selbst enthält keine Namen.
- **Schweizer Daten: erfunden.** Sie prüfen die Rechenwege an konstruierten Fällen — ein
  Zug über Mitternacht, ein ausgefallener Zug, eine Nacht mit Zeitumstellung — und
  beschreiben **keinen realen Betrieb**. Keine Zahl aus dieser Quelle sagt etwas über
  tatsächliche Züge aus.

Welche Zeile woher stammt, steht in jeder Tabelle ausgeschrieben.

Woher die beiden Quellen kommen:

- **Schweizer Ist-Daten-Archiv** (opentransportdata.swiss): fertig gejointe Soll- und
  Ist-Zeiten je Halt, rückwirkend verfügbar. Dient dazu, die Auswertungen zu entwickeln,
  ohne auf eigene Sammelhistorie zu warten.
- **GTFS-Realtime für VRN und RMV** (gtfs.de): eigene Mitschrift seit dem 19.08.2026.
  Nur damit lässt sich später auch die Prognosegüte auswerten — archivierte Prognosen
  gibt es sonst nirgends.

## Was eine Zeile ist

Alles hier rechnet mit einer einzigen Grundeinheit: **ein Zug an einem Bahnhof.** Nicht
die ganze Fahrt, nicht die Linie, nicht der Tag — ein einzelner Halt eines einzelnen
Zuges. Dazu gehören vier Zeiten: wann er ankommen sollte, wann er tatsächlich ankam, wann
er abfahren sollte, wann er tatsächlich abfuhr.

Verspätungen sind immer die Abweichung vom Fahrplan in Minuten, positiv bedeutet zu spät,
negativ zu früh.

Fahrten werden dem **Betriebstag** zugeordnet, nicht dem Kalendertag. Ein Zug, der um
23:50 abfährt und um 00:40 ankommt, gehört zu einem einzigen Betriebstag — sonst fielen
genau die Nachtfahrten auseinander, in denen die auffälligsten Störungen stecken. Ein
Betriebstag kann deshalb länger als 24 Stunden sein.

## Laufzeit- und Haltezeitanteil

Die zentrale Zerlegung. Für jeden Halt *n* eines Laufwegs:

| Größe | Rechnung | Was sie beschreibt |
|---|---|---|
| **Laufzeitanteil** | Ankunftsverspätung(*n*) − Abfahrtsverspätung(*n−1*) | Was auf dem Abschnitt vom Vorhalt hierher dazukam oder wegging |
| **Haltezeitanteil** | Abfahrtsverspätung(*n*) − Ankunftsverspätung(*n*) | Was während des Halts dazukam oder wegging |

Ein **negativer Wert ist kein Fehler**, sondern genutzte Fahrplanreserve. Fahrpläne
enthalten planmäßige Fahrzeit- und Haltezeitzuschläge; ein Zug, der aufholt, verbraucht
sie. Ohne dieses Vorwissen wirkt „Zug kommt früher an" wie ein Datenfehler.

Der Laufzeitanteil wird nur für **lückenlos aufeinanderfolgende** Halte ausgewiesen. Fehlt
ein Halt dazwischen, beschreibt „von → nach" keine gefahrene Strecke mehr.

## Nicht bestimmbar heißt nicht null

Der Grundsatz hinter allen Kennzahlen: Wo ein Wert nicht bestimmbar ist, bleibt er leer.
Er wird nie durch 0 ersetzt, weil 0 eine Aussage wäre — „es hat sich nichts geändert" —
und nicht das Eingeständnis fehlender Information.

Betroffen sind vier Fälle:

- **Ausgefallene Züge.** Ein ausgefallener Zug hat keine Verspätung, er hat gar keine.
  Ausfälle fließen in keinen Verspätungsdurchschnitt ein, werden aber immer daneben
  ausgewiesen. Andernfalls verbessert jede Streichung die Statistik rechnerisch.
- **Ausgelassene Halte.** Gleiche Behandlung; die Zeile bleibt an ihrer Stelle im
  Laufweg stehen, damit die Reihenfolge lesbar bleibt, trägt aber keine Werte.
- **Unvollständige Meldungen.** Wird nur die Ankunft gemeldet, ist der Haltezeitanteil
  an diesem Halt nicht bestimmbar — und der Laufzeitanteil des Folgeabschnitts ebenfalls,
  weil er gegen die fehlende Abfahrtsverspätung rechnen müsste.
- **Halte in der Stunde der Zeitumstellung**, siehe nächster Abschnitt.

Davon zu unterscheiden ist der planmäßige Fall: Am Startbahnhof gibt es keine Ankunft, am
Endbahnhof keine Abfahrt. Dort wird kein Haltezeitanteil ausgewiesen, weil es keinen gibt
— das ist kein fehlender Messwert und wird auch nicht als solcher gekennzeichnet.

In den Diagrammen erscheinen solche Beiträge deshalb gar nicht, statt als Nulllinie.

## Zeitumstellung

In der Nacht der Rückstellung auf Winterzeit existiert die lokale Stunde 02:00–02:59
zweimal, in der Nacht der Umstellung auf Sommerzeit gar nicht. Soll- und Ist-Zeiten liegen
als lokale Wanduhrzeiten ohne Zeitzonenversatz vor. Liegen beide in der doppelten Stunde,
ist aus den Daten **nicht entscheidbar**, ob sie denselben Durchgang meinen — die
berechnete Verspätung kann um genau eine Stunde danebenliegen.

Diese Mehrdeutigkeit ist nicht wegrechenbar; eine Umrechnung über die benannte Zeitzone
löst sie nicht auf, weil sie für beide Werte denselben Durchgang wählt. Bahnpuls
korrigiert die betroffenen Halte deshalb nicht, sondern **markiert sie und nimmt sie aus
jeder Kennzahl heraus**. Betroffen sind zwei Nächte im Jahr. Wo ein solcher Halt in einem
Laufweg vorkommt, entfällt zusätzlich der Laufzeitanteil des Folgeabschnitts.

## Woher der Ist-Wert bei den deutschen Daten kommt

Die deutsche Quelle liefert keine fertigen Ist-Zeiten, sondern alle 30 Sekunden eine
Momentaufnahme mit Prognosen. Als Ist gilt daraus **der zeitlich letzte Wert, der bis
fünf Minuten nach der planmäßigen Zeit gemeldet wurde**. Die fünf Minuten fangen ab, dass
die letzte Meldung leicht nach dem Ereignis eintrifft; sie sind eine Annahme und
beeinflussen jede Zahl auf diesen Seiten.

Kommt für einen Halt bis dahin keine Meldung, bleibt der Wert leer — es wird nicht auf
eine frühere Prognose zurückgegriffen. Eine Prognose von vor zwanzig Minuten ist keine
Messung.

**Unplausible Werte werden verworfen, nicht gerundet.** Der Feed meldet vereinzelt Züge,
die Stunden *zu früh* wären — gemessen bis zu 23 Stunden. Solche Fahrten gibt es nicht;
die Werte entstehen, wenn sich eine Prognosezeit auf einen anderen Betriebstag bezieht.
Ein Wert außerhalb von einer Stunde zu früh bis 24 Stunden zu spät gilt deshalb als nicht
bestimmbar, und mit ihm die daraus abgeleitete planmäßige Zeit. Der Halt bleibt im Laufweg
stehen und trägt keine Zahl.

Das ist keine Kosmetik: ein Zug, der rechnerisch 23 Stunden zu früh ist, zöge jeden
Durchschnitt nach unten — also in die schmeichelhafte Richtung. Bei einer Auswertung über
Verspätungen ist das die schlechteste Richtung, in die ein Fehler zeigen kann.

Zwei Eigenheiten dieser Quelle, die man den Zahlen ansehen kann:

- **Eine Momentaufnahme enthält oft nur einen Teil der Halte einer Fahrt.** Der
  vollständige Laufweg entsteht erst aus der Zusammenschau vieler Aufnahmen. Fehlt ein
  Halt in allen, bleibt eine Lücke im Laufweg — sie wird als solche markiert, und
  Abschnitte über eine Lücke hinweg gehen in keine Auswertung ein.
- **Die Nummer eines Halts ist die Fahrplannummer, nicht seine Position.** Sie kann bei 0
  beginnen, und bei einem Zug, der beim Beginn der Beobachtung schon unterwegs war, bei
  einem beliebigen Wert. Der erste angezeigte Halt einer Fahrt ist deshalb nicht
  zwangsläufig ihr Startbahnhof.

Stationsnamen und Liniennummern fehlen bei dieser Quelle vorerst: der freie Echtzeit-Feed
enthält beide nicht. Angezeigt wird die Haltestellen-ID, bis der Fahrplan-Datensatz
angeschlossen ist.

## Abdeckung — worauf diese Zahlen stehen

Jede Aussage über Pünktlichkeit ist nur so viel wert wie der Beleg, dass die Datenbasis
vollständig war. Deshalb wird je Betriebstag mitgeführt, **wie viele Halt-Ereignisse
überhaupt einen Ist-Wert hatten** und aus welchem Grund die übrigen keinen haben.

Die Abdeckungsquote zählt ausschließlich Ereignisse, die der Fahrplan vorsieht. Der
Startbahnhof geht nicht als fehlende Ankunft in den Nenner ein — sonst sänke die Quote
allein dadurch, dass ein Tag mehr kurze Läufe enthält, ohne dass ein einziger Messwert
fehlte.

Die Gründe für einen fehlenden Wert werden **einzeln ausgewiesen und nie addiert**. Sie
können gleichzeitig zutreffen: ein Zug kann ausfallen und dabei in der Umstellungsstunde
liegen. Eine Summe dieser Spalten wäre eine Doppelzählung.

Vier Gründe werden unterschieden — ausgefallener Zug, ausgelassener Halt, Halt in der
Umstellungsstunde, und schließlich der Fall, der die anderen drei nicht erklärt: der Halt
stand im Fahrplan, fiel nicht aus, wurde nicht ausgelassen, lag nicht in der
Umstellungsstunde — und trotzdem kam keine Ist-Meldung. Das ist die Zahl, die eine echte
Lücke in der Datenquelle anzeigt, und die einzige, bei der ein Anstieg ein Problem der
Erhebung bedeutet und nicht des Betriebs.

Was hier noch **nicht** erfasst ist: Lücken in der Sammlung der deutschen Echtzeitdaten
selbst, also Zeiträume, in denen kein Abruf zustande kam. Die sind aus den Ist-Daten
nicht sichtbar; sie werden ergänzt, sobald die deutsche Quelle angeschlossen ist. Bis
dahin gilt die Abdeckung ausdrücklich nur für das, was in der Quelle stand.

## Normierung je Zug

Aggregierte Abschnittswerte werden **je Zug** ausgewiesen, nie als Rohsumme. Eine Summe
rankt zwangsläufig den dichtest befahrenen Abschnitt nach oben, unabhängig von seiner
Betriebsqualität — die Aussage wäre wertlos.

Der Nenner ist dabei die Zahl der Fahrten, für die der Wert **tatsächlich bestimmbar**
war, nicht die Zahl aller Fahrten. Beide Zahlen stehen nebeneinander, damit erkennbar
bleibt, auf wie viel Beobachtung ein Durchschnitt beruht.

Über mehrere Tage hinweg werden Mittelwerte aus Summe und Zähler neu gerechnet, nicht aus
Tagesmittelwerten gemittelt — sonst zählte ein Sonntag so viel wie ein Werktag.

## Bestimmung des Ist-Werts

**Schweizer Ist-Daten:** Als Ist-Zeit gilt ausschließlich ein Wert, den die Quelle als
tatsächlich gemessen kennzeichnet. Prognostizierte oder geschätzte Zeiten werden nicht als
Ist verwendet, auch wenn sie vorliegen.

**Eigene GTFS-Realtime-Daten:** Die Quelle liefert fortlaufend
Prognose-Schnappschüsse. Als Ist-Wert gilt der zeitlich letzte Schnappschuss, der
höchstens **fünf Minuten nach** dem prognostizierten Ereigniszeitpunkt eingetroffen ist.
Die Karenz fängt ab, dass die letzte Meldung leicht nach dem Ereignis eintrifft. Der Wert
ist eine Annahme und beeinflusst jede nachgelagerte Kennzahl; er wird hier ausgewiesen und
bei einer Änderung hier korrigiert.

## Was diese Zahlen nicht sind

Bahnpuls ist keine amtliche Statistik und steht in keiner Verbindung zu den
Datenherausgebern oder zu Eisenbahnverkehrsunternehmen. Die zugrunde liegenden Daten
werden ohne Gewähr auf Vollständigkeit und Verfügbarkeit bereitgestellt; Lücken im Feed
schlagen auf die Auswertung durch. Die Darstellung ist analytisch gemeint: sie beschreibt,
wo im Netz Verspätung entsteht, und nicht, wer sie zu verantworten hat.

## Quellen

- Deutsche Echtzeitdaten: [gtfs.de](https://gtfs.de), lizenziert unter CC BY-SA 4.0.
- Deutsche Fahrplandaten: [gtfs.de](https://gtfs.de) auf Grundlage des NeTEx-Datensatzes
  des DELFI e. V., lizenziert unter CC BY 4.0.
- Schweizer Ist-Daten: [opentransportdata.swiss](https://opentransportdata.swiss) als
  Bezugsort der Rohdaten.

Vollständige Attribution, die Bedingungen für eine Weiterverwendung und die Lizenz des
Codes stehen auf der Seite [Lizenz und Quellen](/lizenz).

---

Daten von [gtfs.de](https://gtfs.de) (CC BY-SA 4.0 bzw. CC BY 4.0) — vollständige
Angaben unter [Lizenz und Quellen](/lizenz) · [Impressum](/impressum) ·
[Datenschutz](/datenschutz)
