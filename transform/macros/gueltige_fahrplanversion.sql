{#
    Ordnet Fahrten die zum Betriebstag **gueltige** Fahrplan-Version und den Feed zu,
    in dem ihre trip_id eindeutig ist.

    `kandidaten` ist der Name einer CTE mit (betriebstag, trip_key, trip_id).
    Ergebnis: eine Zeile je trip_key mit (trip_key, static_version, feed).

    **Das ist CLAUDE.md Regel 9 in Code**, und deshalb steht es hier statt zweimal
    ausgeschrieben: gejoint wird gegen die juengste Version, die **nicht nach** dem
    Betriebstag veroeffentlicht wurde -- nicht gegen die neueste, nicht ueber alle
    vereinigt. Der Laufweg einer Fahrt ist Fahrplaninhalt und aendert sich mit der
    Version; das ist der Unterschied zu stg_de_static, wo ein Stationsname eine
    Beschriftung ist und vereinigt werden darf.

    **Fahrten ohne Treffer fallen heraus, statt geraten zu werden.** Drei Faelle:
    keine Version ist aelter als der Betriebstag (jeder Tag vor der ersten Ladung),
    die Version kennt die trip_id nicht, oder dieselbe trip_id steht in **beiden**
    Feeds derselben Version -- dann waere nicht entscheidbar, welcher Laufweg gemeint
    ist, und ein geratener Laufweg saehe vollstaendig aus und waere frei erfunden.
    Der Aufrufer entscheidet, wie er mit dem Fehlen umgeht; er darf es nicht
    stillschweigend als 0 lesen.
#}
{% macro gueltige_fahrplanversion(kandidaten) -%}
    with version as (

        select
            k.trip_key,
            max(f.static_version) as static_version

        from {{ kandidaten }} as k
        join {{ ref('stg_de_fahrplanhalt') }} as f
          on  f.trip_id        = k.trip_id
          and f.static_version <= k.betriebstag
        group by 1

    )

    select
        version.trip_key,
        version.static_version,
        min(f.feed) as feed

    from version
    join {{ kandidaten }} as k
      on k.trip_key = version.trip_key
    join {{ ref('stg_de_fahrplanhalt') }} as f
      on  f.static_version = version.static_version
      and f.trip_id        = k.trip_id
    group by 1, 2
    having count(distinct f.feed) = 1
{%- endmacro %}
