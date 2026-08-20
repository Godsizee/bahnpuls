{#
    Wahr, wenn ein Verspaetungswert ueberhaupt ein Betriebsvorgang sein kann.

    Gemessen am 2026-08-20 ueber 3.986.272 Rohzeilen des eigenen Feeds: die Maxima sind
    unauffaellig (+17.820 s Ankunft, +18.120 s Abfahrt -- fuenf Stunden Verspaetung gibt
    es), die Minima nicht. Ankunft bis **-19.611 s**, Abfahrt bis **-83.050 s**. Ein Zug,
    der 23 Stunden zu frueh ist, existiert nicht; das sind Artefakte, vermutlich Fahrten
    mit einer Prognosezeit auf einem anderen Betriebstag.

    Warum ein Makro und keine Bedingung an Ort und Stelle: dieselbe Definition entscheidet
    an drei Stellen in int_de_stop_events -- Soll-Zeit, Ankunft, Abfahrt. Liefen die
    auseinander, bliebe eine Soll-Zeit stehen, deren Verspaetung verworfen wurde, und der
    Halt zaehlte im Nenner der Abdeckungsquote mit, ohne je einen Wert haben zu koennen.
#}
{% macro ist_plausible_verspaetung(spalte) -%}
(
    {{ spalte }} is not null
    and {{ spalte }} between {{ var('de_plausibel_delay_min_sek', -3600) }}
                         and {{ var('de_plausibel_delay_max_sek', 86400) }}
)
{%- endmacro %}
