-- BPULS-024, Lueckenseite. Stundenkorn, begrenzt auf die letzten 30 Kalendertage je
-- Quelle -- das sind 720 Zeilen, also kein Mengenproblem (BPULS-061: die Last einer
-- Evidence-Seite haengt an der weitesten Abfrage, nicht an der Dateigroesse).
--
-- Das Stundenkorn bleibt erhalten, statt hier schon auf Tage zu verdichten: eine
-- einzelne Stunde ohne Poll ist der Befund, um den es geht, und ein Tagesmittel
-- verschluckt sie.
with tage as (

    select quelle, kalendertag
    from mart_erhebung
    group by quelle, kalendertag
    qualify dense_rank() over (partition by quelle order by kalendertag desc) <= 30

)

select
    erhebung.kalendertag,
    erhebung.stunde,
    erhebung.quelle,
    erhebung.polls_beobachtet,
    erhebung.polls_erwartet,
    erhebung.abdeckung,
    erhebung.groesste_luecke_sek,
    erhebung.feed_alter_schnitt_sek,
    erhebung.feed_alter_max_sek,
    erhebung.stunde_vollstaendig

from mart_erhebung as erhebung
join tage
  on  tage.quelle      = erhebung.quelle
 and tage.kalendertag = erhebung.kalendertag
