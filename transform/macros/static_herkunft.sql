{#
    Version und Feed aus dem Dateipfad einer statischen Fahrplandatei, z. B.
    "v=2026-08-20/rv" aus ".../v=2026-08-20/rv/trips.txt".

    Beides gehoert zusammen: die Version, weil Fahrplaene nebeneinander liegen (Regel 9),
    und der Feed, weil route_id und trip_id **je Feed** eigene Namensraeume sind. Wer nur
    die Version vergleicht, verbindet eine Regionalfahrt mit einer Fernverkehrslinie
    gleicher Nummer.

    Der replace faengt Windows-Pfadtrenner ab: DuckDB gibt filename so zurueck, wie das
    Betriebssystem den Pfad bildet, und die Modelle laufen lokal wie im Container.
#}
{% macro static_herkunft(spalte) -%}
regexp_extract(replace({{ spalte }}, '\', '/'), 'v=([0-9-]+)/([^/]+)/', 0)
{%- endmacro %}
