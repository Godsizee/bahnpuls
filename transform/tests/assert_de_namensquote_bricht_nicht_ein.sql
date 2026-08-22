{{ config(severity = 'warn') }}

-- Meldet Betriebstage, an denen die Namensquote gegenueber den Vortagen **einbricht** --
-- weniger als die Haelfte des hoechsten Werts der letzten 30 Betriebstage.
--
-- **Warum das ueberhaupt schiefgehen kann:** die Halte-Namen entstehen ueber die stop_id
-- aus dem statischen Fahrplan, und der Echtzeit-Feed wechselt den Namensraum dieser IDs
-- im laufenden Betrieb (Q6). Am 2026-08-22 ist die Quote zwischen 09 und 13 Uhr von
-- 100 % auf 4 % gefallen, weil der Feed auf einen ID-Vorrat umgestellt hat, den die
-- einzige geladene Fahrplan-Version nicht kennt. Der Tag lief weiter, kein Task wurde
-- rot, keine Zeile fehlte -- die Seite zeigte nur ploetzlich Zahlen statt Bahnhoefen.
-- Bemerkt wurde es beim Nachmessen aus anderem Anlass (BPULS-069).
--
-- Ein Einbruch ist kein Fehler in der Transformation, deshalb Warnung: der Seitenbau
-- darf daran nicht haengen. Er ist aber auch keine Betriebseigenschaft, die man
-- kommentarlos in A1/A2 mitrechnet -- ohne Namen faellt der Bezug zur Station weg, und
-- die verbliebenen Treffer koennen Kollisionen zwischen zwei Namensraeumen sein.
--
-- **Groessenschwelle statt aller Tage:** ein Betriebstag mit 23 Halten (vorab gemeldete
-- Ausfaelle, Betriebstag in der Zukunft -- BPULS-068) traegt keine belastbare Quote und
-- brachte den Test sonst bei jedem Lauf zum Anschlagen. Die Schwelle gilt fuer den
-- geprueften Tag **und** fuer die Vergleichstage.
--
-- Der Preis dieser Schwelle: gegen die Fixtures sieht der Test **keinen einzigen Tag** an
-- und ist gruen, weil er nichts angesehen hat. Belegt ist er deshalb an den
-- ausgelieferten Produktionsdaten, in beide Richtungen -- Gegenprobe und Zahlen in
-- transform/README.md.
with tage as (

    select
        betriebstag,
        halte,
        namensquote

    from {{ ref('mart_datenqualitaet') }}
    where quelle = 'de_gtfsrt'
      and halte >= 1000

),

mit_vergleich as (

    select
        betriebstag,
        halte,
        namensquote,
        -- Hoechstwert statt Median: eine dauerhaft gefallene Quote soll weiter melden,
        -- bis der alte Stand aus dem Fenster gelaufen ist. Ein Median haette den
        -- Einbruch nach drei Tagen selbst zur Normalitaet erklaert.
        max(namensquote) over (
            order by betriebstag
            rows between 30 preceding and 1 preceding
        ) as bester_vortag

    from tage

)

select
    betriebstag,
    halte,
    round(namensquote, 4)   as namensquote,
    round(bester_vortag, 4) as bester_vortag

from mit_vergleich
where bester_vortag is not null
  and namensquote < 0.5 * bester_vortag
