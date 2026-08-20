-- Jede Soll-Zeit muss in das Fenster des zugehoerigen Betriebstags fallen:
-- ab 00:00 des Betriebstags bis 06:00 des Folgetags. Der Betriebstag ist laenger
-- als 24 h -- Nachtfahrten und die Ruecksprungnacht (26 h) muessen hineinpassen,
-- ein um einen Tag oder um eine Zeitzone verschobener Wert aber nicht mehr.
--
-- Das ist der Test, der eine falsche Betriebstag-Zuordnung faengt, bevor sie sich
-- in Kennzahlen fortpflanzt (Fallstrick "Betriebstag != Kalendertag" im Datenmodell).
--
-- Gilt hart nur fuer Quellen, die Soll-Zeit **und** Betriebstag gemeinsam liefern
-- (geaendert mit BPULS-030). Bei CH stehen beide in derselben Zeile der Quelldatei; faellt
-- die Zeit aus dem Fenster, ist die Transformation schuld, und das ist ein Fehler.
--
-- Bei GTFS-RT ist die Soll-Zeit **rekonstruiert** (Prognose minus Verspaetung) und der
-- Betriebstag kommt als start_date aus dem Feed -- zwei Angaben aus verschiedenen Quellen,
-- die auseinanderlaufen koennen, ohne dass an der Transformation etwas falsch ist. Das ist
-- eine Eigenschaft der Quelle und wird deshalb von assert_de_soll_zeit_im_fenster als
-- Warnung gemeldet, nicht als Fehler. Der Unterschied ist nicht kosmetisch: ein harter
-- Fehler hier ueberspringt alle nachgelagerten Modelle, und das Dashboard zeigt dann eine
-- leere Seite mit HTTP 200 -- ein Datenqualitaetsbefund darf den Seitenbau nicht verhindern,
-- er soll auf der Seite sichtbar werden.

with halt_zeiten as (

    select trip_key, stop_sequence, betriebstag, 'soll_an' as feld, soll_an as zeit
    from {{ ref('fct_stop_events') }}
    where soll_an is not null
      and quelle = 'ch_istdaten'

    union all

    select trip_key, stop_sequence, betriebstag, 'soll_ab' as feld, soll_ab as zeit
    from {{ ref('fct_stop_events') }}
    where soll_ab is not null
      and quelle = 'ch_istdaten'

)

select *
from halt_zeiten
where zeit < betriebstag::timestamp
   or zeit >= betriebstag::timestamp + interval 30 hour
