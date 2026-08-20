{{ config(severity='warn') }}

-- Ein Schluessel, der ueber die Versionen hinweg **verschiedene** Bezeichnungen traegt.
--
-- Zwei sehr verschiedene Dinge sehen hier gleich aus: eine blosse Umbenennung derselben
-- Station (harmlos, die neuere gewinnt) und eine **wiederverwendete ID mit neuer
-- Bedeutung** (nicht harmlos -- dann traegt ein Halt-Ereignis den Namen einer anderen
-- Betriebsstelle). Aus den Namen allein ist das nicht entscheidbar, deshalb warnt der
-- Test, statt zu urteilen: er nennt die Faelle, damit jemand hinsieht.
--
-- Grund fuer die Vereinigung ueber Versionen steht in stg_de_static (Q6).

select
    art,
    schluessel,
    bezeichnung,
    namensvarianten,
    zuerst_gesehen,
    zuletzt_gesehen

from {{ ref('stg_de_static') }}
where namensvarianten > 1
