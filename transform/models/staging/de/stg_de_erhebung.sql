{{ config(materialized='view') }}

-- Die **Erhebung** selbst, nicht ihr Inhalt (BPULS-024). Reine Typisierung: eine Zeile
-- bleibt eine Rohzeile, verdichtet wird in int_de_erhebung.
--
-- **Warum das eine eigene Spur ist.** Alle anderen Modelle lesen, *was* der Feed
-- gemeldet hat. Ob er ueberhaupt gemeldet hat, steht dort nicht: ein Poll, der
-- ausfaellt, hinterlaesst keine Zeile, die man zaehlen koennte -- er hinterlaesst eine
-- **Luecke zwischen zwei Zeiten**. Genau deshalb war diese Kennzahl in BPULS-024 als
-- Leerstelle benannt statt stillschweigend zu fehlen.
--
-- **Warum direkt aus der Quelle und nicht aus stg_de_gtfsrt:** das dortige Modell
-- filtert `is_trip_level_only` heraus. Ein Poll, der nur solche Meldungen brachte,
-- waere darin unsichtbar und zaehlte hier faelschlich als Ausfall.
--
-- **Was gezaehlt wird, ist ein Poll mit Aenderung.** Der Collector schreibt nur, was
-- sich gegenueber dem vorigen Poll geaendert hat (ADR-003); ein Poll ohne jede
-- Aenderung hinterliesse keine Zeile und saehe hier wie ein Ausfall aus. Gemessen am
-- 24-h-Lauf ist selbst die ruhigste Nachtstunde bei ~4.500 Zeilen, also ~38 je Poll --
-- der Fall ist theoretisch, nicht praktisch. Er gehoert trotzdem genannt, weil die
-- Kennzahl sonst mehr verspricht, als sie haelt.
--
-- **Zur Laufzeit:** die View liest zwei Spalten aus einem Parquet-Bestand, der
-- taeglich um ~2,45 Mio. Zeilen waechst. Weil Parquet spaltenweise liegt, kostet das
-- einen Bruchteil dessen, was stg_de_gtfsrt ohnehin schon liest -- ein zusaetzlicher
-- voller Durchlauf ist es nicht.

select
    -- Wanduhrzeit, nicht Betriebstag: ein Poll ist ein Vorgang der Erhebung und hat mit
    -- der Betriebstagslogik nichts zu tun. Beides zu vermischen waere derselbe
    -- Kategorienfehler wie eine Nachtfahrt auf den Kalendertag zu buchen (Regel 6).
    timezone('Europe/Berlin', to_timestamp(fetched_at))         as fetched_at,
    timezone('Europe/Berlin', to_timestamp(snapshot_timestamp)) as snapshot_ts,

    'de_gtfsrt' as quelle

from {{ source('de_raw', 'stop_events') }}
where fetched_at is not null
