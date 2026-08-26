---
title: Methodik
description: Wie die Kennzahlen gerechnet werden — und was sie bewusst nicht behaupten
sidebar_position: 8
---

**Diese Seite beschreibt jede Kennzahl des Dashboards und benennt die Annahmen dahinter.**

Eine Zahl ohne offengelegte Definition ist eine Behauptung. Die Seite wird zusammen mit den
Kennzahlen gepflegt, nicht nachträglich.

**Diese Seite muss man nicht lesen, um das Dashboard zu verstehen.** Sie ist für alle da,
die eine Zahl nachprüfen oder ihr widersprechen wollen — und dafür wissen müssen, wie
genau sie zustande kam. Wer nur wissen will, worum es geht, ist auf der
[Startseite](/) besser aufgehoben.

Ein Hinweis vorweg, weil er alles Weitere prägt: Wo etwas nicht bestimmbar ist, bleibt es
hier leer. Es wird **nie** durch eine Null ersetzt. Null wäre eine Aussage — „es hat sich
nichts verändert" — und das ist etwas völlig anderes als „wir wissen es nicht". Diese
Unterscheidung zieht sich durch jede Kennzahl auf diesen Seiten.

## Datenstand

Alle Zahlen auf diesen Seiten stammen aus **einer** Quelle: **GTFS-Realtime für VRN und
RMV** (gtfs.de), aufgezeichnet in eigener Mitschrift seit dem 19.08.2026. Nichts hier ist
konstruiert, geschätzt oder aus einer fremden Auswertung übernommen.

Zwei Einschränkungen gehören dazu, bevor irgendeine Zahl gelesen wird:

- **Die Sammlung ist jung.** Für Aussagen über eine einzelne Linie oder einen bestimmten
  Bahnhof reichen wenige Tage nicht; man sieht Tage, keine Regelmäßigkeit.
- **Zwei Betriebstage zählen nicht mit.** Am 22. und 23.08.2026 hat die Sammlung
  nachweislich schief gegriffen; beide Tage gehen in keine Kennzahl ein und stehen
  gekennzeichnet daneben — Einzelheiten unter
  „Zwei Betriebstage, die nicht mitzählen“ weiter unten.
- **Wo statt eines Bahnhofsnamens eine Nummer steht**, kannte keine Fahrplan-Version
  diesen Halt — der Echtzeit-Feed selbst enthält keine Namen.

Warum ausgerechnet die eigene Mitschrift und kein fertiges Archiv: nur so lässt sich
später auch die **Prognosegüte** auswerten. Archivierte Prognosen gibt es sonst nirgends —
sie werden laufend überschrieben und sind weg, sobald der Zug durch ist.

Bis zum 23.08.2026 stand daneben eine zweite, **synthetische** Quelle (konstruierte
Schweizer Fälle), an der die Rechenwege entwickelt wurden, solange noch keine eigene
Historie vorlag. Sie ist entfernt worden, sobald die eigene Aufzeichnung trug: erfundene
Zahlen gehören nicht neben gemessene, auch nicht als gekennzeichnete Nebenspalte. Die
Fälle, die sie geprüft hat — Fahrt über Mitternacht, Ausfall, ausgelassener Halt, Nacht
der Zeitumstellung — prüfen jetzt Testdaten im deutschen Format, außerhalb des
Dashboards.

## Wie die Zahlen geschrieben sind

Deutsche Schreibweise: **der Punkt trennt Tausender, das Komma die Nachkommastellen.**
`32.126,0` sind also zweiunddreißigtausend, nicht zweiunddreißig. Datumsangaben stehen als
`24.08.2026`, Uhrzeiten als `18:07`.

Wo eine große Zahl abgekürzt steht, meint **`k` Tausend und `M` Millionen** — `32,1k` ist
dieselbe Zahl wie `32.126`, nur gerundet. Zeitangaben tragen ihre Einheit in der
Spaltenüberschrift; „Min." heißt Minuten, „s" Sekunden. Sekundenwerte je Halt oder
Abschnitt sind bewusst nicht in Minuten umgerechnet: die Beträge liegen im einstelligen
Sekundenbereich, und `0,1 Min.` liest sich schlechter als `5,84 s`.

## Wie die Farben zu lesen sind

Farbe trägt auf diesen Seiten Bedeutung und ist keine Verzierung. Sie folgt zwei Regeln.

**Wo eine Zahl ein Vorzeichen hat, steht ein Balken und keine Farbfläche.** Betroffen sind
alle Spalten, die eine entstandene oder abgebaute Zeit ausweisen — „unterwegs dazu",
„im Bahnhof entstanden", „auf dem Abschnitt entstanden". Der Balken läuft von der Null aus:
nach rechts, wenn Zeit **verloren** ging, nach links, wenn welche **aufgeholt** wurde. Die
Null liegt in jeder Zeile derselben Tabelle an derselben Stelle; die Länge ist auf die
stärkste Abweichung der jeweiligen Spalte bezogen.

Der Grund ist nicht Geschmack. Eine durchgehende Farbskala läuft vom kleinsten zum größten
Wert einer Spalte — enthält die Spalte auch negative Werte, bekommt aufgeholte Zeit damit
denselben Farbton wie verlorene, nur etwas blasser. Das ist genau die Verwechslung, die
diese Seiten vermeiden wollen: **eine abgebaute Verspätung ist kein schwacher Schaden,
sondern das Gegenteil davon.**

**Wo eine Zahl kein Vorzeichen haben kann, steht eine Farbskala mit festen Grenzen.**
Betroffen sind die Anteile auf der Seite [Fahrplanreserve](/puffer): Sie laufen von 0 auf
100 %, nicht vom kleinsten zum größten Wert der jeweiligen Liste. Eine Skala, die sich an
den gezeigten Zeilen ausrichtet, ließe die harmloseste Zeile einer schlechten Liste wie
einen Nullwert aussehen — und zwei Tabellen nebeneinander wären nicht vergleichbar.

Eine Ausnahme steht auf der Seite [Engpässe im Netz](/engpaesse): die Heatmap nach
Tagesstunde. Ihre Farbe ist eine Rangfolge **innerhalb der Grafik**, vom kleinsten zum
größten gezeigten Wert, ohne verankerten Nullpunkt — feste Grenzen würden hier mit den
Daten nicht mitwandern. Ob auf einem Feld aufgeholt wurde, steht deshalb dort in der Zahl
und nicht in der Farbe.

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

## Verkehrsart und Zuggattung

Auf jeder Auswertungsseite steht dieselbe Auswahlleiste: **Alle · Nahverkehr ·
Fernverkehr**, darunter die Zuggattungen — ICE, IC, EC, RE, RB, S und was der Fahrplan
sonst führt. Die beiden Angaben stammen aus **zwei verschiedenen Quellen**, und keine von
beiden wird geraten.

| Angabe | Woher sie kommt | Werte |
|---|---|---|
| **Verkehrsart** | aus der Fahrplandatei, in der die Fahrt steht | Fernverkehr, Nahverkehr, ohne Angabe |
| **Zuggattung** | aus dem Liniennamen, bis zur ersten Ziffer | ICE, IC, EC, RE, RB, S, … , ohne Angabe |

**Die Verkehrsart ist eine Eigenschaft der Datei, nicht eine Deutung des Namens.** gtfs.de
liefert die Schienenfahrpläne getrennt aus: einen Datensatz für den Fernverkehr, einen für
den Nahverkehr. Welcher Datensatz den Liniennamen einer Fahrt liefert, entscheidet damit
zugleich ihre Verkehrsart. Diese Zuordnung reist auf demselben Weg mit, auf dem ohnehin
der Name geholt wird.

**Die Zuggattung wird gelesen, nicht zugeordnet:** der Anfang des Liniennamens bis zur
ersten Ziffer. Aus `RE 70` wird `RE`, aus `S 3` wird `S`, aus `IC 2011` wird `IC`. Es gibt
keine gepflegte Liste bekannter Gattungen. Ein `MEX` oder `SÜWEX` bekommt deshalb seine
eigene Gattung, statt in einem Sammeleimer „sonstige" zu landen — und liegt trotzdem
richtig unter Nahverkehr, weil das die andere Angabe entscheidet.

**Warum nicht aus dem Namen auf die Verkehrsart geschlossen wird.** Eine Liste
„ICE, IC, EC gehören zum Fernverkehr, RE, RB, S zum Nahverkehr" müsste gepflegt werden,
und jede unbekannte Gattung landete auf der falschen Seite oder in einem Sammeleimer. Eine
Regionalfahrt als Fernverkehr zu zählen fiele in keiner Zahl auf. Auch die Verkehrsgesellschaft
taugt nicht dafür: Der Nahverkehrsdatensatz führt 147 davon, und weder VRN noch RMV sind
darunter — beide sind Tarifverbünde und keine Datenkategorie.

### Was „ohne Angabe" bedeutet

**„Ohne Angabe" heißt: der Fahrplan kennt diese Fahrt nicht.** Es heißt nicht „sonstige".

Beide Angaben sind für genau dieselben Fahrten leer — für die, deren Kennung in keiner zum
Betriebstag gültigen Fahrplan-Version vorkommt. Dort fehlt auch schon der Linienname; in
den Tabellen stehen diese Fahrten als „ohne Liniennummer".

Diese Gruppe ist als **eigene, anwählbare Gattung** sichtbar und in der Auswahl *Alle*
enthalten. Sie verschwindet nirgends stillschweigend. Wählst du oben *Nahverkehr* oder
*Fernverkehr*, fällt sie dagegen heraus — sie gehört zu keinem von beiden, und eine
Zuordnung wäre erfunden.

```sql ohne_angabe
-- Die Zahl kommt aus der Abfrage, nicht aus dem Text: diese Seite wird stündlich neu
-- gebaut, und ein festgeschriebener Prozentsatz wäre irgendwann falsch, ohne dass es
-- auffiele. Dieselbe Regel, nach der die Befundseite gebaut ist.
select
    sum(fahrten)                                                as fahrten,
    sum(fahrten) filter (where verkehrsart = 'ohne Angabe')     as fahrten_ohne,
    100.0 * sum(fahrten) filter (where verkehrsart = 'ohne Angabe')
          / nullif(sum(fahrten), 0)                             as anteil_ohne,
    sum(halte_mit_ankunft)                                      as halte,
    100.0 * sum(halte_mit_ankunft) filter (where verkehrsart = 'ohne Angabe')
          / nullif(sum(halte_mit_ankunft), 0)                   as halte_anteil_ohne
from bahnpuls.puenktlichkeit
-- Eine einzige Schwelle: die Fahrten- und Haltezahlen hängen nicht von ihr ab und
-- stünden sonst fünffach in der Summe.
where schwelle_min = 6
```

<BigValue data={ohne_angabe} value=anteil_ohne fmt='#,##0.0'
    title="Anteil der Fahrten ohne Verkehrsart (%)" />
<BigValue data={ohne_angabe} value=fahrten_ohne fmt='#,##0'
    title="Fahrten ohne Verkehrsart" />
<BigValue data={ohne_angabe} value=halte_anteil_ohne fmt='#,##0.0'
    title="deren Anteil an den planmäßigen Halten (%)" />

Die Zahlen stehen auf den letzten 30 aufgezeichneten Betriebstagen — demselben Fenster wie
die Seite [Pünktlichkeit und Ausfälle](/puenktlichkeit). Ist der Anteil groß, ist eine nach
Verkehrsart gefilterte Ansicht entsprechend kleiner als die Gesamtsicht. Deshalb steht die
Zahl hier und nicht in einer Fußnote.

Mit jeder geladenen Fahrplan-Version wird die Gruppe kleiner: Die Fahrpläne werden
gesammelt und nicht ersetzt, und eine Fahrt, deren Kennung später auflösbar wird, verlässt
diese Gruppe.

### Wo nicht gefiltert werden kann

Zwei Auswertungen tragen die Verkehrsart **nicht** und lassen sich deshalb nicht danach
einschränken:

- die Gesamtzahlen der [Startseite](/) — sie sollen mit einer Aussage beginnen und nicht
  mit einer Auswahl;
- die Tabelle „Woher die Züge kommen" auf jeder Bahnhofsseite, die aus derselben
  Auswertung stammt.

Beide zeigen also immer alle Züge. Wo das zutrifft, steht es auf der Seite selbst.

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

## Zwei Betriebstage, die nicht mitzählen

Am **22. und 23. August 2026** ist die Erhebung schiefgelaufen, und zwar hier und nicht
bei der Quelle. Gesammelt wird über eine Liste von Bahnhofsnummern im Zielgebiet. Am
22.08. um 08:41 Uhr veröffentlichte der Datenanbieter einen neuen Fahrplan-Datensatz und
vergab dabei die Nummern neu: von den 1.916 Nummern, mit denen die Sammlung lief, standen
danach noch **48** im Fahrplan. Ab diesem Moment wurde nicht mehr der Bahnverkehr im
Gebiet mitgeschrieben, sondern das, was zufällig dieselbe Nummer trug.

Aufgezeichnet sind an diesen beiden Tagen **3.381 und 2.456 Schienenfahrten**, während der
Fahrplan für das Gebiet 6.710 und 6.183 vorsieht. Rund die Hälfte fehlt — und weil
Echtzeitdaten nirgends archiviert werden, ist sie endgültig weg.

**Entscheidend ist aber nicht, wie viel fehlt, sondern welcher Teil.** Durchgekommen ist,
was die Neuvergabe zufällig überlebt hat: überwiegend große Knotenbahnhöfe und
Fernverkehr. Das ist keine zufällige Stichprobe, sondern eine Schieflage. Eine
Pünktlichkeitsquote über diese beiden Tage beschriebe diesen Rest und nicht das Gebiet —
und sie sähe nicht offensichtlich falsch aus, sondern einfach nach zwei ruhigen Tagen.
Genau deshalb steht dieser Abschnitt hier.

Für diese beiden Tage gilt deshalb:

- Sie gehen in **keine** Kennzahl ein — weder in die Pünktlichkeit noch in die
  Abschnittsauswertungen.
- Sie bleiben **sichtbar**: in der Tabelle „Wie verlässlich ist das?" auf der Startseite
  stehen sie weiterhin, gekennzeichnet, und die Einzelfahrten dieser Tage lassen sich
  weiterhin ansehen. Ein Tag, der spurlos verschwindet, wäre von einem Tag ohne Sammlung
  nicht zu unterscheiden.
- Die **Rohdaten bleiben unangetastet**. Korrigiert wird nur in der Auswertung, nie in der
  Mitschrift.

Die Ursache ist seit dem 24.08.2026 behoben: Die Liste wird nicht mehr über Nummern
gepflegt, sondern aus den **Stationsnamen** abgeleitet und nach jeder
Fahrplanveröffentlichung neu erzeugt — ein Bahnhof wechselt nicht das Gebiet, weil er eine
neue Nummer bekommt. Eine stündliche Prüfung meldet außerdem, wenn die Liste nicht mehr
zum aktuellen Fahrplan passt; am 22.08. hätte sie binnen einer Stunde angeschlagen.

## Was aussortiert wird — und warum es trotzdem gezählt steht

Gesammelt wird über eine Liste von Bahnhöfen im Zielgebiet, und zwar über deren Nummern:
taucht in einer Meldung eine dieser Nummern auf, wird die ganze Fahrt mitgeschrieben. Das
ist die Voraussetzung dafür, dass auch ein Fernzug erfasst wird, der das Gebiet nur einmal
berührt.

Der Datenanbieter vergibt die Nummern aber **je Datensatz getrennt**. Im Datensatz für
Busse und Straßenbahnen trägt eine Haltestelle in Hannover dieselbe Nummer wie ein Bahnhof
hier — und seit dem 22.08.2026 liefert der Echtzeit-Datenstrom auch diesen Nahverkehr,
bundesweit. Für die Sammlung sieht das aus wie ein Treffer im Zielgebiet.

An einer einzelnen Nummer ist das nicht zu erkennen; sie kann in beiden Datensätzen etwas
bedeuten. Entschieden wird deshalb über die **ganze Fahrt**: Gehen mehr ihrer Halte im
Nahverkehrsdatensatz auf als im Bahnfahrplan, ist es keine Bahnfahrt im Gebiet, und die
Fahrt fließt in keine Kennzahl ein.

Zwei Festlegungen dazu, die nicht selbstverständlich sind:

- **Bei Gleichstand bleibt die Fahrt drin**, insbesondere wenn kein Fahrplan sie kennt.
  Nicht prüfbar ist nicht widerlegt — dieselbe Regel wie bei der Belegquote der Laufwege.
- **Die aussortierten Fahrten werden gezählt und auf der Startseite ausgewiesen.** Ein
  Ausschluss, der nirgends auftaucht, ist von einem Datenverlust nicht zu unterscheiden.

Der Weg über die Namen wäre der naheliegende und wurde gemessen: Die Regel „mindestens
zwei Halte namentlich im Gebiet" hätte zwar fast allen Fremdverkehr abgefangen, dabei aber
**237 von 1.681 echten Bahnfahrten** verworfen — und 100 der Fremdfahrten tragen genau
einen bekannten Halt, der im Gebiet liegt. Von einem Fernzug, der einmal hier hält, ist
das nicht zu unterscheiden.

### Halte außerhalb von VRN und RMV

Derselbe Mechanismus, der einen Fernzug erfasst, bringt seinen **ganzen Laufweg** mit: Ein
ICE München–Frankfurt–Hamburg wird wegen seiner Halte in Hessen gesammelt und trägt
München und Hamburg mit in die Daten. Gemessen am 23.08.2026 lagen so **43,3 % aller Halte
mit bekanntem Namen außerhalb** des Zielgebiets — angeführt von Karlsruhe, Köln, Nürnberg,
Kassel-Wilhelmshöhe, Stuttgart und München.

Diese Halte bleiben in den Daten stehen, gehen aber in keine Kennzahl ein:

- **Ob ein Halt im Gebiet liegt, entscheidet dieselbe Liste, nach der gesammelt wird** —
  abgeleitet aus den Tarifplänen der beiden Verbünde, nach Heimatverbund und nicht nach
  Übergangstarif. Geprüft wird **über den Namen**; die Nummer entscheidet nur dort, wo kein
  Fahrplan den Halt benennt. Der Name muss es sein, weil die Nummern zwischen den
  wöchentlichen Fahrplanausgaben fast vollständig wechseln und ein Bahnhof dadurch nicht
  das Gebiet verlässt. Und er muss den Vorrang haben, weil dieselbe Nummer in einem
  anderen Datensatz etwas anderes bedeutet: Zählte die Nummer gleichrangig mit, stünden
  Klandorf in Brandenburg und Pernink in Tschechien in der Rangliste der Engpässe — beides
  am 23.08.2026 gemessen und wieder herausgenommen.
- **Ein Abschnitt zählt nur, wenn beide Endpunkte im Gebiet liegen.** Ohne diese Bedingung
  stand `Köln Hbf → Köln Messe/Deutz` mit 261 Zügen in der Engpass-Rangliste.
- **Die Halte werden nicht gelöscht, sondern gekennzeichnet.** Fiele ein Halt aus der
  Reihenfolge, spannte der Abschnitt über ihn hinweg und wiese zwei nicht benachbarte
  Bahnhöfe als direkte Fahrt aus — plausibel aussehend und dadurch besonders teuer.
- **Die Verspätung, mit der ein Zug einfährt, bleibt erhalten.** Sie steht als
  Ankunftsverspätung an seinem ersten Halt im Gebiet. Nur der Laufzeitanteil des
  Einfahrtsabschnitts fehlt — er ist auf der Strecke davor entstanden. Damit bleibt ein
  Zug, der 20 Minuten mitbringt, von einem unterscheidbar, der sie hier aufsammelt.
- **Die Zahl steht daneben**, wie bei den aussortierten Fahrten: Wie viele Halte außerhalb
  lagen, weist das Abdeckungsprotokoll je Betriebstag aus.

Was das kostet, ist benannt: Der Laufweg eines Fernzuges ist auf diesen Seiten nur noch
innerhalb von VRN und RMV zu sehen. Wo ein Zug seine Verspätung außerhalb aufgesammelt
hat, beantworten diese Daten nicht.

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

Die Quelle liefert keine Ist-Zeiten, sondern fortlaufend
**Prognose-Schnappschüsse**. Als Ist-Wert gilt der zeitlich letzte Schnappschuss, der
höchstens **fünf Minuten nach** dem prognostizierten Ereigniszeitpunkt eingetroffen ist.
Die Karenz fängt ab, dass die letzte Meldung leicht nach dem Ereignis eintrifft. Der Wert
ist eine Annahme und beeinflusst jede nachgelagerte Kennzahl; er wird hier ausgewiesen und
bei einer Änderung hier korrigiert.

## Fahrplanreserve: derselbe Zug, zwei Befunde

Fahrpläne enthalten Regelzuschläge — Fahrzeit- und Haltezeitreserve. Ein negativer
Laufzeitanteil heißt deshalb nicht „Messfehler", sondern: der Zug hat Reserve gezogen.
Die Seite [Fahrplanreserve](/puffer) wertet genau das aus.

**Entscheidend ist, mit welcher Verspätung ein Zug in den Abschnitt einfährt.** Dieselbe
Beobachtung bedeutet zwei gegensätzliche Dinge:

- **Verspätet eingefahren und aufgeholt** — die Reserve hat gewirkt. Ein hoher Anteil ist
  ein gutes Zeichen.
- **Pünktlich eingefahren und trotzdem früher angekommen** — der Zug brauchte den
  Zuschlag nicht. Ein hoher Anteil heißt, dass die Fahrzeit großzügiger bemessen ist als
  nötig; der Zug steht dann am nächsten Halt und wartet.

Eine gemeinsame Kennzahl „Anteil aufholender Züge" nähme für beide Fälle denselben Wert
an. Beide werden deshalb getrennt gezählt und nie summiert.

**Als pünktlich eingefahren gilt eine Eingangsverspätung von höchstens 60 Sekunden.**
Das ist eine Annahme, sie entscheidet die Zuordnung, und sie steht hier, weil sie das tut.
Die Eingangsverspätung wird nicht neu gemessen, sondern aus den vorhandenen Werten
gerechnet: Ankunftsverspätung minus Laufzeitanteil ist genau die Abfahrtsverspätung am
Vorhalt. Ist eines von beiden nicht bestimmbar, fällt die Durchfahrt aus der Auswertung —
sie wird nicht als „pünktlich" gezählt.

**Eine zu knapp bemessene Fahrzeit erkennt man am Zeitverlust, nicht am Aufholen.** Wo
fast jeder Zug Zeit verliert, ist die angesetzte Fahrzeit zu kurz. Wo fast jeder Zug
schneller ist als geplant, ist sie zu großzügig. Das klingt selbstverständlich, wird aber
leicht verwechselt, weil beides als „Puffer" bezeichnet wird.

Ausgewertet wird der **Laufzeitanteil** zwischen zwei Bahnhöfen. Die Haltezeitreserve im
Bahnhof bleibt hier außen vor.

## Engpässe: Abschnitt, Tagesstunde, Richtung

Die Seite [Engpässe im Netz](/engpaesse) legt viele Fahrten übereinander und fragt, wo
im Netz wiederholt Verspätung entsteht. Gerechnet wird auf denselben Beiträgen wie beim
Laufweg, nur über die Zeit aggregiert.

**Immer je Zug, nie als Summe.** Eine Summe rankt zwangsläufig den dichtest befahrenen
Abschnitt nach oben — der hat mehr Züge, nicht mehr Probleme. Der Nenner ist dabei die
Zahl der Fahrten, für die der Beitrag **bestimmbar** war; sie steht als eigene Spalte
daneben, damit sichtbar bleibt, auf wie viel Beobachtung ein Mittelwert beruht.

**Die Tagesstunde ist die Wanduhrzeit der planmäßigen Ankunft** am Ende des Abschnitts.
Ein Nachtzug mit Ankunft 01:30 steht bei Stunde 1 und gehört trotzdem zum Betriebstag
davor. Für die Frage, wann im Tagesverlauf eine Strecke klemmt, ist das die richtige
Zuordnung; für die Zuordnung zum Betriebstag wäre sie falsch, und beides wird hier
getrennt gehalten.

**Abschnitte werden über den Bahnhofsnamen zusammengefasst, nicht über die
Haltestellen-ID.** Die IDs wechseln zwischen den Fahrplan-Veröffentlichungen, und der
Echtzeit-Feed verwendet mehrere Namensräume gleichzeitig. Über die ID zusammengefasst
zerfiele ein einzelner Engpass in mehrere Einträge mit je einem Bruchteil der Züge — die
Rangliste zeigte dann nicht den schlimmsten Abschnitt, sondern den mit dem einheitlichsten
Namensraum. Wo kein Name bekannt ist, steht die ID, und die Zusammenfassung bleibt
unvollständig; die Tabelle weist das aus.

**Die Richtungen werden getrennt geführt.** Ein Abschnitt, auf dem es in eine Richtung
schlechter läuft als in die andere, ist ein anderer Befund als einer, der insgesamt
langsam ist. Was der Unterschied bedeutet, sagen diese Daten nicht — er ist ein Hinweis,
keine Diagnose.

**Was diese Seite nicht zeigt:** Abschnitte außerhalb der 200 meistbefahrenen. Ausgewählt
wird nach Verkehrsmenge, nicht nach Verspätung — andernfalls suchte die Rangliste in einer
Menge, die bereits nach demselben Kriterium vorsortiert wurde, und jede Zahl darin sähe
schlimmer aus, als sie ist. Ein Engpass auf einer wenig befahrenen Strecke bleibt dadurch
unsichtbar. Ebenfalls nicht getrennt wird nach Verkehrsart; sie wäre aus dem Liniennamen
zu raten, und dafür sind zu wenige Halte benannt.

## Pünktlichkeit und Ausfälle

Die Seite [Pünktlichkeit und Ausfälle](/puenktlichkeit) führt zwei Quoten nebeneinander,
die sich **nur im Nenner** unterscheiden. Der Zähler ist bei beiden derselbe: Halte, an
denen der Zug ankam und dabei weniger als die gewählte Schwelle zu spät war.

- **„nur gefahrene Halte"** — Nenner sind die Halte, für die eine Ankunftsverspätung
  vorliegt. Das ist die übliche Lesart und beantwortet: wie pünktlich waren die Züge, die
  fuhren?
- **„alle planmäßigen Halte"** — Nenner sind alle Halte, an denen planmäßig ein Zug
  ankommen sollte, einschließlich der ausgefallenen, der ausgelassenen und derer ohne
  Meldung. Das beantwortet: kam mein Zug, und kam er rechtzeitig?

Die zweite Quote liegt nie über der ersten. Der Abstand ist keine Ungenauigkeit, sondern
die Größe, um die es geht.

**Pünktlich heißt: weniger als die Schwelle zu spät.** Zu früh gilt als pünktlich — ein
Zug vor der Zeit ist kein Pünktlichkeitsproblem, sondern gehört zum Thema Fahrplanreserve.
Ausgewiesen werden 1, 3, 6, 15 und 60 Minuten. Die branchenübliche Grenze liegt bei unter
sechs Minuten; als einzige Zahl verdeckt sie, was Reisende trifft, deshalb steht hier die
ganze Kurve.

**Der erste Halt eines Laufs zählt nie mit.** Dort kommt planmäßig nichts an. Ihn
mitzuzählen hieße, eine Lücke zu messen, wo der Fahrplan nichts vorsieht — und die Quote
sänke allein dadurch, dass ein Tag mehr kurze Läufe enthält. Fällt eine Fahrt aus, die nur
an ihrem ersten Halt beobachtet wurde, erscheint sie deshalb in der Zahl der ausgefallenen
**Fahrten**, nicht in der Zahl der ausgefallenen **Halte**.

### Wohin ein Halt gezählt wird

Jeder planmäßige Halt landet in **genau einer** von sieben Schubladen. Wo mehrere Gründe
zuträfen — ein Zug kann ausfallen und zugleich in der Umstellungsstunde liegen —, gilt
diese Rangfolge:

1. **Ausfall gemeldet** — die Quelle bezeichnet die Fahrt ausdrücklich als ausgefallen.
2. **kein Halt bedient** — im beobachteten Lauf wurde kein einziger Halt bedient. Das ist
   die Form, in der ein vollständiger Ausfall in den deutschen Daten ankommt, aber
   **abgeleitet und nicht gemeldet**: die Spalte sagt, was beobachtet wurde, nicht, dass
   der Zug nicht fuhr. Deshalb steht sie neben Nummer 1 und nicht darin.

   Für einen Teil dieser Fahrten lässt sich der Zweifel ausräumen. Deckt der beobachtete
   Laufweg den **planmäßigen vollständig** ab, wurde nicht bloß ein gestrichenes Ende
   gesehen. Verglichen wird gegen die zum Betriebstag **gültige** Fahrplan-Version — nie
   gegen die neueste, denn der Laufweg einer Fahrt ändert sich mit dem Fahrplan.

   Der Rest zerfällt in zwei Dinge, die nichts miteinander zu tun haben, und die Tabelle
   je Linie auf der Seite [Pünktlichkeit](/puenktlichkeit) weist deshalb **drei** Zahlen
   nebeneinander aus: belegt, widerlegt, und **nicht prüfbar**. Nicht prüfbar heißt, dass
   die Kennung der Fahrt in keiner gültigen Fahrplan-Version vorkommt — dann gibt es
   nichts, wogegen sich der Laufweg halten ließe.

   Diese dritte Zahl stillschweigend zu den widerlegten zu schlagen, war bis zum
   22.08.2026 der Fall und ist ein Fehler, den die Daten selbst gezeigt haben: weil der
   Linienname aus derselben Quelle stammt wie der Soll-Laufweg, traf es ausschließlich
   Fahrten **ohne Liniennummer**. Über drei Betriebstage war dort keine einzige von 182
   Fahrten belegt, bei Fahrten mit Liniennummer dagegen 97,6 bis 100 %. Der Unterschied
   zwischen zwei Betriebstagen (84,4 % gegen 61,3 % belegt) bestand vollständig aus der
   Größe dieser Gruppe und sagte nichts über den Betrieb aus.
3. **Laufweg gekappt** — ein ausgelassener Halt am Anfang oder Ende des Laufs. Der Zug
   fuhr, aber nicht die ganze Strecke. Für Reisende an den entfallenen Bahnhöfen ist das
   ein vollständiger Ausfall; in einer Ausfallquote je Zug taucht es meist nicht auf.
4. **Halt ausgelassen** — übersprungen mitten im Lauf.
5. **Zeitumstellung** — die Stunde gibt es doppelt, die Verspätung ist nicht eindeutig.
6. **keine Meldung** — planmäßig da, nicht ausgefallen, nicht ausgelassen, nicht
   mehrdeutig, und trotzdem keine Ist-Zeit. Nur hier bedeutet ein Anstieg ein Problem der
   Erhebung statt des Betriebs.
7. **gemessen** — es liegt eine Ankunftsverspätung vor.

Die sieben ergeben zusammen exakt die Zahl der planmäßigen Halte. Anders als bei der
[Abdeckung](/) auf der Startseite, wo die Gründe sich überschneiden dürfen und deshalb nie
addiert werden, ist die Zuordnung hier eindeutig.

### Was diese Quoten nicht können

**Der Nenner ist der beobachtete Laufweg, nicht der Fahrplan.** Gezählt werden Halte, die
in den Daten vorkommen. Ein Zug, der vollständig ausfiel und über den der Echtzeit-Feed
danach gar nichts mehr meldete, ist in keiner der beiden Quoten enthalten — auch nicht in
der ehrlicheren.

Beide Quoten sind damit **obere Schranken**: sie können nur besser aussehen als die
Wirklichkeit, nie schlechter. Zu schließen wäre das erst, wenn die Soll-Halte aus dem
statischen Fahrplan danebengelegt werden; bis dahin ist die Lücke hier benannt statt
stillschweigend eingerechnet.

**Bei den deutschen Daten ist die Spalte „Ausfall gemeldet" strukturell leer** — und das
ist keine Aussage über den Betrieb, sondern über die Form der Meldung. GTFS-Realtime lässt
zwei Formen zu: eine Markierung an der ganzen Fahrt, oder das Streichen jedes einzelnen
Halts. Die Spalte liest die erste; dieser Feed benutzt sie nicht. Eine Auszählung des
vollständigen bundesweiten Feeds am 21.08.2026 ergab bei **49.133 Fahrten keine einzige**
Fahrt-Markierung, dagegen **12.747** gestrichene Halte und **582 Fahrten** (1,2 %), bei
denen jeder Halt gestrichen war.

**Die betroffenen Züge fehlen deshalb nicht im Nenner** — sie stehen seit dem 21.08.2026
in der eigenen Schublade „kein Halt bedient" und gehen in `quote_planmaessig` ein.
Vorher wurden sie als „Halt ausgelassen" gezählt: dieselbe Zahl, nur ohne erkennbaren
Grund. Eine Fahrt, über die der
Feed gar nichts meldet, bleibt dagegen unsichtbar; wie häufig das ist, ist offen.

## Bahnhöfe — dieselbe Rechnung, nach Ort statt nach Linie

Die [Bahnhofsseiten](/bahnhoefe) beantworten die Pünktlichkeitsfrage für einen Ort. Die
Einordnung eines Halts ist **exakt dieselbe** wie bei den Quoten je Linie — sieben
einander ausschließende Zustände, dieselbe Rangfolge, dieselben fünf Schwellen. Sie steht
im Code an genau einer Stelle und wird von beiden Auswertungen benutzt; zwei Formulierungen
derselben Regel liefen mit der Zeit auseinander.

Der Schlüssel eines Bahnhofs ist sein **Name**, nicht seine Nummer. Die Haltestellennummern
im Fahrplan rotieren mit jeder Veröffentlichung; über die Nummer zerfiele ein Bahnhof in
mehrere Einträge mit je einem Bruchteil seiner Züge. Halte, für die kein Name bekannt ist,
haben keine Seite — eine Seite über eine Kennnummer beantwortet keine Frage.

**Ein Bahnhof ist, was der Fahrplan einen Halt nennt.** Wo Fern- und S-Bahn-Ebene getrennt
geführt werden — etwa `Frankfurt(Main)Hbf` und `Frankfurt Hbf (tief)` —, stehen sie auch
hier als zwei Einträge. Sie zusammenzufassen wäre eine Entscheidung über Bahnsteige, die
die Daten nicht hergeben.

### Drei Größen, die sich nicht addieren

Jede Bahnhofsseite weist drei Zahlen nebeneinander aus. Sie sind keine Teile einer Summe:

- **Mitgebracht** — der Verspätungsstand bei der Ankunft, gemittelt über die Halte, an
  denen er gemessen wurde. Züge vor der Zeit gehen negativ ein; sonst sähe ein Bahnhof
  besser aus, nur weil dort viele Züge zu früh sind.
- **Hier entstanden** — die Differenz zwischen Abfahrts- und Ankunftsverspätung an diesem
  Halt. Positiv heißt, der Aufenthalt hat Zeit gekostet. Der **erste** Halt eines Laufs
  zählt nicht mit: die Bereitstellung im Ausgangsbahnhof ist etwas anderes als ein
  Aufenthalt unterwegs.
- **Auf dem Weg hierher entstanden** — der Laufzeitanteil des letzten Abschnitts vor der
  Einfahrt. Er gehört dem Abschnitt, nicht dem Bahnhof, und steht nur daneben, weil erst
  beide Zahlen die Frage beantworten, ob ein Zug seinen Rückstand mitbringt oder hier
  aufsammelt.

Über mehrere Betriebstage werden diese Werte aus Summe und Zähler neu gerechnet, nie aus
Tagesmittelwerten gemittelt — sonst zählte ein ruhiger Sonntag so viel wie ein Werktag.

### Warum eine Auswahl und nicht jeder Halt

Der Feed nennt im Zielgebiet mehrere hundert Betriebsstellen beim Namen. Eine eigene Seite
hat eine Auswahl davon, und welche das sind, steht als Liste im Projekt — nicht als
Rangliste in den Daten. Zwei Gründe: eine Auswahl nach Verkehrsmenge läge fast vollständig in Frankfurt und
zeigte nicht das Gebiet, und die Adresse einer Bahnhofsseite soll zitierbar bleiben, statt
zu verschwinden, sobald ihr Bahnhof aus einer Rangliste fällt.

Die Kennzahlen selbst kennen diese Auswahl nicht: sie werden für **jede** benannte
Betriebsstelle im Gebiet gerechnet. Ausgewählt ist nur, wofür eine Seite gebaut wird.

## Die Erhebung selbst

Alle Zahlen oben beschreiben, **was** gemeldet wurde. Ob durchgehend gemeldet wurde, steht
dort nicht — ein ausgefallener Abruf hinterlässt keine Zeile, sondern eine Lücke zwischen
zwei Zeitpunkten. Deshalb wird die Erhebung getrennt geführt und auf der
[Startseite](/) ausgewiesen.

**Gezählt wird nach Kalendertag und Wanduhrstunde, nicht nach Betriebstag.** Ein Abruf ist
ein Vorgang der Sammlung; er hat keinen Betriebstag, und die Zeilen eines einzigen Abrufs
verteilen sich regelmäßig auf zwei. Die beiden Größen werden deshalb nie miteinander
verrechnet.

**Die Stunden stammen aus einem lückenlosen Gerüst**, nicht aus den Daten. Eine Stunde
ganz ohne Abruf erzeugt keine Zeile und wäre aus einer gruppierten Tabelle verschwunden —
ausgerechnet aus der, die sie zeigen soll.

**Die Abdeckung ist eine untere Schranke:** gezählt werden Abrufe, die eine Änderung
gebracht haben. Ein Abruf ohne jede Änderung hinterlässt nichts. Und sie kann über 100 %
liegen, weil beim Ausrollen kurz zwei Sammler gleichzeitig laufen; der Wert wird nicht
gedeckelt, weil ein gedeckelter Wert wie eine normale Stunde aussähe.

## Die Befundseite — worauf ihre drei Zahlen stehen

Die [Befundseite](/befunde) trifft drei Aussagen. Sie rechnet dabei nichts Neues, sondern
schneidet vorhandene Kennzahlen anders zu — drei Festlegungen gehören dazu.

**Alle drei Befunde stehen auf demselben Zeitraum.** Das ist keine Selbstverständlichkeit:
Die Quellabfragen dieses Dashboards schneiden unterschiedlich zu — Pünktlichkeit und
Engpässe auf je 30 Betriebstage, die Entstehungssicht gar nicht. Drei Befunde auf drei
verschiedenen Fenstern wären drei Aussagen, die sich nicht aufeinander beziehen lassen.
Maßgeblich ist deshalb das Fenster der Pünktlichkeitsquelle, und es steht oben auf der
Seite. Betriebstage mit unvollständiger Erhebung sind darin nicht enthalten.

**„Halte, die in der üblichen Quote nicht vorkommen"** ist die Differenz zwischen allen
Halten mit planmäßiger Ankunft und den Halten, für die eine Ankunftsverspätung vorlag. Das
sind gestrichene Halte, Halte gestrichener Läufe, ausgelassene Halte, Halte ohne
Ist-Meldung und Halte aus der Umstellungsstunde zusammen. Sie werden hier **nur für diese
eine Aussage** summiert; im Abdeckungsprotokoll stehen sie einzeln und werden dort nie
addiert, weil sich die Gründe überschneiden können. Hier ist das unbedenklich, denn die
sieben Zustände der Pünktlichkeitsrechnung schließen einander aus.

**Die Engpass-Rangliste verlangt mindestens 100 messbare Fahrten** je Abschnitt im
Zeitraum. Ohne eine solche Untergrenze steht der Abschnitt mit drei Zügen an der Spitze,
von denen einer gestört war. Die Grenze ist bewusst niedrig gewählt: Die Quelle liefert
ohnehin nur die 200 meistbefahrenen Abschnitte und greift damit schon vor. Sie steht
trotzdem in der Abfrage, weil diese Vorauswahl eine Eigenschaft der Quelle ist und keine
der Seite.

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

Vollständige Attribution, die Bedingungen für eine Weiterverwendung und die Lizenz des
Codes stehen auf der Seite [Lizenz und Quellen](/lizenz).

---

Daten von [gtfs.de](https://gtfs.de) (CC BY-SA 4.0 bzw. CC BY 4.0) — vollständige
Angaben unter [Lizenz und Quellen](/lizenz) · [Impressum](/impressum) ·
[Datenschutz](/datenschutz)
