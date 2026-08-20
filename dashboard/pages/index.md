---
title: Bahnpuls
description: Wo Verspätung im Schienenverkehr entsteht — auf der Strecke oder im Bahnhof
---

Öffentliche Statistiken beantworten, **wie viel** Verspätung es gab. Bahnpuls fragt,
**wo sie entsteht**: auf dem Abschnitt zwischen zwei Betriebsstellen oder während des
Halts im Bahnhof. Das sind zwei verschiedene Befunde mit zwei verschiedenen Maßnahmen —
und die Unterscheidung fehlt in praktisch jedem Verspätungs-Dashboard.

Wie die Kennzahlen gerechnet werden, steht vollständig auf der [Methodik](/methodik).

```sql datenstand
select
    count(distinct betriebstag)                  as betriebstage,
    count(distinct trip_key)                     as fahrten,
    count(*)                                     as halt_ereignisse,
    min(betriebstag)                             as von,
    max(betriebstag)                             as bis
from bahnpuls.mart_zuglauf
```

<Alert status=warning>

**Datenstand: synthetische Testdaten.** Die hier gezeigten Zahlen stammen aus
konstruierten Fixtures, nicht aus echtem Betrieb — sie prüfen die Rechenwege, nicht die
Wirklichkeit. Die Sammlung eigener Daten läuft seit dem 19.08.2026; das Schweizer
Ist-Daten-Archiv ist noch nicht eingebunden.

</Alert>

<BigValue data={datenstand} value=fahrten title="Fahrten" />
<BigValue data={datenstand} value=halt_ereignisse title="Halt-Ereignisse" />
<BigValue data={datenstand} value=betriebstage title="Betriebstage" />

## Wo entsteht die Verspätung?

```sql aufteilung
select
    sum(laufzeit_delta_sek_summe)  / 60.0 as strecke_min,
    sum(haltezeit_delta_sek_summe) / 60.0 as bahnhof_min,
    sum(ausgefallene_halte)               as ausgefallene_halte,
    sum(ausgelassene_halte)               as ausgelassene_halte
from bahnpuls.mart_verspaetungsentstehung
```

Netto über alle Abschnitte — aufgeholte Zeit ist gegengerechnet, ein negativer Wert
heißt also: unter dem Strich wurde dort Fahrplanreserve genutzt.

<BigValue data={aufteilung} value=strecke_min title="Auf der Strecke (Min.)" fmt='#,##0.0' />
<BigValue data={aufteilung} value=bahnhof_min title="Im Bahnhof (Min.)" fmt='#,##0.0' />
<BigValue data={aufteilung} value=ausgefallene_halte title="Halte ausgefallener Züge" />

Ausfälle stehen bewusst **neben** den Verspätungswerten, nie darin: ein ausgefallener Zug
hat keine Verspätung, und wer ihn als Verspätung 0 zählt, verbessert mit jeder Streichung
die Statistik.

## Abschnitte mit dem größten Laufzeitverlust

```sql top_abschnitte
select
    von_stop_name || ' → ' || nach_stop_name       as abschnitt,
    betriebstag,
    zuege,
    laufzeit_messwerte                             as messwerte,
    laufzeit_delta_sek_je_zug  / 60.0              as laufzeit_min_je_zug,
    haltezeit_delta_sek_je_zug / 60.0              as haltezeit_min_je_zug
from bahnpuls.mart_verspaetungsentstehung
where laufzeit_messwerte > 0
order by laufzeit_delta_sek_je_zug desc
limit 10
```

<DataTable data={top_abschnitte} rows=10>
    <Column id=abschnitt title="Abschnitt" />
    <Column id=betriebstag title="Betriebstag" fmt='dd.mm.yyyy' />
    <Column id=zuege title="Züge" />
    <Column id=messwerte title="davon messbar" />
    <Column id=laufzeit_min_je_zug title="Laufzeit je Zug (Min.)" fmt='#,##0.0' contentType=colorscale colorScale=negative />
    <Column id=haltezeit_min_je_zug title="Haltezeit je Zug (Min.)" fmt='#,##0.0' />
</DataTable>

**Je Zug normiert, nicht als Summe.** Eine Rohsumme rankt immer den dichtest befahrenen
Abschnitt nach oben, unabhängig davon, wie gut er läuft. Die Spalte „davon messbar" zeigt,
auf wie vielen Fahrten der Wert tatsächlich beruht — Ausfälle und unvollständige Meldungen
gehen nicht in den Nenner ein.

Den vollständigen Verlauf einer einzelnen Fahrt zeigt die Seite
[Laufweg einer Fahrt](/laufweg).
