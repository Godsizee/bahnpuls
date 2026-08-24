{{ config(severity = 'warn') }}

-- Keine Fahrt, die im Bahnfahrplan ihres Betriebstags steht, darf als
-- gebietsfremd ausgeschlossen werden (BPULS-073).
--
-- **Warum das ueberhaupt eine Frage ist:** int_de_gebietsfremd entscheidet ueber
-- ein Verhaeltnis -- gehen mehr Halte einer Fahrt nur im Nahverkehrsfeed auf als
-- im Bahnfahrplan, gilt sie als fremd. Das ist ein Indiz, kein Beweis, und es
-- haengt daran, dass die Halte der Fahrt im Bahnfahrplan aufloesen. Genau das
-- kann brechen: die stop_id-Werte rotieren zwischen Veroeffentlichungen fast
-- vollstaendig, und eine fehlende Fahrplanversion macht aus einer Bahnfahrt eine
-- Fahrt ohne bekannte Halte.
--
-- Die trip_id ist der schaerfere Zeuge, taugt aber nur **versionsgenau**: sie
-- rotiert mit, und der Nummernkreis des Nahverkehrsfeeds ist so dicht besetzt,
-- dass eine alte Bahn-trip_id mit hoher Wahrscheinlichkeit eine heutige
-- Busfahrt trifft. Innerhalb **einer** Version ist sie dagegen eindeutig:
-- gemessen an v=2026-08-22 haben die 108.688 rv- und 5.589 fv-Fahrten mit den
-- 1.673.963 nv-Fahrten **keine einzige** Nummer gemeinsam. Deshalb steht hier
-- die zum Betriebstag gueltige Version (Regel 9), nicht die Vereinigung.
--
-- **Warnung, kein Fehler:** ein Treffer bedeutet, dass die Bewertung zu scharf
-- ist -- schlimm genug, aber die Rohdaten liegen unversehrt, und der Befund ist
-- in der Transformationsschicht reparierbar. Einen Seitenbau dafuer abzubrechen
-- naehme dem Dashboard die Anzeige, an der man das Problem ueberhaupt sieht.
--
-- An Live-Daten gegengeprueft (2026-08-23, ein Abruf des Feeds, 1.288 Fahrten im
-- Gebiet): von 642 als fremd bewerteten Fahrten stand **keine** in rv oder fv,
-- alle 642 im Nahverkehrsfeed. Der Test hat also einen belegten Nullpunkt.
-- int_de_gebietsfremd fuehrt nur den trip_key; die trip_id, gegen die der
-- Fahrplan aufloest, steckt im Staging-Modell daneben.
with kandidaten as (

    select distinct
        fremd.betriebstag,
        fremd.trip_key,
        roh.trip_id

    from {{ ref('int_de_gebietsfremd') }} as fremd
    join {{ ref('stg_de_gtfsrt') }} as roh
      on roh.trip_key = fremd.trip_key
    where fremd.gebietsfremd

),

im_bahnfahrplan as (

    {{ gueltige_fahrplanversion('kandidaten') }}

)

select
    kandidaten.betriebstag,
    kandidaten.trip_key,
    im_bahnfahrplan.static_version,
    im_bahnfahrplan.feed

from kandidaten
join im_bahnfahrplan using (trip_key)
