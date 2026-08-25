{#
    Die Verkehrsart aus dem Feed, aus dem der Linienname einer Fahrt stammt:
    "fv" -> Fernverkehr, "rv" -> Nahverkehr, alles andere -> NULL (ADR-014).

    **Nicht geraten, sondern gelesen.** gtfs.de liefert die Schienenfahrplaene nach
    Verkehrsart getrennt aus; die Zuordnung ist damit eine Eigenschaft des Datensatzes
    und braucht keine Liste bekannter Gattungen. Der umgekehrte Weg -- die Verkehrsart
    aus dem Gattungspraefix ableiten -- ist in ADR-014 verworfen: jede unbekannte
    Gattung landete auf der falschen Seite.

    Warum ein Makro und kein case an den zwei Aufrufstellen: int_de_stop_events und
    int_de_ausfaelle holen den Liniennamen ueber denselben Join, und eine fachliche
    Zuordnung existiert im Projekt genau einmal. Zwei Formulierungen liefen
    auseinander, sobald eine dritte Verkehrsart dazukaeme -- und die Marts zaehlten
    dann je nach Zweig verschieden.

    NULL heisst "nicht bekannt", nie "sonstige": es sind genau die Fahrten, deren
    trip_id in keiner gueltigen Fahrplan-Version steht. Dort fehlt schon heute der
    Linienname.
#}
{% macro verkehrsart(spalte) -%}
case {{ spalte }}
    when 'fv' then 'Fernverkehr'
    when 'rv' then 'Nahverkehr'
end
{%- endmacro %}
