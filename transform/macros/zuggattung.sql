{#
    Die Zuggattung aus dem Liniennamen: alles vor der ersten Ziffer.
    "RE 70" -> "RE", "S 3" -> "S", "IC 2011" -> "IC", eine Linie namens "3" -> NULL.

    **Gelesen, nicht zugeordnet.** Bewusst ohne gepflegte Liste bekannter Gattungen:
    MEX, SUEWEX oder trilex bekommen dadurch ihre eigene Gattung, statt in einem
    Sammeleimer "sonstige" zu verschwinden -- und liegen trotzdem richtig im
    Nahverkehr, weil darueber die Spalte verkehrsart entscheidet und nicht diese hier
    (ADR-014). Eine Liste muesste bei jeder neuen Linie nachgezogen werden, und bis das
    jemand merkt, zaehlt sie falsch.

    NULL heisst "nicht bekannt", nie "sonstige": bleibt nach dem Abschneiden nichts
    uebrig, ist das keine Gattung namens Leerzeichen.
#}
{% macro zuggattung(spalte) -%}
nullif(trim(regexp_extract({{ spalte }}, '^([^0-9]*)', 1)), '')
{%- endmacro %}
