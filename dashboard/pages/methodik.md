---
title: Methodik
description: Wie die Kennzahlen gerechnet werden — und was sie bewusst nicht behaupten
---

Eine Zahl ohne offengelegte Definition ist eine Behauptung. Diese Seite beschreibt jede
Kennzahl, die im Dashboard vorkommt, und benennt die Annahmen dahinter. Sie wird
zusammen mit den Kennzahlen gepflegt, nicht nachträglich.

## Datenstand

Die aktuell gezeigten Zahlen stammen aus **synthetischen Testdaten**. Sie prüfen die
Rechenwege — ob Fensterlogik, Betriebstag-Behandlung und Ausfallbehandlung korrekt sind —
und beschreiben keinen realen Betrieb. Sobald echte Daten vorliegen, wird dieser Abschnitt
ersetzt.

Zwei Quellen sind vorgesehen:

- **Schweizer Ist-Daten-Archiv** (opentransportdata.swiss): fertig gejointe Soll- und
  Ist-Zeiten je Halt, rückwirkend verfügbar. Dient dazu, die Auswertungen zu entwickeln,
  ohne auf eigene Sammelhistorie zu warten.
- **GTFS-Realtime für VRN und RMV** (gtfs.de): eigene Mitschrift seit dem 19.08.2026.
  Nur damit lässt sich später auch die Prognosegüte auswerten — archivierte Prognosen
  gibt es sonst nirgends.

## Was eine Zeile ist

Grundeinheit ist das **Halt-Ereignis**: ein Zug an einer Betriebsstelle, mit Soll- und
Ist-Zeit für Ankunft und Abfahrt. Alle Verspätungen sind Sekunden bzw. Minuten gegenüber
dem Sollfahrplan, positiv bedeutet zu spät.

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

Davon zu unterscheiden ist der planmäßige Fall: Am Startbahnhof gibt es keine Ankunft, am
Endbahnhof keine Abfahrt. Dort wird kein Haltezeitanteil ausgewiesen, weil es keinen gibt
— das ist kein fehlender Messwert und wird auch nicht als solcher gekennzeichnet.
- **Halte in der Stunde der Zeitumstellung**, siehe nächster Abschnitt.

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

**Eigene GTFS-Realtime-Daten** (in Vorbereitung): Die Quelle liefert fortlaufend
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

- Schweizer Ist-Daten: [opentransportdata.swiss](https://opentransportdata.swiss) als
  Bezugsort der Rohdaten.
- Deutsche Fahrplan- und Echtzeitdaten: [gtfs.de](https://gtfs.de), lizenziert unter
  CC BY-SA 4.0.

Die vollständige Lizenzseite mit Attribution, Weitergabebedingungen und Impressum folgt
vor der Veröffentlichung.
