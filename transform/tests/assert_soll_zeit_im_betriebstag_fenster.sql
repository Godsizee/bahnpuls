-- Jede Soll-Zeit muss in das Fenster des zugehoerigen Betriebstags fallen:
-- ab 00:00 des Betriebstags bis 06:00 des Folgetags. Der Betriebstag ist laenger
-- als 24 h -- Nachtfahrten und die Ruecksprungnacht (26 h) muessen hineinpassen,
-- ein um einen Tag oder um eine Zeitzone verschobener Wert aber nicht mehr.
--
-- Das ist der Test, der eine falsche Betriebstag-Zuordnung faengt, bevor sie sich
-- in Kennzahlen fortpflanzt (Fallstrick "Betriebstag != Kalendertag" im Datenmodell).

with halt_zeiten as (

    select trip_key, stop_sequence, betriebstag, 'soll_an' as feld, soll_an as zeit
    from {{ ref('fct_stop_events') }}
    where soll_an is not null

    union all

    select trip_key, stop_sequence, betriebstag, 'soll_ab' as feld, soll_ab as zeit
    from {{ ref('fct_stop_events') }}
    where soll_ab is not null

)

select *
from halt_zeiten
where zeit < betriebstag::timestamp
   or zeit >= betriebstag::timestamp + interval 30 hour
