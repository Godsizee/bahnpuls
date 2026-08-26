<!--
	Sprungfeld auf der Bahnhofsuebersicht (BPULS-088): tippen statt scrollen.

	Die Tabelle darunter hat `search=true` und **filtert** -- das ist etwas anderes als
	ein Einstieg. Gesucht wird ein Bahnhof, gefunden werden soll seine Seite; dieses Feld
	fuehrt direkt dorthin.

	Ohne JavaScript bleibt die Tabelle darunter vollstaendig bedienbar. Das Feld ist eine
	Abkuerzung, keine Voraussetzung.
-->
<script>
	/** Abfrage mit den Spalten `bahnhof` (Name) und `seite` (Adresse der Bahnhofsseite). */
	export let data;

	let eingabe = '';

	// Der Vergleich laeuft ohne Ruecksicht auf Gross- und Kleinschreibung und ohne
	// Randleerzeichen: wer "frankfurt (main) hbf" tippt, meint denselben Bahnhof.
	const normal = (s) => String(s ?? '').trim().toLocaleLowerCase('de');

	$: knoten = $data ? Array.from($data) : [];
	$: treffer = knoten.filter((k) => normal(k.bahnhof).includes(normal(eingabe)));
	$: genau =
		treffer.find((k) => normal(k.bahnhof) === normal(eingabe)) ??
		(eingabe.trim() && treffer.length === 1 ? treffer[0] : null);

	const springen = () => {
		if (genau) window.location.href = genau.seite;
	};
</script>

<form class="bahnpuls-suche" on:submit|preventDefault={springen}>
	<label for="bahnhof-sprung">Zu deinem Bahnhof springen</label>
	<span class="bahnpuls-suche-zeile">
		<input
			id="bahnhof-sprung"
			list="bahnpuls-knotenliste"
			autocomplete="off"
			placeholder="Name eintippen, z. B. Mannheim"
			bind:value={eingabe}
		/>
		<button type="submit" disabled={!genau}>Öffnen</button>
	</span>
	<datalist id="bahnpuls-knotenliste">
		{#each knoten as k (k.seite)}
			<option value={k.bahnhof}></option>
		{/each}
	</datalist>
	{#if eingabe.trim() && !genau}
		<span class="bahnpuls-suche-hinweis">
			{treffer.length === 0
				? 'Kein Bahnhof mit diesem Namen hat eine eigene Seite. Die Tabelle unten zeigt alle, die eine haben.'
				: treffer.length + ' Bahnhöfe passen — tippe weiter oder wähle einen aus der Liste.'}
		</span>
	{/if}
</form>

<style>
	.bahnpuls-suche {
		display: flex;
		flex-direction: column;
		gap: 0.35rem;
		margin: 1rem 0 1.5rem;
	}
	.bahnpuls-suche label {
		font-size: 0.75rem;
		font-weight: 500;
		color: var(--base-content-muted, #717171);
	}
	.bahnpuls-suche-zeile {
		display: flex;
		flex-wrap: wrap;
		gap: 0.4rem;
	}
	.bahnpuls-suche input {
		flex: 1 1 18rem;
		max-width: 26rem;
		font-size: 0.875rem;
		padding: 0.35rem 0.6rem;
		border: 1px solid var(--base-300, #d6d6d6);
		border-radius: 0.375rem;
		background: var(--base-100, #ffffff);
		color: var(--base-content, #2c2c2c);
	}
	.bahnpuls-suche button {
		font-size: 0.75rem;
		font-weight: 500;
		padding: 0.35rem 0.9rem;
		border: 1px solid var(--base-300, #d6d6d6);
		border-radius: 0.375rem;
		background: var(--base-100, #ffffff);
		color: var(--primary, #2563eb);
		cursor: pointer;
	}
	.bahnpuls-suche button:disabled {
		color: var(--base-content-muted, #717171);
		cursor: not-allowed;
	}
	.bahnpuls-suche-hinweis {
		font-size: 0.75rem;
		color: var(--base-content-muted, #717171);
	}
</style>
