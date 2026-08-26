<!--
	Hält **eine** Eingabe und die Adresse zusammen (BPULS-087: ein gefilterter Blick muss
	zitierbar sein). Die Komponente tut zweierlei:

	  1. Sie **schreibt** den Wert der Eingabe in die Adresse, sobald er sich ändert.
	  2. Sie **gibt** den Wert aus der Adresse an das Eingabefeld weiter -- aber erst
	     **nach** dem Aufbau der Seite, und das ist keine Bequemlichkeit.

	**Warum erst nach dem Aufbau, und warum das eine Komponente rechtfertigt.** Evidence
	baut die **erste** Abfrage einer Seite mit den beim Vorrendern berechneten Zeilen als
	Startwert (`Query.createReactive`: beim ersten Aufruf steht `initialData` noch in den
	Optionen und wird erst danach entfernt). Ob der Abfragetext derselbe ist, prüft es
	dabei **nicht**. Stünde die Auswahl aus der Adresse schon beim Aufbau fest, bekäme die
	Seite also die *ungefilterten* Zahlen des Vorrenderns zu sehen und behielte sie --
	stumm, ohne Fehler, mit richtig aussehenden Zahlen. Am gebauten Stand gemessen:
	`/puenktlichkeit?art=Fernverkehr` zeigte alle Linien, `/puenktlichkeit?art=Nahverkehr&gattung=S`
	dagegen richtig nur die S-Bahn -- weil dort ein zweiter Schritt dazwischenlag.

	Deshalb: erst die Vorauswahl der Seite (dieselbe wie beim Vorrendern, der Startwert
	passt also), dann in `onMount` die Adresse. Der zweite Schritt geht durch Evidences
	`waitFor`, das `initialData` ausdrücklich verwirft -- und holt die Zahlen wirklich.

	`{#key}` um den Inhalt: die Eingabekomponenten lesen `defaultValue` nur beim Aufbau.
	Ohne den Neuaufbau bliebe der Regler auf der Vorauswahl stehen.

	Diese Komponente legt **keine** Eingabe an, sie liest nur mit -- deshalb steht hier
	keine EINGABEN-Zeile für `deploy/dashboard-seitenabfragen-pruefen.py`.

	`window.location` und nicht `$page.url.searchParams`: SvelteKit verbietet den Zugriff
	darauf in einer vorgerenderten Seite und bricht den Bau mit einem 500er ab
	(BPULS-077, am Bau gesehen).
-->
<script>
	import { onMount } from 'svelte';
	import { getInputContext } from '@evidence-dev/sdk/utils/svelte';

	/** Name der Eingabe, so wie ihn die Komponente im Inhalt trägt. */
	export let eingabe;
	/** Name des Adressparameters. Voreinstellung: derselbe Name. */
	export let parameter = null;
	/**
	 * Die Vorauswahl der Seite -- derselbe Wert, mit dem vorgerendert wurde. Bei ihm
	 * verschwindet der Parameter aus der Adresse: eine Einschränkung, die nichts
	 * einschränkt, gehört nicht in einen zitierten Link.
	 */
	export let vorgabe = null;
	/** Ein Schieberegler braucht eine Zahl, kein Zeichenkettenpaar. */
	export let zahl = false;

	const inputs = getInputContext();

	let vorauswahl = vorgabe;
	let bereit = false;

	onMount(() => {
		const roh = new URLSearchParams(window.location.search).get(parameter ?? eingabe);
		if (roh !== null && roh !== '') {
			const wert = zahl ? Number(roh) : roh;
			if (!zahl || Number.isFinite(wert)) vorauswahl = wert;
		}
		bereit = true;
	});

	const schreiben = (roh) => {
		if (typeof window === 'undefined') return;
		// `'value' in roh` statt `roh.value !== undefined`: ein Lesezugriff auf den
		// Eingabespeicher **legt den Schlüssel an**, wenn es ihn nicht gibt, und liefert
		// einen Platzhalter zurück. Aus einem Schieberegler (Wert: `[5]`) wurde damit
		// `?mindest=(SELECT NULL WHERE 0 …)`. `in` löst den Zugriff nicht aus.
		const huelle =
			roh !== null &&
			roh !== undefined &&
			(typeof roh === 'object' || typeof roh === 'function') &&
			'value' in roh;
		const inner = huelle ? roh.value : roh;
		// Ein noch nicht gesetzter Wert ist im Speicher kein `undefined`, sondern ein
		// Platzhalter. Er macht sich zu einer leeren Zeichenkette -- oder zu Evidences
		// eigenem Merksatz. Beides heißt hier dasselbe: noch nichts zu schreiben.
		const wert = inner === null || inner === undefined ? '' : String(inner);
		const ungesetzt = wert === '' || wert.includes('has not been set');
		const p = new URLSearchParams(window.location.search);
		if (ungesetzt || wert === String(vorgabe)) p.delete(parameter ?? eingabe);
		else p.set(parameter ?? eingabe, wert);
		const anhang = p.toString();
		const ziel = window.location.pathname + (anhang ? '?' + anhang : '');
		if (ziel !== window.location.pathname + window.location.search) {
			// replaceState statt pushState: eine Auswahl ist kein Seitenwechsel, und der
			// Zurück-Knopf soll auf die vorige Seite führen und nicht durch zwölf
			// Filterstände.
			window.history.replaceState(window.history.state, '', ziel);
		}
	};

	$: if (bereit) schreiben($inputs[eingabe]);
</script>

{#key vorauswahl}
	<slot {vorauswahl} />
{/key}
