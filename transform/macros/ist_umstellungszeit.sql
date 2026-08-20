{#
    Wahr, wenn eine Soll-Zeit in der Stunde der Sommerzeitumstellung liegt: in der
    Nacht des letzten Sonntags im Maerz existiert die lokale Stunde 02:00-02:59 gar
    nicht, in der des letzten Sonntags im Oktober zweimal.

    Warum ein Makro und keine zweifache Bedingung: dieselbe Definition entscheidet an
    zwei Stellen mit gegenlaeufiger Wirkung -- assert_keine_stille_zeitumstellung
    macht die Halte sichtbar, die Marts schliessen genau dieselben aus (BPULS-013).
    Zwei getrennte Formulierungen wuerden auseinanderlaufen, und dann meldet der Test
    Halte, die in den Kennzahlen trotzdem mitgerechnet werden.

    Europe/Zurich und Europe/Berlin stellen zum selben Zeitpunkt um, die Definition
    gilt fuer beide Quellen.
#}
{% macro ist_umstellungszeit(zeit) -%}
(
    {{ zeit }} is not null
    and month({{ zeit }}) in (3, 10)
    -- letzter Sonntag des Monats: Sonntag, dessen Datum + 7 Tage im Folgemonat liegt
    and dayofweek(cast({{ zeit }} as date)) = 0
    and month(cast({{ zeit }} as date) + interval 7 day) != month(cast({{ zeit }} as date))
    and hour({{ zeit }}) = 2
)
{%- endmacro %}
