{{ config(severity = 'warn') }}

-- Meldet ausgefallene Fahrten, die **nicht** in Halt-Ereignisse aufgeloest werden
-- konnten. Kein Fehler: es gibt drei legitime Gruende, und alle drei muessen
-- sichtbar bleiben, statt als stille Null zu enden -- genau daran ist A5 vorher
-- gescheitert.
--
--   1. Fuer den Betriebstag existiert **keine aeltere** Fahrplan-Version. Trifft
--      jeden Tag vor der ersten Ladung; hier wird bewusst nicht die spaetere
--      Version genommen (Regel 9).
--   2. Die trip_id steht in derselben Version in **beiden** Feeds -- welcher
--      Laufweg gemeint ist, waere geraten.
--   3. Die Version kennt die trip_id gar nicht.
--
-- Als Warnung und nicht als Fehler, weil ein Datenqualitaetsbefund den Seitenbau
-- nicht anhalten darf (Befund vom 2026-08-20) -- aber laut genug, dass ein
-- Anstieg auffaellt.
with ausgefallen as (

    select distinct betriebstag, trip_key
    from {{ ref('stg_de_fahrtmeldung') }}
    where zug_ausgefallen

),

aufgeloest as (

    select distinct trip_key
    from {{ ref('int_de_ausfaelle') }}

),

beobachtet as (

    select distinct trip_key
    from {{ ref('stg_de_gtfsrt') }}

)

select
    ausgefallen.betriebstag,
    ausgefallen.trip_key

from ausgefallen
left join aufgeloest using (trip_key)
left join beobachtet using (trip_key)

where aufgeloest.trip_key is null
  -- Fahrten, die auch mit Halten gemeldet wurden, brauchen keine Aufloesung.
  and beobachtet.trip_key is null
