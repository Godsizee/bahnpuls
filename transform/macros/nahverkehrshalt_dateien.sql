{#
    Zaehlt die Nahverkehrs-Haltelisten, die auf dem Volume tatsaechlich liegen.

    Gleiche Begruendung wie bei fahrplanhalt_dateien(): ein Glob ohne Treffer ist in
    DuckDB ein **Fehler**, kein leeres Ergebnis. Und diesen Zustand gibt es hier
    regulaer -- die Liste entsteht erst mit dem ersten Static-Load nach BPULS-070,
    und ihr Schreiben ist bewusst best-effort, damit ein Fehlschlag nie die Version
    kostet.

    Ohne diese Pruefung risse der ganze dbt-Lauf ab, also auch Puenktlichkeit,
    Engpaesse und Pufferbilanz, die mit der Fremdverkehrsfrage nichts zu tun haben.

    Beim Parsen (`execute == false`) steht keine Verbindung bereit; dort wird 1
    zurueckgegeben, damit der Zweig mit der echten Quelle kompiliert wird.
#}
{% macro nahverkehrshalt_dateien() -%}
    {%- if not execute -%}
        {{ return(1) }}
    {%- endif -%}
    {%- set muster = var('de_static_dir') ~ '/v=*/nv/' ~ 'stops.parquet' -%}
    {%- set ergebnis = run_query("select count(*) as anzahl from glob('" ~ muster ~ "')") -%}
    {{ return(ergebnis.columns[0].values()[0]) }}
{%- endmacro %}
