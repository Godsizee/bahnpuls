-- Kein Aggregat darf einen Abschnitt ausweisen, dessen Endpunkt ausserhalb von
-- VRN + RMV liegt (BPULS-075).
--
-- Der Anlass steht als Zeile in der Rangliste: `Koeln Hbf -> Koeln Messe/Deutz` mit
-- 261 Zuegen, obwohl Koeln in keiner Halteliste vorkommt. Der Collector sammelt
-- Fernverkehrsfahrten mit ihrem **ganzen** Laufweg -- der Weg dorthin ist also keine
-- Fehlfunktion, sondern der Normalfall, und deshalb braucht es eine Pruefung, die ihn
-- am Ende der Kette abfaengt statt in der Mitte.
--
-- Warum am Namen und nicht an der Kennzeichnung: die Kennzeichnung ist genau das, was
-- hier geprueft wird. Ein Test, der sie gegen sich selbst haelt, ist immer gruen. Der
-- Name wird deshalb frisch gegen die Gebietsliste gehalten -- dieselbe Datei, die der
-- Collector filtert.
--
-- Halte ohne bekannten Namen bleiben aussen vor: sie koennen ueber ihre stop_id im
-- Gebiet liegen, und ein Test darf nicht melden, was er nicht wissen kann.

with abschnittsenden as (

    select 'mart_verspaetungsentstehung' as mart, betriebstag, von_stop_name as bezeichnung
    from {{ ref('mart_verspaetungsentstehung') }}
    where von_stop_name is not null

    union all

    select 'mart_verspaetungsentstehung', betriebstag, nach_stop_name
    from {{ ref('mart_verspaetungsentstehung') }}
    where nach_stop_name is not null

    union all

    select 'mart_engpassknoten', betriebstag, von_bezeichnung
    from {{ ref('mart_engpassknoten') }}
    where bezeichnung_vollstaendig

    union all

    select 'mart_engpassknoten', betriebstag, nach_bezeichnung
    from {{ ref('mart_engpassknoten') }}
    where bezeichnung_vollstaendig

    union all

    select 'mart_pufferbilanz', betriebstag, von_bezeichnung
    from {{ ref('mart_pufferbilanz') }}
    where bezeichnung_vollstaendig

    union all

    select 'mart_pufferbilanz', betriebstag, nach_bezeichnung
    from {{ ref('mart_pufferbilanz') }}
    where bezeichnung_vollstaendig

)

select
    mart,
    bezeichnung,
    count(*) as zeilen

from abschnittsenden
where not exists (
    select 1
    from {{ ref('stg_de_gebietshalt') }} as gebiet
    where gebiet.stop_name = abschnittsenden.bezeichnung
)
group by 1, 2
