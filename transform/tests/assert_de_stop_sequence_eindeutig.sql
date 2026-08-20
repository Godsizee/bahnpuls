-- Was fuer GTFS-RT statt Lueckenlosigkeit zugesichert werden kann (BPULS-030): je
-- Fahrt darf jede stop_sequence genau einmal vorkommen. Die Quelle liefert denselben
-- Halt in vielen Snapshots; taucht er nach der Verdichtung doppelt auf, hat
-- int_de_stop_events nicht auf ein Ereignis reduziert -- und jede Kennzahl zaehlte
-- diesen Halt mehrfach. Das ist der Fehler, der bei dieser Quelle tatsaechlich droht,
-- nicht die Luecke.
--
-- Faengt zugleich den Fall ab, den der Redeploy erzeugt: Coolify laesst alten und
-- neuen Container kurz parallel laufen, beide schreiben denselben Halt weg.

select
    trip_key,
    stop_sequence,
    count(*) as zeilen

from {{ ref('fct_stop_events') }}
where quelle = 'de_gtfsrt'
group by trip_key, stop_sequence
having count(*) > 1
