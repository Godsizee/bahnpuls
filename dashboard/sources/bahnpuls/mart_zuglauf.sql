-- Bewusst **nicht** der ganze Mart: Evidence liefert seine Daten an den Browser aus, und
-- `select *` ergab bei echten Daten 707.585 Zeilen und 347 MB je Seitenaufruf -- die
-- Seite war damit unbenutzbar, im Browser als Timeout beim Initialisieren der Datenbank
-- sichtbar. Bei 36 Fixture-Zeilen war davon nichts zu merken.
--
-- Die Laufweg-Seite zeigt immer genau eine Fahrt. Ausgeliefert wird deshalb eine
-- begrenzte Stichprobe des zuletzt geladenen Betriebstags; die Seite sagt das auch.
-- Uebersichtszahlen kommen aus mart_datenqualitaet, nicht von hier -- sonst waere die
-- Stichprobe als Gesamtzahl ausgewiesen.
--
-- Der eigentliche Umbau (serverseitige Abfrage oder vorbereitete Einzelfahrten) ist
-- BPULS-056. Das hier ist die Grenze, die aus der Seite ueberhaupt erst etwas
-- Anzeigbares macht.
with letzte_tage as (

    -- Je Quelle der zuletzt geladene Betriebstag. Nicht global das Maximum: die
    -- synthetischen CH-Fixtures reichen bis in den Oktober und wuerden die echten
    -- deutschen Tage sonst vollstaendig verdecken.
    select quelle, max(betriebstag) as tag
    from mart_zuglauf
    group by quelle

),

auswahl as (

    select zuglauf.trip_key
    from mart_zuglauf as zuglauf
    join letzte_tage
      on  zuglauf.quelle      = letzte_tage.quelle
      and zuglauf.betriebstag = letzte_tage.tag
    group by zuglauf.quelle, zuglauf.trip_key
    -- Eine Fahrt mit einem einzigen gemeldeten Halt ergibt keinen Laufweg.
    having count(*) >= 2
    qualify row_number() over (
        partition by zuglauf.quelle order by zuglauf.trip_key
    ) <= 150

)

select zuglauf.*
from mart_zuglauf as zuglauf
join auswahl using (trip_key)
