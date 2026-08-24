{{ config(severity='warn') }}

-- Jeder Bahnhof aus dem Seed `knoten` muss in mart_bahnhof vorkommen (BPULS-061). Der
-- Schluessel ist der Name, auf das Zeichen genau -- ein Tippfehler oder eine geaenderte
-- Schreibweise im Fahrplan waere sonst eine vorgerenderte Seite ohne eine einzige Zahl,
-- und zwar eine, die im Menue steht und in einer Vorfuehrung angeklickt wird.
--
-- **Warnung, kein Fehler.** Ein kleiner Knoten kann an einem einzelnen Betriebstag
-- legitim ohne Halt dastehen, und der Lauf gegen die Fixtures kennt ohnehin nur eine
-- Handvoll Bahnhoefe. Ein Fehler wuerde hier den ganzen Bau anhalten, ohne dass eine
-- Kennzahl falsch waere -- die Meldung gehoert in die Pruefung, nicht in den Abbruch.
select
    knoten.bahnhof

from {{ ref('knoten') }} as knoten
left join (
    select distinct bahnhof from {{ ref('mart_bahnhof') }}
) as vorhanden
  on vorhanden.bahnhof = knoten.bahnhof

where vorhanden.bahnhof is null
