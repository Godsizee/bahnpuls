<!--
	Die gemeinsame Auswahlleiste aller Auswertungsseiten (BPULS-087), samt Rueckweg aus
	einer Auswahl ohne Treffer (BPULS-090).

	**EINGABEN: verkehrsart (roh) · gattung (.value)** -- diese Zeile liest auch
	`deploy/dashboard-seitenabfragen-pruefen.py`. `${inputs.verkehrsart}` steht in den
	Abfragen **ohne** `.value`: <ButtonGroup> schreibt seinen Wert roh in den
	Eingabespeicher, genau wie <Slider> (BPULS-084). `${inputs.gattung.value}` steht
	**mit** `.value` und ist ein fertiges SQL-Tupel -- `('RE', 'RB')`, oder
	`(select null where 0)`, wenn nichts ausgewaehlt ist.

	**Warum eine eigene Komponente und nicht <ButtonGroup> + <Dropdown multiple> im
	Markup jeder Seite** -- drei Gruende, alle am Quelltext von Evidence 40.1.8 geprueft:

	  1. **Die Gattungsliste soll der Verkehrsart folgen, und Evidences Dropdown kann das
	     nicht.** `selectAllByDefault` wirkt nur auf den **ersten** Stapel Optionen
	     (`dropdownOptionStore.js` setzt `selectAll` danach auf `false`), und eine
	     ausgewaehlte Option, die spaeter aus der Liste faellt, bleibt ueber
	     `__removeOnDeselect` ausgewaehlt stehen. Ein Klick auf "Fernverkehr" liesse also
	     RE, RB und S ausgewaehlt -- und die Seite waere leer, ausgerechnet auf dem Weg,
	     um den es hier geht.
	  2. **Die Mehrfachauswahl beschriftet sich auf Englisch** ("6 Selected"), und zwar
	     schon im Ausgangszustand.
	  3. **Fuenf Seiten, eine Formulierung.** Reihenfolge, Beschriftung und Vorauswahl
	     liegen einmal, nicht fuenfmal (CLAUDE.md: fachliche Definitionen existieren nur
	     einmal).

	Die Verkehrsart kommt trotzdem von Evidence: <ButtonGroup> tut genau das Richtige,
	und der Seitenabfragen-Pruefer findet den Namen dort, wo er ihn erwartet.
-->
<script>
	import { onMount } from 'svelte';
	import { ButtonGroup, ButtonGroupItem } from '@evidence-dev/core-components';
	import { getInputContext } from '@evidence-dev/sdk/utils/svelte';
	import { duckdbSerialize } from '@evidence-dev/sdk/usql';

	/**
	 * Abfrage dieser Seite mit den Spalten `verkehrsart` und `gattung` -- eine Zeile je
	 * Paar. Welche Gattungen zur Wahl stehen, entscheiden die Daten der Seite und nicht
	 * eine gepflegte Liste: eine Gattung, die es hier nicht gibt, waere ein Knopf, der
	 * in eine leere Tabelle fuehrt.
	 */
	export let data;

	/** Was die Seite selbst darunter anbietet -- eine Zeile, kein Absatz. */
	export let hinweis = '';

	const ALLE = '%';
	const inputs = getInputContext();

	// **Die Adresse wirkt erst nach dem Aufbau, nicht waehrenddessen.** Evidence baut die
	// erste Abfrage einer Seite mit den beim Vorrendern berechneten Zeilen als Startwert
	// und prueft dabei nicht, ob der Abfragetext derselbe ist
	// (`Query.createReactive`). Stuende die Auswahl aus der Adresse schon beim Aufbau
	// fest, zeigte die Seite also die **ungefilterten** Zahlen des Vorrenderns -- stumm,
	// ohne Fehler, mit richtig aussehenden Zahlen. Am gebauten Stand gemessen:
	// `?art=Fernverkehr` lieferte alle Linien. Die ausfuehrliche Begruendung steht im
	// Kopf von `AdresseMerken.svelte`.
	//
	// Gelesen wird ueber `window.location` und nicht ueber `$page.url.searchParams`:
	// SvelteKit verbietet den Zugriff darauf in einer vorgerenderten Seite und bricht den
	// Bau mit einem 500er ab (BPULS-077, am Bau gesehen).
	let artVorgabe = ALLE;
	/** `null` heisst "nicht eingeschraenkt" -- die Auswahl folgt dann der Verkehrsart. */
	let gattungswahl = null;
	/** Erst nach dem Aufbau darf zurueckgeschrieben werden -- sonst loescht der erste
	 *  Lauf genau die Parameter, die `onMount` gleich lesen will. */
	let bereit = false;

	onMount(() => {
		const adresse = new URLSearchParams(window.location.search);
		const art = adresse.get('art');
		if (art) artVorgabe = art;
		const gattungen = adresse.get('gattung')?.split(',').filter(Boolean);
		if (gattungen?.length) gattungswahl = gattungen;
		bereit = true;
	});

	$: verkehrsart = $inputs.verkehrsart ?? ALLE;
	$: zeilen = $data ? Array.from($data) : [];

	// Reihenfolge: erst Fern-, dann Nahverkehr in der gewohnten Ordnung, alles Weitere
	// alphabetisch, "ohne Angabe" zuletzt. Sie ist auf jeder Seite dieselbe -- eine
	// Leiste, deren Knoepfe die Plaetze tauschen, muesste bei jedem Besuch neu gelesen
	// werden.
	const RANG = ['ICE', 'IC', 'EC', 'RE', 'RB', 'S'];
	const rang = (g) => {
		if (g === 'ohne Angabe') return 900;
		const i = RANG.indexOf(g);
		return i === -1 ? 500 : i;
	};

	$: angeboten = [
		...new Set(
			zeilen
				.filter((z) => verkehrsart === ALLE || z.verkehrsart === verkehrsart)
				.map((z) => z.gattung)
				.filter((g) => g !== null && g !== undefined && g !== '')
		)
	].sort((a, b) => rang(a) - rang(b) || String(a).localeCompare(String(b), 'de'));

	// Deckt die Wahl alles ab, was angeboten wird, ist sie keine Einschraenkung mehr.
	// Ohne diesen Schritt stuende "IC" als einzelne Wahl da, obwohl der Fernverkehr hier
	// nur IC kennt -- und "Alle" saehe abgewaehlt aus, ohne dass etwas fehlte.
	$: if (
		gattungswahl !== null &&
		angeboten.length > 0 &&
		angeboten.every((g) => gattungswahl.includes(g))
	) {
		gattungswahl = null;
	}

	// Der Schnitt, nicht die rohe Wahl: wer RE, RB und S gewaehlt hat und dann auf
	// Fernverkehr umstellt, bekommt die Gattungen des Fernverkehrs -- nicht eine leere
	// Seite mit drei Knoepfen, die es dort nicht gibt.
	$: gewaehlt =
		gattungswahl === null ? angeboten : angeboten.filter((g) => gattungswahl.includes(g));

	/**
	 * Der Wert fuer "nicht eingeschraenkt" -- **ohne** die geladene Liste zu brauchen.
	 *
	 * Das ist der Kern der Sache, und er hat eine Sitzung gekostet: **eine Eingabe muss
	 * vom ersten Aufbau an einen Wert haben.** Wer sie erst setzt, wenn seine Daten da
	 * sind, bekommt eine Seite, die stumm leer bleibt -- am gebauten Stand gemessen:
	 * `/engpaesse` zeigte mit Adressanhang `?gattung=RE,RB` seine Tabellen, mit derselben
	 * Auswahl ohne Anhang nicht, obwohl beide im selben Zustand enden (dieselbe
	 * Fehlerklasse wie BPULS-084).
	 *
	 * Ein leeres Tupel taugt dafuer nicht: es hiesse "nichts ausgewaehlt", und die Seite
	 * behauptete schon im vorgerenderten Stand, die Auswahl treffe keine Zeile.
	 * Stattdessen steht hier die Gattungsliste **als Unterabfrage** -- der Abfragetext
	 * von `data` steht sofort bereit, seine Zeilen erst spaeter. `gattung in (alle
	 * Gattungen dieser Seite)` schraenkt nichts ein und ist ab dem ersten Aufbau gueltig.
	 */
	$: ohneEinschraenkung = data?.text
		? '(select gattung from (' + data.text + '))'
		: '(select null where 0)';

	const gattungSetzen = (auswahl, offen, alle) => {
		const neu = {
			// Sonst dieselbe Form, die Evidences <Dropdown multiple> ablegt: ein fertiges
			// SQL-Tupel. Nie selbst zusammengesetzte Zeichenketten -- `duckdbSerialize`
			// verdoppelt Hochkommas, ein Gattungsname mit Apostroph braeche die Abfrage
			// sonst auf.
			value: offen
				? alle
				: auswahl.length
					? '(' + auswahl.map((g) => duckdbSerialize(g)).join(', ') + ')'
					: '(select null where 0)',
			label: offen ? 'alle' : auswahl.join(', '),
			rawValues: auswahl.map((g) => ({ value: g, label: g }))
		};
		// Nur bei echter Aenderung schreiben: der Eingabespeicher meldet jede Aenderung
		// an alle Leser, und diese Zuweisung ist selbst einer davon.
		if (JSON.stringify(neu) !== JSON.stringify($inputs.gattung)) $inputs.gattung = neu;
	};
	$: gattungSetzen(gewaehlt, gattungswahl === null, ohneEinschraenkung);

	const adresseSchreiben = (art, wahl, alle) => {
		if (typeof window === 'undefined') return;
		const p = new URLSearchParams(window.location.search);
		if (art && art !== ALLE) p.set('art', art);
		else p.delete('art');
		if (wahl !== null && wahl.length && wahl.length < alle.length)
			p.set('gattung', wahl.join(','));
		else p.delete('gattung');
		const anhang = p.toString();
		const ziel = window.location.pathname + (anhang ? '?' + anhang : '');
		if (ziel !== window.location.pathname + window.location.search) {
			// replaceState statt pushState: eine Auswahl ist kein Seitenwechsel, und der
			// Zurueck-Knopf soll auf die vorige Seite fuehren und nicht durch zwoelf
			// Filterstaende.
			window.history.replaceState(window.history.state, '', ziel);
		}
	};
	$: if (bereit) adresseSchreiben(verkehrsart, gattungswahl, angeboten);

	$: eingeschraenkt = verkehrsart !== ALLE || gattungswahl !== null;
	$: zurueck = typeof window === 'undefined' ? '' : window.location.pathname;

	const umschalten = (g) => {
		const jetzt = gattungswahl === null ? angeboten : gattungswahl;
		const neu = jetzt.includes(g) ? jetzt.filter((x) => x !== g) : [...jetzt, g];
		// Alles ausgewaehlt ist dasselbe wie nicht eingeschraenkt -- sonst stuende die
		// Einschraenkung in der Adresse, obwohl sie nichts weglaesst.
		gattungswahl = neu.length === angeboten.length ? null : neu;
	};
</script>

<div class="bahnpuls-leiste">
	<!--
		{#key}: <ButtonGroupItem> liest `defaultValue` nur beim Aufbau. Ohne den
		Neuaufbau bliebe der Reiter auf "Alle" stehen, obwohl die Adresse etwas anderes
		sagt.
	-->
	{#key artVorgabe}
		<ButtonGroup name="verkehrsart" display="tabs" title="Verkehrsart" defaultValue={artVorgabe}>
			<ButtonGroupItem value="%" valueLabel="Alle" defaultValue={artVorgabe} />
			<ButtonGroupItem value="Nahverkehr" valueLabel="Nahverkehr" defaultValue={artVorgabe} />
			<ButtonGroupItem value="Fernverkehr" valueLabel="Fernverkehr" defaultValue={artVorgabe} />
		</ButtonGroup>
	{/key}

	<div class="bahnpuls-gattungen">
		<span class="bahnpuls-beschriftung">Zuggattung</span>
		<button
			type="button"
			class="bahnpuls-chip"
			class:aktiv={gattungswahl === null}
			aria-pressed={gattungswahl === null}
			on:click={() => (gattungswahl = null)}>Alle</button
		>
		{#each angeboten as g (g)}
			<button
				type="button"
				class="bahnpuls-chip"
				class:aktiv={gewaehlt.includes(g)}
				aria-pressed={gewaehlt.includes(g)}
				on:click={() => umschalten(g)}>{g}</button
			>
		{/each}
	</div>

	{#if eingeschraenkt}
		<p class="bahnpuls-fuss">
			<!--
				data-sveltekit-reload: ein Wechsel innerhalb der Seite laesst die
				Eingabekomponenten stehen, und dann bliebe die Auswahl trotz leerer
				Adresse bestehen.
			-->
			<a href={zurueck} data-sveltekit-reload>Auswahl zurücksetzen</a>
			{#if hinweis}<span class="bahnpuls-hinweis">{hinweis}</span>{/if}
		</p>
	{/if}
</div>

<style>
	.bahnpuls-leiste {
		margin: 0 0 1.25rem;
	}
	.bahnpuls-gattungen {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: 0.35rem;
		margin-top: -0.9rem;
	}
	.bahnpuls-beschriftung {
		font-size: 0.75rem;
		font-weight: 500;
		color: var(--base-content-muted, #71717a);
		margin-right: 0.35rem;
	}
	.bahnpuls-chip {
		font-size: 0.75rem;
		font-weight: 500;
		line-height: 1.4;
		padding: 0.2rem 0.6rem;
		border-radius: 9999px;
		border: 1px solid var(--base-300, #d4d4d8);
		background: var(--base-100, #ffffff);
		color: var(--base-content, #27272a);
		cursor: pointer;
	}
	.bahnpuls-chip:hover {
		background: var(--base-200, #f4f4f5);
	}
	.bahnpuls-chip.aktiv {
		border-color: var(--primary, #2563eb);
		color: var(--primary, #2563eb);
		background: var(--base-200, #f4f4f5);
	}
	.bahnpuls-fuss {
		margin: 0.6rem 0 0;
		font-size: 0.75rem;
		color: var(--base-content-muted, #71717a);
	}
	.bahnpuls-fuss a {
		color: var(--primary, #2563eb);
	}
	.bahnpuls-hinweis {
		margin-left: 0.6rem;
	}
</style>
