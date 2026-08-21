---
title: Lizenz und Quellen
description: Woher die Daten stammen, unter welchen Bedingungen sie hier stehen und was das für die Weiterverwendung heißt
sidebar_position: 8
---

Zwei Dinge auf diesen Seiten haben zwei verschiedene Lizenzen: die **Daten**, die
ausgewertet werden, und der **Code**, der sie auswertet. Die Bedingungen der Daten sind
die strengeren, und sie gelten weiter, wenn jemand die Zahlen von hier weiterverwendet.
Deshalb stehen sie zuerst.

## Deutschland — Echtzeitdaten

Grundlage aller deutschen Zahlen auf diesen Seiten.

| | |
|---|---|
| Bezug | GTFS-Realtime-Stream von [gtfs.de](https://gtfs.de/de/realtime/), `realtime.gtfs.de/realtime-free.pb` |
| Lizenz | [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/) — Namensnennung und Weitergabe unter gleichen Bedingungen |
| Abrufzeitraum | seit dem 19.08.2026, fortlaufend alle 30 Sekunden |
| Gewähr | ausdrücklich keine — auf Korrektheit, ständige Verfügbarkeit und Vollständigkeit |

**Namensnennung:** Echtzeitdaten von [gtfs.de](https://gtfs.de), lizenziert unter
[CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/). Bearbeitet für dieses
Projekt: gefiltert auf das Gebiet von VRN und RMV, aus den fortlaufenden
Prognose-Schnappschüssen auf je ein Halt-Ereignis verdichtet und um abgeleitete
Kennzahlen ergänzt.

Der Stream ist kein einzelner Datensatz, sondern ein **Sammelstrom aus den Feeds
mehrerer Herausgeber**, und die haben nicht alle dieselbe Lizenz. Diese berühren das
Gebiet, das dieses Projekt aufzeichnet, nach Angabe von gtfs.de:

| Enthaltener Feed | Lizenz | Abdeckung |
|---|---|---|
| DELFI GTFS-RT Stream | CC BY-SA | Teile Deutschlands |
| SIRI Bahn (Regionalverkehr) | CC BY-SA | Teile Deutschlands |
| SIRI Rhein-Neckar-Dreieck | CC BY-SA | Nahverkehr im Rhein-Neckar-Dreieck |
| SIRI Hessen | CC BY-SA | Nahverkehr in Hessen |
| SIRI Baden-Württemberg | CC BY-SA | Nahverkehr in Baden-Württemberg |
| Verkehrsverbund Rhein-Neckar / Rhein-Nahe-Nahverkehrsverbund | [DL-DE→BY-2.0](https://www.govdata.de/dl-de/by-2-0) | Nahverkehr im Bereich VRN / RNN |

Die letzte Zeile ist die, auf die es ankommt: sie steht unter der **Datenlizenz
Deutschland — Namensnennung 2.0**, nicht unter Creative Commons. Sie verlangt
Namensnennung, aber **kein** Share-Alike. Beide Pflichten sind hier erfüllt, weil die
strengere von beiden auf den ganzen abgeleiteten Bestand angewendet wird.

Der Name dieser Zeile stammt von gtfs.de und bündelt **zwei Verkehrsverbünde**. Nur der
erste davon gehört zum Gebiet dieses Projekts: **VRN** ist der Verkehrsverbund
Rhein-Neckar, **RNN** der Rhein-Nahe-Nahverkehrsverbund im Raum Bad Kreuznach — ein
Nachbarverbund, der hier nicht ausgewertet wird. Genannt wird er trotzdem, weil beide
Verbünde denselben Feed speisen.

## Deutschland — Fahrplandaten

Aus dem Echtzeit-Feed allein lässt sich kein Bahnhofsname und keine Linie herstellen; er
liefert nur Nummern. Beides kommt aus dem statischen Fahrplan.

| | |
|---|---|
| Bezug | `download.gtfs.de/germany/rv_free/latest.zip` und `.../fv_free/latest.zip` |
| Datengrundlage | NeTEx-Datensatz des [DELFI e. V.](https://www.delfi.de/) |
| Lizenz | [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) — Namensnennung, **ohne** Share-Alike |
| Abrufzeitraum | seit dem 20.08.2026, danach wöchentlich |

**Namensnennung:** Fahrplandaten von [gtfs.de](https://gtfs.de) auf Grundlage des
NeTEx-Datensatzes des [DELFI e. V.](https://www.delfi.de/), lizenziert unter
[CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Bearbeitet: auf die
Zuordnung von Haltestellen- und Liniennummern zu Namen reduziert.

## Schweiz — opentransportdata.swiss

Die als schweizerisch gekennzeichneten Zeilen im Dashboard sind derzeit **konstruierte
Testfälle**, keine echten Betriebsdaten; das steht so auch auf der Seite
[Methodik](/methodik). Echte Daten aus dieser Quelle sind vorbereitet, aber noch nicht
eingespielt. Sobald sie es sind, gilt der Pflichttext der Nutzungsbedingungen wörtlich:

> In Publikationen und Analysen, die auf ODMCH-Daten basieren, ist die URL
> opentransportdata.swiss als Bezugsort der Rohdaten anzugeben.

Diese Quelle steht unter eigenen „Nutzungsbedingungen Open Data", nicht unter einer
Creative-Commons-Lizenz, und verlangt **kein** Share-Alike.

## Was das für die Zahlen auf dieser Seite heißt

Aus einem Bestand unter CC BY-SA 4.0 entsteht durch Auswertung eine **abgeleitete
Datenbank**, und die erbt die Bedingungen. Konkret:

- **Wer Zahlen oder Grafiken von hier übernimmt**, nennt die Quellen wie oben. Das ist
  keine Formalie, sondern die Bedingung, unter der die Daten überhaupt hier stehen
  dürfen.
- **Wird der aufbereitete Datensatz selbst veröffentlicht**, steht er unter
  [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/) — die Share-Alike-Pflicht
  stammt aus dem Echtzeit-Stream und trägt sich durch. Das ist geplant, aber noch nicht
  geschehen.
- **Ein gemischter Datensatz** aus deutschen und schweizerischen Daten weist beide
  Herkünfte getrennt aus. Der schweizerische Anteil müsste nicht unter CC BY-SA stehen;
  die beiden Pflichten zu verschmelzen wäre bequem und falsch.

## Der Code

Der gesamte Code — Collector, Transformationen, diese Seiten — liegt offen unter
[github.com/Godsizee/bahnpuls](https://github.com/Godsizee/bahnpuls) und steht unter der
**MIT-Lizenz**. Code und Daten sind getrennt zu lizenzieren: die MIT-Lizenz gilt für die
Programme, nicht für die Daten, die sie verarbeiten.

## Keine Gewähr, keine Verbindung

Bahnpuls ist ein privates Projekt und **keine amtliche Statistik**. Es steht in keiner
Verbindung zu den Datenherausgebern, zu Verkehrsverbünden oder zu
Eisenbahnverkehrsunternehmen.

Die zugrunde liegenden Daten werden von den Herausgebern ohne Gewähr auf Korrektheit,
Vollständigkeit und Verfügbarkeit bereitgestellt. Lücken oder Fehler im Feed schlagen auf
die Auswertung durch. Wo ein Wert nicht bestimmbar war, bleibt er hier leer statt
geschätzt zu werden — welche Fälle das sind und wie oft sie vorkommen, steht auf der Seite
[Methodik](/methodik) und in der Abdeckungstabelle auf der [Startseite](/).

---

[Impressum](/impressum) · [Datenschutz](/datenschutz) · [Methodik](/methodik)
