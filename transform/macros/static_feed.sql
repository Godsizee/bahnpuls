{#
    Der Feed allein aus dem Dateipfad einer statischen Fahrplandatei -- "rv" oder "fv"
    aus ".../v=2026-08-20/rv/trips.txt".

    Warum getrennt von static_herkunft: gtfs.de liefert die Fahrplaene **nach
    Verkehrsart getrennt** aus (rv_free = Regionalverkehr Schiene, fv_free =
    Fernverkehr Schiene). Die Verkehrsart einer Fahrt steht damit bereits in den Daten
    -- als Eigenschaft der Datei, aus der ihr Linienname stammt. Sie wird hier gelesen,
    nicht aus dem Liniennamen geraten (ADR-014).

    static_herkunft zieht Version **und** Feed zusammen, weil ein Join beide braucht.
    Dieses Makro nimmt dieselbe Regex und dieselbe Gruppe 2 -- eine Formulierung, zwei
    Aufrufstellen, statt den Ausdruck ein zweites Mal hinzuschreiben.
#}
{% macro static_feed(spalte) -%}
nullif(regexp_extract(replace({{ spalte }}, '\', '/'), 'v=([0-9-]+)/([^/]+)/', 2), '')
{%- endmacro %}
