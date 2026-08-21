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
    quelle,
    case quelle when 'de_gtfsrt' then 'Deutschland — echte Aufzeichnung'
                when 'ch_istdaten' then 'Schweiz — Testdaten zur Prüfung der Rechenwege'
                else quelle end                  as herkunft,
    count(*)                                     as tage,
    sum(fahrten)                                 as fahrten,
    sum(halte)                                   as halte,
    min(betriebstag)                             as von,
    max(betriebstag)                             as bis
from bahnpuls.mart_datenqualitaet
group by quelle
order by quelle desc
```

```sql echt
select * from ${datenstand} where quelle = 'de_gtfsrt'
```

<Alert status=warning>

**Diese Seite ist im Aufbau, und zwei sehr verschiedene Dinge stehen nebeneinander.**

Die deutschen Zahlen sind **echt**. Sie stammen aus der eigenen Aufzeichnung, die seit dem
19. August 2026 läuft — also erst seit wenigen Tagen. Für Aussagen über eine bestimmte
Linie oder einen bestimmten Bahnhof ist das zu wenig; man sieht ein paar Tage, keine
Regelmäßigkeit.

Die schweizerischen Zahlen sind **erfunden**. Sie sind ein Prüfstand: konstruierte Fälle,
an denen sich nachweisen lässt, dass die Rechnung stimmt — ein Zug über Mitternacht, ein
ausgefallener Zug, eine Nacht mit Zeitumstellung. Sie beschreiben **keinen realen
Betrieb**.

In jeder Tabelle steht dabei, woher eine Zeile stammt.

</Alert>

<BigValue data={echt} value=fahrten title="Aufgezeichnete Fahrten" />
<BigValue data={echt} value=halte title="Davon einzelne Halte" />
<BigValue data={echt} value=bis title="Aufgezeichnet bis" />

<DataTable data={datenstand} rows=5>
    <Column id=herkunft title="Woher die Zahlen stammen" />
    <Column id=tage title="Tage" />
    <Column id=fahrten title="Fahrten" />
    <Column id=halte title="Halte" />
    <Column id=von title="von" />
    <Column id=bis title="bis" />
</DataTable>

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
    <Column id=betriebstag title="Tag" fmt="dd.mm.yyyy" />
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
    case quelle when 'de_gtfsrt' then 'Deutschland' else 'Schweiz (Testdaten)' end as herkunft,
    halte,
    round(100 * abdeckung_an, 1) as gemessen_an,
    round(100 * abdeckung_ab, 1) as gemessen_ab,
    halte_ohne_ist_an + halte_ohne_ist_ab as keine_meldung,
    round(100 * namensquote, 1) as name_bekannt,
    ausgefallene_halte,
    ausgelassene_halte
from bahnpuls.mart_datenqualitaet
order by betriebstag desc, quelle
```

Keine Auswertung ist besser als ihre Datengrundlage. Deshalb steht hier offen, für wie
viele Halte überhaupt ein Wert vorlag — und woran es lag, wenn nicht.

Vier Gründe kann es haben, dass ein Halt keine Zahl trägt: Der Zug ist **ausgefallen**,
der Halt wurde **ausgelassen**, die Zeit fiel in die Nacht der **Zeitumstellung** (dort
gibt es eine Stunde doppelt, die Rechnung ist dann nicht eindeutig) — oder es kam
**einfach keine Meldung**. Nur der letzte Fall ist ein Problem der Messung. Die anderen
drei sind Betrieb und gehören zum Bild.

<DataTable data={abdeckung} rows=10>
    <Column id=betriebstag title="Tag" />
    <Column id=herkunft title="Herkunft" />
    <Column id=halte title="Halte" />
    <Column id=gemessen_an title="Ankunft gemessen %" fmt="#,##0.0" />
    <Column id=gemessen_ab title="Abfahrt gemessen %" fmt="#,##0.0" />
    <Column id=keine_meldung title="keine Meldung" />
    <Column id=name_bekannt title="Bahnhofsname bekannt %" fmt="#,##0.0" />
    <Column id=ausgefallene_halte title="Ausfälle" />
    <Column id=ausgelassene_halte title="ausgelassen" />
</DataTable>

---

Wie eine einzelne Fahrt Halt für Halt verläuft, zeigt die Seite
[Laufweg einer Fahrt](/laufweg). Wer genau wissen will, wie gerechnet wird — mit allen
Annahmen und ihren Grenzen —, findet das auf der Seite [Methodik](/methodik).

---

Daten von [gtfs.de](https://gtfs.de) (CC BY-SA 4.0 bzw. CC BY 4.0) — vollständige
Angaben unter [Lizenz und Quellen](/lizenz) · [Impressum](/impressum) ·
[Datenschutz](/datenschutz)
