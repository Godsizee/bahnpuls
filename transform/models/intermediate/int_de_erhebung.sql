{{ config(materialized='table') }}

-- Ein Poll je Zeile, mit dem Abstand zum vorigen (BPULS-024).
--
-- **Der Abstand ist die eigentliche Kennzahl.** Polls zu zaehlen sagt, wie oft es
-- geklappt hat; der Abstand sagt, wie lange es nicht geklappt hat -- und nur das
-- entscheidet, ob eine Luecke in den Ist-Daten eine Betriebslage oder ein Aussetzer der
-- Sammlung ist. Im 24-h-Lauf lag die groesste gemessene Luecke bei 225 s, verursacht
-- durch drei aufeinanderfolgende Fetch-Timeouts (BPULS-058).
--
-- **Warum `distinct` und nicht `group by` ueber Rohzeilen:** gezaehlt werden Zeiten,
-- nicht Zeilen. Damit ist dieses Modell von der Dublettenfrage nicht betroffen -- beim
-- Redeploy schreiben zwei Container zwei Minuten lang gleichzeitig, und ihre Zeilen
-- verdoppeln sich, ihre Poll-Zeitpunkte nicht. Zwei Container **polling** aber
-- tatsaechlich getrennt: zwei dicht beieinanderliegende Zeiten sind dann zwei Polls und
-- werden auch als zwei gezaehlt. Das ist richtig so -- es sind zwei.

with polls as (

    select
        quelle,
        fetched_at,
        max(snapshot_ts) as snapshot_ts

    from {{ ref('stg_de_erhebung') }}
    group by 1, 2

)

select
    quelle,
    fetched_at,
    snapshot_ts,

    -- Wie alt der Feed war, als wir ihn geholt haben. Gemessen liegt der Wert bei rund
    -- 19 s; steigt er, liefert die Quelle veraltete Daten, ohne dass ein Poll fehlt.
    date_diff('second', snapshot_ts, fetched_at) as feed_alter_sek,

    -- NULL beim allerersten Poll: davor gab es nichts, und 0 waere gelogen.
    date_diff(
        'second',
        lag(fetched_at) over (partition by quelle order by fetched_at),
        fetched_at
    ) as abstand_sek

from polls
