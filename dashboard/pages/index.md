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
    quelle,
    case quelle when 'de_gtfsrt' then 'Deutschland, echt'
                when 'ch_istdaten' then 'Schweiz, synthetisch'
                else quelle end                  as herkunft,
    count(*)                                     as betriebstage,
    sum(fahrten)                                 as fahrten,
    sum(halte)                                   as halt_ereignisse,
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

**Vorschau im Aufbau — zwei Quellen auf sehr unterschiedlichem Grund.** Die deutschen
Zahlen sind **echt**, aus eigener Mitschrift seit dem 19.08.2026; für Aussagen über
einzelne Linien oder Bahnhöfe ist die Historie noch zu kurz, und Stationsnamen fehlen,
solange der Fahrplan-Datensatz nicht angeschlossen ist. Die schweizerischen Zahlen sind
**synthetisch** und beschreiben keinen realen Betrieb — sie prüfen die Rechenwege. Welche
Zeile woher stammt, steht überall in der Spalte `quelle`.

</Alert>

<BigValue data={echt} value=fahrten title="Fahrten (echt, DE)" />
<BigValue data={echt} value=halt_ereignisse title="Halt-Ereignisse (echt, DE)" />
<BigValue data={echt} value=bis title="Daten bis" />

<DataTable data={datenstand} rows=5>
    <Column id=herkunft title="Quelle" />
    <Column id=betriebstage title="Betriebstage" />
    <Column id=fahrten title="Fahrten" />
    <Column id=halt_ereignisse title="Halt-Ereignisse" />
    <Column id=von title="von" />
    <Column id=bis title="bis" />
</DataTable>

## Worauf diese Zahlen stehen

```sql abdeckung
select
    betriebstag,
    case quelle when 'de_gtfsrt' then 'DE, echt' else 'CH, synthetisch' end as herkunft,
    halte,
    round(100 * abdeckung_an, 1) as abdeckung_an_prozent,
    round(100 * abdeckung_ab, 1) as abdeckung_ab_prozent,
    halte_ohne_ist_an + halte_ohne_ist_ab as ohne_meldung,
    ausgefallene_halte,
    ausgelassene_halte
from bahnpuls.mart_datenqualitaet
order by betriebstag desc, quelle
```

Für wie viele Halte lag überhaupt ein gemessener Wert vor — und wo nicht, aus welchem
Grund. Ohne diesen Beleg ist jede andere Zahl auf diesen Seiten angreifbar. Die Spalte
**ohne Meldung** ist die einzige, bei der ein Anstieg ein Problem der Erhebung anzeigt und
nicht des Betriebs; Ausfälle und ausgelassene Halte sind Betrieb. Die Rechenwege stehen
auf der [Methodik](/methodik).

<DataTable data={abdeckung} rows=10>
    <Column id=betriebstag title="Betriebstag" />
    <Column id=herkunft title="Quelle" />
    <Column id=halte title="Halte" />
    <Column id=abdeckung_an_prozent title="Abdeckung an %" fmt='#,##0.0' />
    <Column id=abdeckung_ab_prozent title="Abdeckung ab %" fmt='#,##0.0' />
    <Column id=ohne_meldung title="ohne Meldung" />
    <Column id=ausgefallene_halte title="Ausfälle" />
    <Column id=ausgelassene_halte title="ausgelassen" />
</DataTable>

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
