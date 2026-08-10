-- Jeder Halt braucht mindestens eine Soll-Zeit. Beide gleichzeitig NULL waere ein
-- Halt ohne jeden Bezugspunkt -- nicht einfach not_null je Spalte, weil der erste
-- Halt einer Fahrt legitim keine Ankunft und der letzte legitim keine Abfahrt hat.

select *
from {{ ref('stg_ch_istdaten') }}
where soll_an is null
  and soll_ab is null
