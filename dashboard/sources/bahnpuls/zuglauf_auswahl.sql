-- Bewusst **nicht** der ganze Mart, und deshalb auch nicht so benannt: Evidence liefert
-- seine Quelldaten an den Browser aus, `select * from mart_zuglauf` ergab bei echten
-- Daten 707.585 Zeilen und 347 MB je Seitenaufruf. Die Seite war damit unbenutzbar
-- (Timeout beim Initialisieren der Datenbank im Browser) -- bei 36 Fixture-Zeilen war
-- davon nichts zu merken. Der Name sagt an jeder Aufrufstelle, dass hier eine Auswahl
-- steht und keine Gesamtheit; `mart_zuglauf` hatte genau das verdeckt.
--
-- **Die Grenze, ausgeschrieben** (BPULS-056): je Quelle die letzten drei Betriebstage,
-- darin je Tag und Linie die ersten sechs Fahrten nach planmaessiger Abfahrt.
--
-- Drei Entscheidungen dahinter, die nicht aus der Aufgabe folgen:
--
--   1. **Quote je Linie, nicht je Tag insgesamt.** Der Vorgaenger schnitt mit
--      `row_number() over (order by trip_key)` alphabetisch ab. Reproduzierbar, aber
--      sinnlos: welche Linien uebrigbleiben, entscheidet die Sortierung der Schluessel.
--      Eine Quote je Linie laesst **jede** Linie vorkommen -- und genau daran haengt der
--      Linienfilter der Seite. Ein Filter, der die halben Linien gar nicht kennt, waere
--      schlimmer als keiner.
--   2. **Drei Tage, nicht einer.** Bei einem einzigen Tag waere ein Betriebstag-Filter
--      eine Auswahlliste mit einem Eintrag. Drei Tage kosten das Dreifache an Zeilen und
--      machen die Frage "wie war gestern" ueberhaupt erst stellbar.
--   3. **Nur Halte in VRN + RMV** (BPULS-075). Der Collector sammelt Fernverkehrslaeufe
--      mit ihrem **ganzen** Laufweg; ein ICE braechte sonst Muenchen und Hamburg mit.
--      Der Laufzeitanteil des Einfahrtsabschnitts faellt damit weg -- er rechnet gegen
--      einen Halt, der hier nicht mehr steht, und der Wasserfall ginge sonst nicht auf.
--      Die **Ankunftsverspaetung am ersten Gebietshalt bleibt**: an ihr ist ein Zug, der
--      die Verspaetung mitbringt, von einem zu unterscheiden, der sie hier aufsammelt.
--   4. **Was die Seite nicht zeichnet, bleibt draussen** (von_stop_*, abschnitt_direkt,
--      ist_endgueltig, die Soll-Zeitstempel je Halt). Uebersichtszahlen kommen aus
--      mart_datenqualitaet, nie von hier -- sonst stuende die Stichprobe als Gesamtzahl
--      auf der Startseite.
--
-- Drei und sechs sind an Fixtures gewaehlt, nicht an Produktionsdaten gemessen. Wird die
-- Seite traege, sind das die beiden Schrauben -- und dann bitte messen, nicht raten.
with tage as (

    -- Je Quelle die letzten drei Betriebstage, nicht global die letzten drei: die
    -- Partition ist die Naht, an der eine zweite Quelle andockt, ohne dass ihre
    -- Betriebstage die der ersten verdecken.
    select quelle, betriebstag
    from mart_zuglauf
    group by quelle, betriebstag
    qualify dense_rank() over (partition by quelle order by betriebstag desc) <= 3

),

fahrten as (

    select
        zuglauf.quelle,
        zuglauf.betriebstag,
        zuglauf.trip_key,
        coalesce(zuglauf.route_kurzname, 'ohne Liniennummer') as linie,
        -- ADR-014. Aendert die Vorauswahl nicht: beide haengen funktional an der Linie,
        -- die schon im group by steht -- sechs Fahrten je Linie bleiben sechs.
        coalesce(zuglauf.verkehrsart, 'ohne Angabe')          as verkehrsart,
        coalesce(zuglauf.gattung, 'ohne Angabe')              as gattung,
        min(zuglauf.soll_ab)                                  as ab_soll

    from mart_zuglauf as zuglauf
    join tage
      on  tage.quelle      = zuglauf.quelle
      and tage.betriebstag = zuglauf.betriebstag
    where zuglauf.halt_im_gebiet
    group by 1, 2, 3, 4, 5, 6
    -- Eine Fahrt mit einem einzigen gemeldeten Halt ergibt keinen Laufweg.
    having count(*) >= 2
    -- nulls last: eine Fahrt ohne planmaessige Abfahrt am ersten gemeldeten Halt (der
    -- Zug war beim Beobachtungsbeginn schon unterwegs) verdraengt sonst die Fahrten,
    -- fuer die eine Zeit bekannt ist.
    qualify row_number() over (
        partition by zuglauf.quelle, zuglauf.betriebstag,
                     coalesce(zuglauf.route_kurzname, 'ohne Liniennummer')
        order by min(zuglauf.soll_ab) nulls last, zuglauf.trip_key
    ) <= 6

)

select
    zuglauf.betriebstag,
    zuglauf.quelle,
    zuglauf.trip_key,
    fahrten.linie,
    fahrten.verkehrsart,
    fahrten.gattung,
    fahrten.ab_soll,
    zuglauf.halt_nr,

    -- Wo keine Fahrplan-Version den Halt kennt, bleibt stop_name NULL; dann steht die ID
    -- da, sichtbar als das, was sie ist. Eine ID als Namen auszugeben waere gelogen, sie
    -- wegzulassen liesse den Laufweg mit Luecken dastehen.
    coalesce(zuglauf.stop_name, zuglauf.stop_id) as halt,
    zuglauf.stop_name is not null                as name_bekannt,

    -- Nur wo der Fahrplan Ankunft **und** Abfahrt vorsieht, gibt es ueberhaupt eine
    -- Haltezeit. Am Start fehlt die Ankunft, am Ende die Abfahrt -- planmaessig nicht
    -- vorhanden ist nicht dasselbe wie nicht bestimmbar (Methodik-Seite).
    zuglauf.soll_an is not null and zuglauf.soll_ab is not null as halt_mit_aufenthalt,

    zuglauf.delay_an_sek,
    zuglauf.delay_ab_sek,

    -- Nur fuer Abschnitte, die vollstaendig im Gebiet liegen. Der Einfahrtsabschnitt
    -- rechnet gegen einen Halt, der auf dieser Seite nicht mehr steht -- sein Wert waere
    -- nicht nachvollziehbar und stuende zugleich in keinem Aggregat.
    case when zuglauf.abschnitt_im_gebiet then zuglauf.laufzeit_delta_sek end
        as laufzeit_delta_sek,
    zuglauf.haltezeit_delta_sek,
    zuglauf.halt_ausgelassen,
    zuglauf.zug_ausgefallen,
    zuglauf.zeitumstellung_mehrdeutig,

    -- War die Erhebung an diesem Betriebstag vollstaendig (BPULS-079)? Der Tag bleibt
    -- waehlbar -- eine einzelne Fahrt ist richtig aufgezeichnet, schief ist die
    -- **Auswahl** der Fahrten --, aber die Betriebstagsliste sagt es dazu.
    zuglauf.erhebung_vollstaendig

from mart_zuglauf as zuglauf
join fahrten
  on  zuglauf.quelle   = fahrten.quelle
  and zuglauf.trip_key = fahrten.trip_key
where zuglauf.halt_im_gebiet
