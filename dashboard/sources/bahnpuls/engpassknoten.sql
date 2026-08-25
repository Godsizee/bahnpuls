-- A4 (BPULS-033). Abschnitt x Tagesstunde, ueber die letzten 30 Betriebstage je Quelle
-- zusammengefasst -- die Tagesachse faellt hier weg, sie ist auf dieser Seite keine
-- Frage. Uebrig bleiben Abschnitt, Richtung und Stunde.
--
-- **Begrenzt auf die 200 meistbefahrenen Abschnitte je Quelle.** In Produktion sind es
-- **19.951 bis 22.363 Abschnitte je Tag** (gemessen 2026-08-21 ueber drei Betriebstage,
-- die vorherige Schaetzung von 14.000 lag um rund die Haelfte zu niedrig), mit
-- Stundenachse entsprechend mehr; die gehen bei Evidence in den Browser (BPULS-056).
-- Mit dieser Grenze bleiben davon 4.628 Zeilen und 53 KB uebrig.
--
-- Gewaehlt wird nach **Verkehrsmenge**, nicht nach Verspaetung -- obwohl die Seite nach
-- Verspaetung sortiert. Andersherum waere der Ausschnitt zirkulaer: die Rangliste sucht
-- dann in einer Menge, die schon nach demselben Kriterium vorsortiert wurde, und jede
-- Zahl darin saehe schlimmer aus, als sie ist. Der Preis ist benannt und steht auch auf
-- der Seite: **ein Engpass auf einer wenig befahrenen Strecke taucht hier nicht auf.**
with fenster as (

    select quelle, betriebstag
    from mart_engpassknoten
    group by quelle, betriebstag
    qualify dense_rank() over (partition by quelle order by betriebstag desc) <= 30

),

zusammengefasst as (

    select
        engpass.quelle,
        engpass.von_bezeichnung,
        engpass.nach_bezeichnung,
        engpass.abschnitt_paar,
        engpass.richtung_hin,
        -- ADR-014: NULL heisst "der Fahrplan kennt diese Fahrt nicht" und bekommt ein
        -- eigenes Etikett -- eine Auswahlliste kann auf NULL nicht filtern.
        coalesce(engpass.verkehrsart, 'ohne Angabe') as verkehrsart,
        coalesce(engpass.gattung, 'ohne Angabe')     as gattung,
        engpass.stunde,

        bool_and(engpass.bezeichnung_vollstaendig) as bezeichnung_vollstaendig,

        -- Summe und Zaehler bleiben getrennt: die Seite rechnet daraus ueber Stunden
        -- hinweg neu. Ein Mittel von Stundenmitteln gewichtet die Stunde mit zwei
        -- Zuegen wie die mit vierzig.
        sum(engpass.zuege)                    as zuege,
        sum(engpass.laufzeit_delta_sek_summe)  as laufzeit_summe,
        sum(engpass.laufzeit_messwerte)        as laufzeit_messwerte,
        sum(engpass.haltezeit_delta_sek_summe) as haltezeit_summe,
        sum(engpass.haltezeit_messwerte)       as haltezeit_messwerte,
        sum(engpass.ausgefallene_halte)        as ausgefallene_halte,
        sum(engpass.ausgelassene_halte)        as ausgelassene_halte

    from mart_engpassknoten as engpass
    join fenster
      on  fenster.quelle      = engpass.quelle
      and fenster.betriebstag = engpass.betriebstag
    group by 1, 2, 3, 4, 5, 6, 7, 8

),

-- Die Auswahl der Abschnitte in einem eigenen Schritt, nicht als verschachteltes
-- Fenster im qualify: DuckDB laesst Fensterfunktionen innerhalb einer Fensterdefinition
-- nicht zu, und der Umweg macht ohnehin lesbarer, wonach ausgewaehlt wird.
ausgewaehlt as (

    select
        quelle,
        von_bezeichnung,
        nach_bezeichnung,
        sum(zuege) as zuege_gesamt
    from zusammengefasst
    group by 1, 2, 3
    qualify row_number() over (
        partition by quelle
        order by zuege_gesamt desc, von_bezeichnung, nach_bezeichnung
    ) <= 200

)

select zusammengefasst.*
from zusammengefasst
join ausgewaehlt
  on  ausgewaehlt.quelle           = zusammengefasst.quelle
  and ausgewaehlt.von_bezeichnung  = zusammengefasst.von_bezeichnung
  and ausgewaehlt.nach_bezeichnung = zusammengefasst.nach_bezeichnung
