<!--
	Der gemerkte Bahnhof als Einstieg (BPULS-088).

	**Ist keiner gemerkt, steht hier nichts** -- kein leerer Kasten, kein Hinweis auf
	etwas Fehlendes. Der Weg ueber die Uebersicht bleibt daneben stehen und ist ohne
	diesen Verweis genauso vollstaendig wie mit ihm.

	Gelesen wird erst in `onMount`: beim Vorrendern gibt es kein `window`, und ein
	Zugriff dort braeche den Bau ab.
-->
<script>
	import { onMount } from 'svelte';
	import { lesen } from './bahnhofSpeicher.js';

	let gemerkt = null;
	onMount(() => (gemerkt = lesen()));
</script>

{#if gemerkt}
	<a class="bahnpuls-gemerkt" href={'/bahnhof/' + gemerkt.slug}>
		<span class="bahnpuls-gemerkt-label">Dein Bahnhof</span>
		<span class="bahnpuls-gemerkt-name">{gemerkt.name}</span>
	</a>
{/if}

<style>
	.bahnpuls-gemerkt {
		display: flex;
		flex-direction: column;
		gap: 0.15rem;
		margin: 0 0 1.5rem;
		padding: 0.7rem 0.9rem;
		border: 1px solid var(--base-300, #d6d6d6);
		border-radius: 0.5rem;
		background: var(--base-200, #f7f7f7);
		text-decoration: none;
	}
	.bahnpuls-gemerkt:hover {
		border-color: var(--primary, #2563eb);
	}
	.bahnpuls-gemerkt-label {
		font-size: 0.7rem;
		text-transform: uppercase;
		letter-spacing: 0.04em;
		color: var(--base-content-muted, #717171);
	}
	.bahnpuls-gemerkt-name {
		font-size: 1.15rem;
		font-weight: 600;
		color: var(--primary, #2563eb);
	}
</style>
