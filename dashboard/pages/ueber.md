---
title: Über das Projekt
description: Warum jemand, der sieben Jahre Züge gefahren hat, anfängt, Verspätung zu rechnen
sidebar_position: 9
---

**Diese Seite erklärt, warum es Bahnpuls gibt und wer es rechnet.**

Sieben Jahre Lokführer im Güterverkehr, deutschlandweit, mit Berechtigungen für die Schweiz
und Österreich. Trassenkonflikt, Langsamfahrstelle, Anschlusswarten, Umlaufbindung,
Regelzuschlag — das sind hier keine Begriffe aus einer Dokumentation. Das war Berufsalltag.

Dieses Projekt ist der Versuch, aus dieser Kenntnis eine Rechnung zu machen.

## Die Frage, die auf dem Führerstand entsteht

Wer Züge fährt, sieht Verspätung nicht als Zahl am Ende, sondern als Verlauf. Man weiß, an
welcher Stelle es regelmäßig klemmt. Man weiß, wo der Fahrplan zu knapp gerechnet ist und
wo Reserve steckt, die fast nie gebraucht wird. Und man weiß, dass „zwölf Minuten zu spät"
mindestens drei verschiedene Geschichten sein können — die Statistik am Ende aber alle drei
gleich behandelt.

Was auf dem Führerstand fehlt, ist die Gegenprobe: Ist das, was man an einzelnen Tagen
erlebt, ein Muster? Oder erinnert man vor allem die Tage, an denen es schiefging?

Genau diese Frage lässt sich mit den öffentlich verfügbaren Daten beantworten — aber nur,
wenn jemand sie fortlaufend mitschreibt, bevor sie verschwinden.

## Was das Domänenwissen hier ändert

Es entscheidet nicht darüber, ob eine Zahl herauskommt. Es entscheidet darüber, ob die
richtige herauskommt:

- **Ein Zug, der früher ankommt, ist kein Datenfehler.** Er hat Fahrzeitreserve gezogen —
  ein eingebautes Werkzeug des Fahrplans, kein Schlendrian. Wer negative Werte als
  Ausreißer wegwirft, wirft genau die Beobachtung weg, die zeigt, ob die Reserve wirkt.
- **Ein ausgefallener Zug ist nicht pünktlich und nicht unpünktlich.** Er hat gar keine
  Verspätung. Rechnet man ihn als null Minuten mit, verbessert jede Streichung die Quote.
- **Betriebstag ist nicht Kalendertag.** Ein Zug, der um 01:30 fährt, gehört zum
  Fahrplan des Vortags. Wer das übersieht, verliert ausgerechnet die Nachtfahrten.
- **Ein Halt ist nicht dasselbe wie eine Fahrt.** Dieselbe Strecke wird von einer S-Bahn
  und einem Fernverkehrszug völlig unterschiedlich befahren, und der Fahrplan gibt beiden
  verschiedene Zuschläge.

Nichts davon fällt beim Programmieren auf. Alles davon verfälscht jede nachgelagerte
Kennzahl.

## Was hier bewusst nicht passiert

**Es ist kein Anklage-Projekt.** Die Zahlen beschreiben, wo im Netz Verspätung entsteht —
nicht, wer sie zu verantworten hat. Ein Abschnitt, auf dem regelmäßig Zeit verlorengeht,
kann eine Baustelle sein, eine Streckenhöchstgeschwindigkeit, ein dichter Takt oder ein
Fahrplan, der ohnehin nur bei freier Fahrt aufgeht. Welche dieser Ursachen zutrifft, sagen
diese Daten nicht, und die Seiten behaupten es auch nicht.

**Es ist keine Fahrgast-App.** Keine Abfahrtstafel, keine Reiseauskunft, keine
Benachrichtigungen. Der Wert liegt in der Historie, nicht im Jetzt.

**Es ist kein Güterverkehr** — so naheliegend das wäre. Für den Güterverkehr gibt es
keine offenen Echtzeitdaten. Der Betriebsablauf dahinter ist derselbe, die Datenlage
nicht.

## Die Grenzen, offen benannt

Die Aufzeichnung läuft seit dem 19. August 2026. Für Aussagen über eine einzelne Linie
oder einen bestimmten Bahnhof ist das zu kurz — man sieht Tage, keine Regelmäßigkeit. Was
über die Methode gesagt wird, gilt trotzdem schon; was über konkrete Strecken gesagt wird,
braucht Zeit.

Das Gebiet ist bewusst klein gehalten: **VRN und Rhein-Main**, nicht Deutschland. Dicht
befahren, Mischverkehr aus Nah- und Fernverkehr — und ein Gebiet, in dem sich jede Zahl
gegen eigene Ortskenntnis halten lässt. Eine Kennzahl, die der eigenen Erfahrung
widerspricht, ist entweder ein Fund oder ein Fehler. Beides muss man sehen können.

Wie jede Kennzahl gerechnet wird und was sie ausdrücklich nicht behauptet, steht auf der
Seite [Methodik](/methodik).

## Zur Person

Aktuell in einer Umschulung zum Fachinformatiker für Anwendungsentwicklung mit
Datenbank-Schwerpunkt. Bahnpuls ist entstanden, um zusammenzubringen, was sonst getrennt
bleibt: die Kenntnis des Betriebs und das Werkzeug, sie nachzurechnen.

Mehr dazu: [ichbin.dasdann.jetzt](https://ichbin.dasdann.jetzt/) · Der vollständige Code
liegt offen unter [github.com/Godsizee/bahnpuls](https://github.com/Godsizee/bahnpuls).

---

Daten von [gtfs.de](https://gtfs.de) (CC BY-SA 4.0 bzw. CC BY 4.0) — vollständige
Angaben unter [Lizenz und Quellen](/lizenz) · [Impressum](/impressum) ·
[Datenschutz](/datenschutz)
