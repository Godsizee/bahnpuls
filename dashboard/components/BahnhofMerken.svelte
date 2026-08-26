<!--
	"Diesen Bahnhof merken" auf einer Bahnhofsseite (BPULS-088).

	**Der Zugriff auf `localStorage` steht in `onMount`, nicht im Rumpf.** Beim
	Vorrendern gibt es kein `window`; ein Zugriff dort bricht den Bau ab, und zwar mit
	einem 500er statt mit einer Meldung -- derselbe Fall wie BPULS-077.

	Ohne JavaScript, ohne Speicher, im privaten Fenster bleibt die Seite vollstaendig:
	der Knopf erscheint dann gar nicht erst, und es fehlt nichts, worauf er hinwiese.
-->
<script>
	import { onMount } from 'svelte';
	import { lesen, merken, vergessen } from './bahnhofSpeicher.js';

	/** Der slug aus dem Seed `knoten` -- der Teil der Adresse, der sich nicht aendert. */
	export let slug;
	/** Der Name, wie er auf der Seite steht. */
	export let name;

	let gemerkt = null;
	let bereit = false;

	onMount(() => {
		gemerkt = lesen();
		bereit = true;
	});

	$: ist = bereit && gemerkt?.slug === slug;

	const umschalten = () => {
		if (ist) {
			vergessen();
			gemerkt = null;
		} else {
			merken(slug, name ?? slug);
			gemerkt = { slug, name: name ?? slug };
		}
	};
</script>

{#if bereit}
	<p class="bahnpuls-merken">
		<button type="button" on:click={umschalten} aria-pressed={ist}>
			{ist ? 'Gemerkt — merken aufheben' : 'Diesen Bahnhof merken'}
		</button>
		<span class="bahnpuls-merken-erklaerung">
			{#if ist}
				Er steht ab jetzt oben auf der Startseite. Gespeichert wird er nur in diesem Browser.
			{:else}
				Danach steht er oben auf der Startseite, und du kommst mit einem Klick hierher zurück.
			{/if}
		</span>
	</p>
{/if}

<style>
	.bahnpuls-merken {
		margin: 0.75rem 0 1.5rem;
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: 0.6rem;
	}
	.bahnpuls-merken button {
		font-size: 0.75rem;
		font-weight: 500;
		padding: 0.3rem 0.75rem;
		border-radius: 0.375rem;
		border: 1px solid var(--base-300, #d6d6d6);
		background: var(--base-100, #ffffff);
		color: var(--primary, #2563eb);
		cursor: pointer;
	}
	.bahnpuls-merken button:hover {
		background: var(--base-200, #f7f7f7);
	}
	.bahnpuls-merken button[aria-pressed='true'] {
		border-color: var(--primary, #2563eb);
		background: var(--base-200, #f7f7f7);
	}
	.bahnpuls-merken-erklaerung {
		font-size: 0.75rem;
		color: var(--base-content-muted, #717171);
	}
</style>
