{{ config(severity = 'warn') }}

-- Meldet Betriebstage, an denen es Laeufe **ohne einen einzigen bedienten Halt** gibt,
-- aber **keinen einzigen** davon gegen den Fahrplan belegen konnte -- obwohl fuer den
-- Tag eine gueltige Fahrplan-Version vorliegt.
--
-- **Warum das ueberhaupt schiefgehen kann:** der Abgleich haengt daran, dass die
-- trip_id des Echtzeit-Feeds dieselbe ist wie im statischen Fahrplan. Die
-- Namensraeume von gtfs.de rotieren zwischen Veroeffentlichungen (Q6), und ob das
-- auch die trip_id betrifft, ist nicht geklaert. Traefe es zu, lieferte der Abgleich
-- stumm ueberall 0 -- und eine Null in einer Spalte "davon belegt" liest sich wie ein
-- Befund ueber den Betrieb statt wie ein Aussetzer der Methode. Genau dieser Fehlertyp
-- hat A5 schon einmal getroffen (BPULS-064).
--
-- Warnung, kein Fehler: der Seitenbau darf daran nicht haengen.
with je_tag as (

    select
        betriebstag,
        quelle,
        max(fahrten_unbedienter_lauf)              as unbedient,
        max(fahrten_unbedienter_lauf_bestaetigt)   as belegt,
        max(fahrten_unbedienter_lauf_nicht_pruefbar) as nicht_pruefbar

    from {{ ref('mart_puenktlichkeit') }}
    -- Eine Schwelle genuegt: die Fahrtzahlen haengen nicht an ihr und stuenden sonst
    -- fuenffach in der Summe. Und nur die deutsche Quelle: der Abgleich gegen den
    -- statischen Fahrplan existiert nur fuer sie.
    where schwelle_sek = 360
      and quelle = 'de_gtfsrt'
    group by 1, 2

),

-- Ohne Fahrplan-Version, die nicht nach dem Betriebstag veroeffentlicht wurde, ist
-- nichts zu belegen -- und das ist kein Befund, sondern Regel 9.
mit_fahrplan as (

    select distinct je_tag.betriebstag, je_tag.quelle
    from je_tag
    join {{ ref('stg_de_fahrplanhalt') }} as fahrplan
      on fahrplan.static_version <= je_tag.betriebstag

)

-- `nicht_pruefbar` steht mit im Ergebnis, weil es die beiden Fehlerbilder trennt:
-- liegt es bei der Zahl der unbedienten Laeufe, kennt der Fahrplan die trip_ids gar
-- nicht (Namensraum-Rotation); liegt es bei null, gibt es Fahrplaene und der Abgleich
-- trifft trotzdem nichts -- dann stimmt etwas mit dem Abgleich selbst nicht.
select
    je_tag.betriebstag,
    je_tag.quelle,
    sum(je_tag.unbedient)      as unbediente_laeufe,
    sum(je_tag.nicht_pruefbar) as davon_nicht_pruefbar

from je_tag
join mit_fahrplan
  on  mit_fahrplan.betriebstag = je_tag.betriebstag
  and mit_fahrplan.quelle      = je_tag.quelle
group by 1, 2
having sum(je_tag.unbedient) > 0
   and sum(je_tag.belegt)    = 0
