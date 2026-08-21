// Prueft, ob der laufende Server die Datendateien wirklich ausliefert, die das
// Manifest nennt. Exit 1, sobald eine fehlt.
//
// **Warum das noetig ist:** eine Evidence-Seite, deren Quellen fehlen, antwortet
// von aussen vollkommen unauffaellig -- HTTP 200, richtiger Titel, richtige
// Groesse. Erst im Browser zeigt sich "No sources found". Der Healthcheck fragt
// nur die Startseite ab und kann das nicht sehen; genau so stand die Seite am
// 2026-08-21 mehrere Stunden ohne eine einzige Zahl da.
//
// Kein curl im Image (siehe Dockerfile), also prueft node selbst.
const fs = require('fs');
const http = require('http');

const manifestPfad = process.argv[2] || '/app/dashboard/build/data/manifest.json';
const basis = process.argv[3] || 'http://127.0.0.1:3000';

let manifest;
try {
	manifest = JSON.parse(fs.readFileSync(manifestPfad, 'utf8'));
} catch (err) {
	console.error(`quellen: manifest nicht lesbar (${manifestPfad}): ${err.message}`);
	process.exit(1);
}

// Der Manifest-Pfad ist relativ zum Build-Wurzelverzeichnis und traegt ein
// "static/"-Praefix, das der Server nicht kennt.
const dateien = Object.values(manifest.renderedFiles || {})
	.flat()
	.map((p) => '/' + String(p).replace(/^static\//, ''));

if (dateien.length === 0) {
	console.error('quellen: BEFUND -- das manifest nennt keine einzige Datei');
	process.exit(1);
}

let offen = dateien.length;
let fehlend = 0;

const fertig = () => {
	if (--offen > 0) return;
	if (fehlend > 0) {
		console.error(`quellen: BEFUND -- ${fehlend} von ${dateien.length} Quellen werden nicht ausgeliefert`);
		process.exit(1);
	}
	console.log(`quellen: alle ${dateien.length} ausgeliefert`);
	process.exit(0);
};

for (const pfad of dateien) {
	http
		.get(basis + pfad, (res) => {
			res.resume(); // Body verwerfen, sonst bleibt die Verbindung offen
			if (res.statusCode !== 200) {
				fehlend++;
				console.error(`quellen: ${res.statusCode} ${pfad}`);
			}
			fertig();
		})
		.on('error', (err) => {
			fehlend++;
			console.error(`quellen: nicht erreichbar ${pfad} -- ${err.message}`);
			fertig();
		});
}
