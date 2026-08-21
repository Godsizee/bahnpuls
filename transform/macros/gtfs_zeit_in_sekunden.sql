{#
    Wandelt eine GTFS-Zeit ("HH:MM:SS", auch "25:30:00") in Sekunden seit
    Betriebstagsbeginn.

    Warum von Hand und nicht ueber einen Zeit-Typ: GTFS laesst Stundenwerte ab 24
    ausdruecklich zu, und jeder Zeit-Typ lehnt sie ab oder rechnet sie still auf den
    naechsten Tag um. Beides verliert die Zuordnung zum Betriebstag (CLAUDE.md
    Regel 6). Die Zerlegung ueber split_part kennt keine 24-Stunden-Grenze.

    Leere Zeichenketten -- am Start fehlt die Ankunft, am Ende die Abfahrt -- werden
    zu NULL, nicht zu 0. Null hiesse Mitternacht.
#}
{% macro gtfs_zeit_in_sekunden(spalte) -%}
(
    case when nullif({{ spalte }}, '') is not null then
        cast(split_part({{ spalte }}, ':', 1) as bigint) * 3600
      + cast(split_part({{ spalte }}, ':', 2) as bigint) * 60
      + cast(split_part({{ spalte }}, ':', 3) as bigint)
    end
)
{%- endmacro %}
