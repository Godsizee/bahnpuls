{#
    Zaehlt die Soll-Halt-Dateien, die auf dem Volume tatsaechlich liegen.

    Warum das noetig ist: `stg_de_fahrplanhalt` liest per Glob, und ein Glob ohne
    Treffer ist in DuckDB ein **Fehler**, kein leeres Ergebnis (geprueft mit 1.5.5;
    `error_on_no_files` kennt read_parquet dort nicht). Die Extraktion der Datei ist
    bewusst best-effort -- sie darf das unwiederbringliche Archiv nicht opfern --,
    also kann es einen Stand geben, in dem keine einzige Version sie hat. Ohne diese
    Pruefung reisst dann der **ganze** dbt-Lauf ab, und mit ihm alles, was mit
    Ausfaellen nichts zu tun hat.

    Beim Parsen (`execute == false`) steht keine Verbindung bereit; dort wird 1
    zurueckgegeben, damit der Zweig mit der echten Quelle kompiliert wird.
#}
{% macro fahrplanhalt_dateien() -%}
    {%- if not execute -%}
        {{ return(1) }}
    {%- endif -%}
    {%- set muster = var('de_static_dir') ~ '/v=*/*/' ~ 'stop_times.parquet' -%}
    {%- set ergebnis = run_query("select count(*) as anzahl from glob('" ~ muster ~ "')") -%}
    {{ return(ergebnis.columns[0].values()[0]) }}
{%- endmacro %}
