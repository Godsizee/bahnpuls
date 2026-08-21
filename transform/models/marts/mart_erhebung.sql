{{ config(
    materialized='incremental',
    incremental_strategy='delete+insert',
    unique_key='kalendertag'
) }}

-- Die Lueckenseite von BPULS-024: nicht was gemeldet wurde, sondern **ob** gemeldet
-- wurde. Korn ist Kalendertag x Stunde x Quelle.
--
-- **Warum Kalendertag und nicht Betriebstag** -- und das ist keine Nachlaessigkeit: ein
-- Poll ist ein Vorgang der Erhebung. Er hat keinen Betriebstag, und die Zeilen eines
-- einzigen Polls verteilen sich regelmaessig auf zwei. Diesen Mart auf Betriebstag zu
-- schluesseln hiesse, eine Wanduhrgroesse in eine Betriebsgroesse zu uebersetzen, die
-- es nicht gibt. Deshalb steht er **neben** mart_datenqualitaet und wird nie mit ihm
-- verrechnet.
--
-- **Die Stunden kommen aus einem Geruest, nicht aus den Daten.** Eine Stunde ganz ohne
-- Poll erzeugt keine Zeile -- sie waere aus einer Tabelle, die nach Stunden gruppiert,
-- **verschwunden**, und ausgerechnet dieser Mart existiert, um sie zu zeigen. Genau
-- dieser Fehlertyp -- die Luecke, die sich selbst unsichtbar macht -- hat das Projekt
-- an diesem Tag schon zweimal getroffen.
--
-- **Die Abdeckung ist eine untere Schranke.** Gezaehlt werden Polls, die eine Aenderung
-- gebracht haben; ein Poll ganz ohne Aenderung hinterlaesst keine Zeile (ADR-003).
-- Praktisch ist das folgenlos -- selbst die ruhigste Nachtstunde bringt ~38 Zeilen je
-- Poll --, aber die Kennzahl heisst deshalb Abdeckung und nicht Verfuegbarkeit.

{% set intervall = var('de_poll_intervall_sek', 30) %}
{% set erwartet = 3600 // intervall %}

with polls as (

    select *
    from {{ ref('int_de_erhebung') }}

    {% if is_incremental() %}
    -- >= statt >: die Grenzstunde wird neu gebaut, nicht ergaenzt. Beim ersten Lauf
    -- ist sie regelmaessig noch unvollstaendig.
    where cast(fetched_at as date) >= (
        select coalesce(max(kalendertag), date '1900-01-01') from {{ this }}
    )
    {% endif %}

),

fenster as (

    select
        quelle,
        date_trunc('hour', min(fetched_at)) as erste_stunde,
        date_trunc('hour', max(fetched_at)) as letzte_stunde,
        max(fetched_at)                     as letzte_beobachtung
    from polls
    group by 1

),

-- Jede Stunde zwischen erster und letzter Beobachtung, auch die ohne einen einzigen
-- Poll. Ohne dieses Geruest waere ein Totalausfall die einzige Stoerung, die dieser
-- Mart **nicht** zeigt.
geruest as (

    select
        fenster.quelle,
        unnest(generate_series(
            fenster.erste_stunde, fenster.letzte_stunde, interval 1 hour
        )) as stunde_beginn,
        fenster.letzte_beobachtung
    from fenster

),

je_stunde as (

    select
        date_trunc('hour', fetched_at) as stunde_beginn,
        quelle,

        count(*)              as polls_beobachtet,
        min(fetched_at)       as erster_poll,
        max(fetched_at)       as letzter_poll,

        -- Der groesste Abstand, der **in** dieser Stunde endete. Der erste Poll einer
        -- Stunde traegt den Abstand ueber die Stundengrenze hinweg -- gerade der ist
        -- interessant, denn eine Luecke haelt sich nicht an Stunden. Fuer eine Stunde
        -- ganz ohne Poll bleibt der Wert NULL: dort endete keine Luecke, sie lief
        -- hindurch, und die Null in polls_beobachtet sagt es deutlicher.
        max(abstand_sek)      as groesste_luecke_sek,

        avg(feed_alter_sek)   as feed_alter_schnitt_sek,
        max(feed_alter_sek)   as feed_alter_max_sek

    from polls
    group by 1, 2

)

select
    cast(geruest.stunde_beginn as date)               as kalendertag,
    extract(hour from geruest.stunde_beginn)::bigint  as stunde,
    geruest.quelle,

    coalesce(je_stunde.polls_beobachtet, 0)           as polls_beobachtet,
    {{ erwartet }}                                    as polls_erwartet,

    -- Kann ueber 100 % liegen: waehrend eines Redeploys pollen zwei Container
    -- gleichzeitig. Das wird **nicht** gedeckelt -- ein gedeckelter Wert sieht aus wie
    -- eine volle Stunde und verbirgt genau den Vorgang, der ihn erzeugt hat.
    coalesce(je_stunde.polls_beobachtet, 0)::double / {{ erwartet }} as abdeckung,

    je_stunde.groesste_luecke_sek,
    je_stunde.feed_alter_schnitt_sek,
    je_stunde.feed_alter_max_sek,
    je_stunde.erster_poll,
    je_stunde.letzter_poll,

    -- Nur eine abgeschlossene Stunde darf als Befund gelesen werden: abgeschlossen ist
    -- sie, wenn ueber ihr Ende hinaus beobachtet wurde. Sonst waere die laufende Stunde
    -- jedes Mal ein Befund -- und ein Befund, der stuendlich auftritt, wird nicht mehr
    -- gelesen.
    geruest.stunde_beginn + interval 1 hour <= geruest.letzte_beobachtung
        as stunde_vollstaendig

from geruest
left join je_stunde
  on  je_stunde.stunde_beginn = geruest.stunde_beginn
  and je_stunde.quelle        = geruest.quelle
