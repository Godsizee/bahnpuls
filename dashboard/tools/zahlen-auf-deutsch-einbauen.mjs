#!/usr/bin/env node
// Biegt die `ssf`-Importe in @evidence-dev/component-utilities auf `./ssf-de.js` um und
// pinnt den einen verbliebenen `toLocaleString`-Aufruf auf `de-DE` (BPULS-080).
// Begruendung, warum an dieser Stelle und nicht in SQL: Kopf von `tools/ssf-de.js`.
//
// Laeuft als `pre`-Schritt vor jedem Bau, nicht als `postinstall`: node_modules wird im
// Image in einer eigenen Stufe installiert und danach nur kopiert -- ein
// `postinstall`-Haken dort saehe diese Datei gar nicht. Das Skript ist deshalb
// wiederholbar und meldet beim zweiten Lauf schlicht, dass nichts zu tun war.
//
// Es bricht ab, wenn ein Ankerpunkt fehlt. Ein stillschweigend uebersprungener Patch
// waere der schlechtere Fall: die Seite baute durch und zeigte wieder `32,126.0`.
import { existsSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const hier = dirname(fileURLToPath(import.meta.url));
const dashboard = join(hier, '..');
const paketSrc = join(dashboard, 'node_modules', '@evidence-dev', 'component-utilities', 'src');

const ERSETZUNGEN = [
	{ datei: 'formatting.js', anker: "import ssf from 'ssf';", ersatz: "import ssf from './ssf-de.js';" },
	{ datei: 'autoFormatting.js', anker: "import ssf from 'ssf';", ersatz: "import ssf from './ssf-de.js';" },
	{ datei: 'builtInFormats.js', anker: "import ssf from 'ssf';", ersatz: "import ssf from './ssf-de.js';" },
	{
		// fallbackFormat: greift fuer Spalten ohne jede Formatangabe. `undefined` heisst
		// "Locale der Laufzeitumgebung" -- im Browser die des Lesers, beim Vorabrendern
		// die des Servers. Beides ist nicht die Schreibweise, die die Seite zusagt.
		datei: 'autoFormatting.js',
		anker: 'typedValue.toLocaleString(undefined, {',
		ersatz: "typedValue.toLocaleString('de-DE', {"
	}
];

const abbruch = (meldung) => {
	console.error(`zahlen: ${meldung}`);
	process.exit(1);
};

if (!existsSync(paketSrc)) {
	abbruch(`${paketSrc} fehlt -- erst \`npm ci\` laufen lassen`);
}

let veraendert = false;

const wrapperQuelle = readFileSync(join(hier, 'ssf-de.js'), 'utf8');
const wrapperZiel = join(paketSrc, 'ssf-de.js');
if (!existsSync(wrapperZiel) || readFileSync(wrapperZiel, 'utf8') !== wrapperQuelle) {
	writeFileSync(wrapperZiel, wrapperQuelle);
	veraendert = true;
}

for (const { datei, anker, ersatz } of ERSETZUNGEN) {
	const pfad = join(paketSrc, datei);
	if (!existsSync(pfad)) abbruch(`${datei} fehlt in component-utilities`);

	const inhalt = readFileSync(pfad, 'utf8');
	if (inhalt.includes(anker)) {
		writeFileSync(pfad, inhalt.replace(anker, ersatz));
		veraendert = true;
	} else if (!inhalt.includes(ersatz)) {
		abbruch(
			`Ankerpunkt in ${datei} nicht gefunden: "${anker}". ` +
				'Vermutlich hat sich component-utilities geaendert -- ' +
				'Formatierung dort neu suchen (BPULS-080), nicht ungeprueft weiterbauen.'
		);
	}
}

if (veraendert) {
	// Vite bundelt `component-utilities/formatting` vor (optimizeDeps.include). Bliebe
	// der Cache stehen, liefe `evidence dev` nach dem Einbau weiter auf der alten,
	// englischen Fassung.
	for (const cache of [
		join(dashboard, 'node_modules', '.vite'),
		join(dashboard, '.evidence', 'template', 'node_modules', '.vite')
	]) {
		rmSync(cache, { recursive: true, force: true });
	}
}

console.log(veraendert ? 'zahlen: deutsche Schreibweise eingebaut' : 'zahlen: schon deutsch');
