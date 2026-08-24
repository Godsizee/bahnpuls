---
title: Bahnhof
description: Wie zuverlässig ein Zug an diesem Bahnhof ankommt — und wie viel Verspätung der Halt selbst kostet
sidebar_link: false
---

<!--
    Vorgerenderte Seite je Knoten (BPULS-061). `params.bahnhof` ist der slug aus dem Seed
    `knoten`, nicht der Name: der Link wird zitiert und darf sich nicht ändern, wenn ein
    Bahnhof umbenannt wird oder jemand die Umlautregel anfasst.

    Welche Seiten gebaut werden, steht in dashboard/svelte.config.js -- SvelteKit findet
    parametrierte Seiten sonst nur über Links im **vorgerenderten** HTML, und die Tabelle
    auf der Übersichtsseite entsteht erst im Browser.
-->

```sql kennzahl
select
    any_value(bahnhof)                          as bahnhof,
    any_value(verbund)                          as verbund,
    strftime(min(betriebstag), '%d.%m.%Y')      as von,
    strftime(max(betriebstag), '%d.%m.%Y')      as bis,
    count(distinct betriebstag)                 as tage,

    sum(zuege)                                  as zuege,
    sum(halte_mit_ankunft)                      as halte_mit_ankunft,
    sum(halte_gemessen)                         as halte_gemessen,
    sum(halte_puenktlich)                       as halte_puenktlich,
    sum(halte_ausgefallen + halte_unbedienter_lauf + halte_verkuerzt + halte_ausgelassen)
                                                as halte_nicht_bedient,
    sum(halte_ohne_meldung)                     as halte_ohne_meldung,

    100.0 * sum(halte_puenktlich) / nullif(sum(halte_gemessen), 0)     as quote_gemessen,
    100.0 * sum(halte_puenktlich) / nullif(sum(halte_mit_ankunft), 0)  as quote_planmaessig,

    -- Über die Tage aus Summe und Zähler neu gerechnet, nie aus Mittelwerten gemittelt.
    sum(verspaetung_an_sek_summe)  / nullif(sum(verspaetung_an_messwerte), 0) as mitgebracht_sek,
    sum(haltezeit_delta_sek_summe) / nullif(sum(haltezeit_messwerte), 0)      as hier_sek,
    sum(laufzeit_delta_sek_summe)  / nullif(sum(laufzeit_messwerte), 0)       as zulauf_sek

from bahnpuls.bahnhof
where slug = '${params.bahnhof}'
  and schwelle_sek = 360
```

# <Value data={kennzahl} column=bahnhof/>

<Value data={kennzahl} column=zuege fmt='#,##0'/> Züge an
<Value data={kennzahl} column=tage fmt='#,##0'/> Betriebstagen,
<Value data={kennzahl} column=von/> bis <Value data={kennzahl} column=bis/>. Verbund:
<Value data={kennzahl} column=verbund/>.

<BigValue data={kennzahl} value=quote_planmaessig fmt='#,##0.0' title="Pünktlich unter 6 Min. (%)" />
<BigValue data={kennzahl} value=quote_gemessen fmt='#,##0.0' title="dieselbe Quote, nur über gemessene Halte (%)" />
<BigValue data={kennzahl} value=halte_mit_ankunft fmt='#,##0' title="Halte mit planmäßiger Ankunft" />
<BigValue data={kennzahl} value=halte_nicht_bedient fmt='#,##0' title="davon nicht bedient" />

Die erste Zahl ist die strengere: in ihrem Nenner stehen **alle** Halte, an denen
planmäßig ein Zug ankommen sollte — auch die ausgefallenen und ausgelassenen. Die zweite
zählt nur, wofür eine Ankunftszeit gemeldet wurde, und ist damit die Quote, die man sonst
liest. Der Abstand zwischen beiden ist kein Rundungsfehler, sondern das, was übliche
Statistiken weglassen.

## Mitgebracht oder hier entstanden?

```sql anteile
select 'mit dem Zug angekommen (Rückstand bei der Einfahrt)' as art,
       mitgebracht_sek as sekunden
from ${kennzahl}
union all
select 'auf dem letzten Abschnitt davor entstanden', zulauf_sek from ${kennzahl}
union all
select 'hier am Bahnsteig entstanden', hier_sek from ${kennzahl}
```

<BarChart
    data={anteile}
    x=art
    y=sekunden
    swapXY=true
    sort=false
    yAxisTitle="Sekunden je gemessenem Halt"
    title="Drei verschiedene Größen — nicht drei Teile einer Summe"
    emptySet=warn
    emptyMessage="Für diesen Bahnhof liegen im Zeitraum keine messbaren Halte vor."
/>

Die drei Balken addieren sich **nicht**. Der erste ist ein Stand — wie spät die Züge hier
ankommen. Die beiden anderen sind Zuwächse: was auf dem letzten Abschnitt vor der Einfahrt
dazukam und was der Aufenthalt selbst gekostet hat. Ein negativer Wert heißt, dass dort
unter dem Strich Verspätung abgebaut wurde.

**Betrieblich sind das verschiedene Dinge.** Ein hoher Rückstand bei der Einfahrt bei
kleinem Zuwachs vor Ort heißt: der Bahnhof erbt sein Problem von der Strecke. Wächst die
Verspätung dagegen am Bahnsteig, liegt es näher am Ort — Fahrgastwechsel, Anschlusswarten,
Disposition, Personalwechsel.

## Nicht eine Schwelle, sondern eine Kurve

```sql kurve
select
    schwelle_min,
    100.0 * sum(halte_puenktlich) / nullif(sum(halte_gemessen), 0)    as quote_gemessen,
    100.0 * sum(halte_puenktlich) / nullif(sum(halte_mit_ankunft), 0) as quote_planmaessig
from bahnpuls.bahnhof
where slug = '${params.bahnhof}'
group by schwelle_min
order by schwelle_min
```

<LineChart
    data={kurve}
    x=schwelle_min
    y={["quote_planmaessig", "quote_gemessen"]}
    xAxisTitle="Schwelle in Minuten"
    yAxisTitle="Anteil pünktlicher Halte (%)"
    yMin=0
    yMax=100
    title="Wie sich die Quote mit der Schwelle verschiebt"
    emptySet=warn
    emptyMessage="Für diesen Bahnhof liegen im Zeitraum keine Halte vor."
/>

Die branchenübliche Grenze liegt bei unter sechs Minuten. Als einzige Zahl verdeckt sie
genau die Fälle, um die es Reisenden geht: 5:59 ist pünktlich, der Vier-Minuten-Anschluss
ist trotzdem weg.

## Über die Tage

```sql taeglich
select
    betriebstag,
    sum(zuege)                                                        as zuege,
    100.0 * sum(halte_puenktlich) / nullif(sum(halte_mit_ankunft), 0) as quote_planmaessig,
    sum(haltezeit_delta_sek_summe) / nullif(sum(haltezeit_messwerte), 0) as hier_sek
from bahnpuls.bahnhof
where slug = '${params.bahnhof}'
  and schwelle_sek = 360
group by betriebstag
order by betriebstag
```

<LineChart
    data={taeglich}
    x=betriebstag
    y=quote_planmaessig
    yAxisTitle="pünktlich unter 6 Min. (%)"
    yMin=0
    yMax=100
    title="Pünktlichkeit je Betriebstag"
    emptySet=warn
    emptyMessage="Für diesen Bahnhof liegen im Zeitraum keine Betriebstage vor."
/>

<DataTable data={taeglich} rows=10 emptySet=warn
    emptyMessage="Für diesen Bahnhof liegen im Zeitraum keine Betriebstage vor.">
    <Column id=betriebstag title="Tag" fmt='dd"."mm"."yyyy' />
    <Column id=zuege title="Züge" fmt="#,##0" />
    <Column id=quote_planmaessig title="pünktlich (6 Min.) %" fmt="#,##0.0" />
    <Column id=hier_sek title="hier entstanden (s je Halt)" fmt="#,##0.0" />
</DataTable>

## Woher die Züge kommen

```sql zulaeufe
with dieser as (
    select any_value(bahnhof) as bahnhof
    from bahnpuls.bahnhof
    where slug = '${params.bahnhof}'
)
select
    coalesce(von_stop_name, von_stop_id)                              as von,
    sum(zuege)                                                        as zuege,
    sum(laufzeit_messwerte)                                           as messbar,
    sum(laufzeit_delta_sek_summe)  / nullif(sum(laufzeit_messwerte), 0)  as laufzeit_sek,
    sum(haltezeit_delta_sek_summe) / nullif(sum(haltezeit_messwerte), 0) as haltezeit_sek

from bahnpuls.mart_verspaetungsentstehung, dieser
where nach_stop_name = dieser.bahnhof
group by von
-- Ohne Untergrenze stünde hier der Zulauf mit zwei Zügen und einem gestörten davon.
having sum(laufzeit_messwerte) >= 20
order by laufzeit_sek desc
limit 10
```

<DataTable data={zulaeufe} rows=10 emptySet=warn
    emptyMessage="Kein Zulauf erreicht im Zeitraum 20 messbare Fahrten.">
    <Column id=von title="letzter Halt davor" />
    <Column id=zuege title="Züge" fmt="#,##0" />
    <Column id=messbar title="davon messbar" fmt="#,##0" />
    <Column id=laufzeit_sek title="auf dem Abschnitt entstanden (s je Zug)" fmt="#,##0.0" contentType=colorscale colorScale=negative />
    <Column id=haltezeit_sek title="hier entstanden (s je Halt)" fmt="#,##0.0" />
</DataTable>

Sortiert danach, was ein Zug auf dem letzten Abschnitt vor der Einfahrt im Durchschnitt
verliert — nicht danach, wie viel dort insgesamt zusammenkommt. Eine Summe setzte immer
die dichtest befahrene Zufahrt nach oben, ganz gleich wie gut sie läuft.

## Was diese Seite nicht sagt

- **Der Nenner ist der beobachtete Laufweg, nicht der Fahrplan.** Ein Zug, von dem der
  Feed nie einen Halt gemeldet hat, fehlt auch hier. Beide Quoten sind damit obere
  Schranken: sie können nur besser aussehen als die Wirklichkeit, nie schlechter.
- **Ein Bahnhof ist hier, was der Fahrplan einen Halt nennt.** Wo Fern- und S-Bahn-Ebene
  getrennt geführt werden, stehen sie auch hier als zwei Einträge.
- **Der Zeitraum ist kurz.** 30 Betriebstage aus einer Sammlung, die am 19.08.2026 begonnen
  hat, zeigen Tage — keine Regelmäßigkeit. Zwei Betriebstage sind ausgenommen, weil die
  Erhebung an ihnen nachweislich schief gegriffen hat.
- **Verspätung ist hier Abweichung vom Fahrplan**, keine Schuldzuweisung. Warum ein Zug
  steht, sagen diese Daten nicht.

Wie die Kennzahlen im Einzelnen gerechnet werden, steht auf der
[Methodik-Seite](/methodik). Zurück zur [Übersicht aller Bahnhöfe](/bahnhoefe).
