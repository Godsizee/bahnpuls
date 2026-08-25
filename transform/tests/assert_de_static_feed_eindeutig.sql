{{ config(severity='warn') }}

-- Eine trip_id, die in **mehreren** Feeds vorkommt -- also in rv und fv zugleich.
--
-- Warum das ueberhaupt auffallen muss: aus dem Feed leitet sich die Verkehrsart ab
-- (ADR-014). Steht dieselbe Fahrt in beiden Datensaetzen, ist ihre Verkehrsart nicht
-- entscheidbar, und stg_de_static loest die Mehrdeutigkeit mit max() still auf. Eine
-- Regionalfahrt, die dabei als Fernverkehr herauskommt, faellt in **keiner** Zahl auf:
-- die Quote sieht plausibel aus, nur zaehlt sie den falschen Zug.
--
-- Deshalb warnen statt urteilen -- wie beim Namenstest daneben. Ob das ein Fehler der
-- Quelle ist oder eine Nummer, die zwei Verbuende unabhaengig vergeben, ist aus den
-- Daten allein nicht zu entscheiden; der Test nennt die Faelle, damit jemand hinsieht.
--
-- **Warnung, nicht Fehler**, aus einem zweiten Grund: der Collector hat Vorrang
-- (CLAUDE.md Regel 3). Ein harter Fehler liesse den stuendlichen Rebuild scheitern und
-- das Dashboard veralten -- wegen einer Handvoll mehrdeutiger Fahrten waere das der
-- teurere Ausgang.

select
    schluessel as trip_id,
    bezeichnung as route_kurzname,
    feed,
    feedvarianten

from {{ ref('stg_de_static') }}
where art = 'linie'
  and feedvarianten > 1
