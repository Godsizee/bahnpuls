// Welche Bahnhofsseiten gebaut werden (BPULS-061).
//
// Evidence liest diese Datei beim Bau ein und mischt sie in seine eigene
// SvelteKit-Konfiguration (`loadUserConfiguration` in .evidence/template/svelte.config.js).
//
// **Warum es sie überhaupt braucht:** SvelteKit rendert eine parametrierte Seite wie
// `/bahnhof/[bahnhof]` nur vor, wenn es sie findet — und es findet sie ausschließlich über
// Links im **vorgerenderten** HTML. Die Tabelle auf der Übersichtsseite entsteht aber erst
// im Browser aus DuckDB-WASM; im gebauten HTML steht keine einzige dieser Adressen. Ohne
// diese Liste bliebe jede Bahnhofsseite ungebaut, und der Bau meldete es nicht einmal
// (`strict: false` im Adapter).
//
// Die Liste kommt aus dem Seed, nicht aus einer zweiten Aufzählung: `knoten.csv` ist
// dieselbe Datei, aus der `mart_bahnhof.ist_knoten` entsteht. Zwei Listen liefen
// auseinander, und dann gäbe es Seiten ohne Zahlen oder Zahlen ohne Seite.
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const hier = path.dirname(fileURLToPath(import.meta.url));
const knotenliste = path.join(hier, '..', 'transform', 'seeds', 'knoten.csv');

const zeilen = fs.readFileSync(knotenliste, 'utf-8').trim().split(/\r?\n/).slice(1);
// Der slug ist das **letzte** Feld, nicht das dritte: ein Haltestellenname darf ein Komma
// enthalten (im Feed kommt das vor), und dann verschiebt ein naives Zerlegen alles.
const slugs = zeilen.map((zeile) => zeile.split(',').pop().trim()).filter(Boolean);

if (slugs.length === 0) {
	throw new Error(
		`knoten.csv (${knotenliste}) enthält keine Zeile — der Bau würde jede Bahnhofsseite ` +
			'stillschweigend auslassen (BPULS-061).'
	);
}

export default {
	kit: {
		prerender: {
			// '*' ist die Voreinstellung: alle Seiten ohne Parameter. Sie muss mit
			// aufgezählt werden, sonst ersetzt diese Liste sie.
			entries: ['*', ...slugs.map((slug) => `/bahnhof/${slug}`)]
		}
	}
};
