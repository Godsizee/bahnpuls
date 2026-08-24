#!/usr/bin/env node
// Misst, was eine Seite im **Browser** kostet (BPULS-078) -- nicht die Dateigroesse auf
// der Platte, sondern das, was ein Leser wirklich abruft.
//
// Warum ueberhaupt gemessen wird: die Grenzen der Quellen (3 Betriebstage x 6 Fahrten je
// Linie, 200 Abschnitte, 30 Tage) sind an Fixtures gewaehlt, nicht an Produktionsdaten.
// Mit wachsender Historie wandert die Last, und die Laufweg-Seite ist genau daran schon
// einmal gestorben (BPULS-056: 707.585 Zeilen, 347 MB je Aufruf, Timeout beim
// Initialisieren von DuckDB-WASM).
//
// **Gezaehlt wird mit der Ressourcen-Zeitleiste des Browsers**, nicht mit einer eigenen
// Buchfuehrung ueber Netzwerkereignisse. Die erste Fassung tat das und lag daneben:
// Weiterleitungen liessen den Zaehler offener Anfragen nie auf null gehen, und fuer
// Anfragen aus einem spaet angehaengten Worker fehlte die URL, sodass ausgerechnet die
// Datendateien als "sonstiges" gefuehrt wurden. `performance.getEntriesByType('resource')`
// ist die Buchfuehrung des Browsers selbst.
//
// Kein Puppeteer, keine neue Abhaengigkeit: Chrome haengt am DevTools-Protokoll, der
// WebSocket-Client steckt seit Node 22 in der Laufzeit.
//
// Aufruf:
//   node deploy/dashboard-ladezeit-messen.js [basis-url] [--langsam] [--json]
//
//   --langsam  drosselt auf 1,6 Mbit/s und 150 ms RTT (grob ein Mobilfunknetz). Der
//              Backlog verlangt genau diesen Blick: ein Ladebalken waehrend einer
//              Vorfuehrung kostet mehr als eine fehlende Seite.
//
// Exit 2 heisst Befund, jeder andere Fehlschlag heisst, der Messer selbst ist gescheitert
// -- dieselbe Trennung wie in dashboard-seitenabfragen-pruefen.py (BPULS-065).
import { spawn } from 'node:child_process';
import { existsSync, mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';

const BASIS = (
	process.argv.find((a) => a.startsWith('http')) ?? 'https://bahnpuls.dasdann.jetzt'
).replace(/\/$/, '');
const LANGSAM = process.argv.includes('--langsam');
const ALS_JSON = process.argv.includes('--json');

// Ohne die Bahnhofsseite waere die neueste und ungemessenste Seite gerade die, die in
// einer Vorfuehrung angeklickt wird.
const SEITEN = [
	'/',
	'/befunde/',
	'/bahnhoefe/',
	'/bahnhof/frankfurt-main-hbf/',
	'/laufweg/',
	'/engpaesse/',
	'/puffer/',
	'/puenktlichkeit/',
	'/methodik/'
];

// Welches Auswahlfeld auf welcher Seite umgestellt wird. Nur Seiten mit Eingaben stehen
// hier -- auf den uebrigen gibt es nichts umzustellen.
const INTERAKTION = { '/laufweg/': 'Betriebstag' };

const RUHE_MS = 2500;
// Mindestens so lange zusehen, auch wenn es schon ruhig aussieht. Evidence laedt seine
// Diagrammbibliothek erst nach, wenn eine Komponente sie braucht -- wer zu frueh
// aufhoert, misst 0,7 MB fuer eine Seite, die in Wahrheit 3,6 MB holt. Genau diese
// Schwankung stand in den ersten Laeufen in der Tabelle.
// Gedrosselt dauert alles laenger -- mit denselben 8 s waere die Messung fertig, bevor
// die nachgeladenen Teile ueberhaupt angekommen sind, und die gedrosselte Seite saehe
// **kleiner** aus als die schnelle.
const MINDESTDAUER_MS = process.argv.includes('--langsam') ? 25000 : 8000;
const ZEITLIMIT_MS = 45000;

const BROWSER = [
	process.env.BAHNPULS_BROWSER,
	'C:/Program Files/Google/Chrome/Application/chrome.exe',
	'C:/Program Files (x86)/Google/Chrome/Application/chrome.exe',
	'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',
	'/usr/bin/google-chrome',
	'/usr/bin/chromium'
].find((p) => p && existsSync(p));

const abbrechen = (meldung, code = 1) => {
	console.error(`ladezeit: ${meldung}`);
	process.exit(code);
};

if (!BROWSER) abbrechen('kein Chrome/Edge gefunden -- Pfad ueber BAHNPULS_BROWSER setzen');

const schlafen = (ms) => new Promise((r) => setTimeout(r, ms));

async function browserStarten() {
	const profil = mkdtempSync(path.join(tmpdir(), 'bahnpuls-ladezeit-'));
	const prozess = spawn(
		BROWSER,
		[
			'--headless=new',
			'--disable-gpu',
			'--no-first-run',
			'--no-default-browser-check',
			// Gross genug, dass die Auswahlliste unter einem Feld noch im Bild liegt: bei
			// den 800x600 der Voreinstellung lag sie darunter und liess sich nicht bedienen.
			'--window-size=1400,1200',
			`--user-data-dir=${profil}`,
			'--remote-debugging-port=0',
			'about:blank'
		],
		{ stdio: 'ignore' }
	);

	const portDatei = path.join(profil, 'DevToolsActivePort');
	for (let versuch = 0; versuch < 100; versuch++) {
		await schlafen(100);
		if (existsSync(portDatei)) {
			const port = readFileSync(portDatei, 'utf-8').split('\n')[0].trim();
			if (port) return { prozess, profil, port };
		}
		if (prozess.exitCode !== null) break;
	}
	prozess.kill();
	throw new Error('Browser hat keinen Debug-Port gemeldet');
}

/** Duenne CDP-Huelle: senden, auswerten, schliessen. */
async function verbinden(port) {
	const liste = await fetch(`http://127.0.0.1:${port}/json/list`).then((r) => r.json());
	const ziel = liste.find((z) => z.type === 'page');
	if (!ziel) throw new Error('kein Seiten-Ziel im Browser');

	const ws = new WebSocket(ziel.webSocketDebuggerUrl);
	let naechste = 1;
	const offen = new Map();

	ws.addEventListener('message', (nachricht) => {
		const daten = JSON.parse(nachricht.data);
		if (daten.id && offen.has(daten.id)) {
			const { aufloesen, ablehnen } = offen.get(daten.id);
			offen.delete(daten.id);
			daten.error ? ablehnen(new Error(daten.error.message)) : aufloesen(daten.result);
		}
	});
	await new Promise((r, x) => {
		ws.addEventListener('open', r, { once: true });
		ws.addEventListener('error', () => x(new Error('WebSocket zum Browser fehlgeschlagen')), {
			once: true
		});
	});

	const senden = (method, params = {}) =>
		new Promise((aufloesen, ablehnen) => {
			const id = naechste++;
			offen.set(id, { aufloesen, ablehnen });
			ws.send(JSON.stringify({ id, method, params }));
		});

	const auswerten = async (ausdruck) => {
		const antwort = await senden('Runtime.evaluate', {
			expression: `(() => { ${ausdruck} })()`,
			returnByValue: true,
			awaitPromise: true
		});
		if (antwort.exceptionDetails) {
			throw new Error(
				antwort.exceptionDetails.exception?.description ?? 'Auswertung in der Seite fehlgeschlagen'
			);
		}
		return antwort.result.value;
	};

	return { senden, auswerten, schliessen: () => ws.close() };
}

// Die Zeitleiste des Browsers auslesen und zusammenfassen. Laeuft **in** der Seite.
const ZEITLEISTE = String.raw`
	const art = (u) => {
		// '.arrow' sind die beim Bau vorgerechneten Abfrageergebnisse, '.parquet' liest
		// DuckDB-WASM im Browser selbst. Beides sind Daten, aber es sind zwei Wege -- und
		// der Unterschied erklaert die Last einer Seite.
		if (u.includes('/prerendered_queries/') || u.endsWith('.arrow')) return 'vorgerechnet';
		if (u.endsWith('.parquet') || u.includes('/data/')) return 'daten';
		if (u.endsWith('.wasm')) return 'wasm';
		if (u.endsWith('.js')) return 'js';
		if (u.endsWith('.css')) return 'css';
		if (/\.(woff2?|ttf|png|svg|ico)$/.test(u)) return 'schrift/bild';
		return 'sonstiges';
	};
	const eintraege = performance.getEntriesByType('resource');
	const nach_art = {};
	let groesste = { url: null, bytes: 0 };
	let bytes = 0;
	let letztes_ende = 0;
	for (const e of eintraege) {
		const b = e.transferSize || e.encodedBodySize || 0;
		bytes += b;
		nach_art[art(e.name)] = (nach_art[art(e.name)] ?? 0) + b;
		if (b > groesste.bytes) groesste = { url: e.name, bytes: b };
		letztes_ende = Math.max(letztes_ende, e.responseEnd);
	}
	const seite = performance.getEntriesByType('navigation')[0];
	// Das Dokument selbst steht nicht in der Ressourcenliste.
	bytes += seite ? seite.transferSize : 0;
	nach_art.dokument = seite ? seite.transferSize : 0;
	const text = document.body.innerText || '';
	return {
		bytes,
		anfragen: eintraege.length + 1,
		nach_art,
		groesste,
		dom_ms: seite ? Math.round(seite.domContentLoadedEventEnd) : null,
		fertig_ms: Math.round(letztes_ende),
		hat_zahlen: /[0-9]/.test(text),
		leer_hinweise: text.split('Dataset is empty').length - 1
	};
`;

/** Warten, bis keine neue Ressource mehr dazukommt. Gibt true zurueck, wenn das Zeitlimit riss. */
async function aufRuheWarten(cdp, beginn, mindestens = MINDESTDAUER_MS) {
	let zuletzt = -1;
	let seit = Date.now();
	while (Date.now() - beginn < ZEITLIMIT_MS) {
		await schlafen(250);
		const anzahl = await cdp
			.auswerten('return performance.getEntriesByType("resource").length;')
			.catch(() => zuletzt);
		if (anzahl !== zuletzt) {
			zuletzt = anzahl;
			seit = Date.now();
		} else if (Date.now() - seit > RUHE_MS && Date.now() - beginn > mindestens) {
			return false;
		}
	}
	return true;
}

/**
 * Ein Evidence-Auswahlfeld oeffnen und einen **anderen** Wert waehlen.
 *
 * Ueber die Tastatur, nicht ueber Koordinaten: die Liste stammt aus `cmdk`, sitzt in
 * einem Portal und wird beim Scrollen neu positioniert -- ein Klick auf zuvor gemessene
 * Koordinaten landet daneben, und zwar lautlos. Die Eingabetaste braucht dabei das
 * `char`-Ereignis; ohne das wandert nur die Hervorhebung, uebernommen wird nichts.
 */
async function auswahlUmstellen(cdp, beschriftung) {
	const feld = await cdp.auswerten(`
		const b = document.querySelector('button[aria-label=${JSON.stringify(beschriftung)}]');
		if (!b) return null;
		b.scrollIntoView({ block: 'center' });
		const r = b.getBoundingClientRect();
		return { text: b.textContent.trim(), x: r.x + r.width / 2, y: r.y + r.height / 2 };
	`);
	if (!feld) return { vorher: null, nachher: null };

	for (const type of ['mousePressed', 'mouseReleased']) {
		await cdp.senden('Input.dispatchMouseEvent', {
			type,
			x: feld.x,
			y: feld.y,
			button: 'left',
			clickCount: 1
		});
	}
	await schlafen(900);

	const taste = async (key, keyCode, text) => {
		const grund = { key, code: key, windowsVirtualKeyCode: keyCode, nativeVirtualKeyCode: keyCode };
		await cdp.senden('Input.dispatchKeyEvent', { type: 'rawKeyDown', ...grund });
		if (text !== undefined) {
			await cdp.senden('Input.dispatchKeyEvent', { type: 'char', text, ...grund });
		}
		await cdp.senden('Input.dispatchKeyEvent', { type: 'keyUp', ...grund });
	};

	await taste('ArrowDown', 40);
	await schlafen(250);
	await taste('Enter', 13, String.fromCharCode(13));
	await schlafen(800);

	const nachher = await cdp.auswerten(`
		const b = document.querySelector('button[aria-label=${JSON.stringify(beschriftung)}]');
		return b ? b.textContent.trim() : null;
	`);
	return { vorher: feld.text, nachher };
}

async function seiteMessen(cdp, pfad) {
	const url = BASIS + pfad;
	// Jede Seite von vorn. Mit warmem Cache aus dem vorherigen Aufruf schwankten dieselben
	// Seiten zwischen 0,7 und 3,4 MB -- gemessen waere dann die Reihenfolge, nicht die Seite.
	await cdp.senden('Network.setCacheDisabled', { cacheDisabled: true });
	// `setCacheDisabled` allein genuegt nicht: der Speicher-Cache des Renderers liefert
	// weiter, und dann meldet dieselbe Seite je nach Reihenfolge 0,7 statt 3,6 MB --
	// gemessen waere die Reihenfolge, nicht die Seite.
	await cdp.senden('Network.clearBrowserCache');
	await cdp.senden('Page.navigate', { url: 'about:blank' });
	await schlafen(300);

	const beginn = Date.now();
	await cdp.senden('Page.navigate', { url });
	let zeitlimit = await aufRuheWarten(cdp, beginn);

	// **Einmal durchscrollen wie ein Leser.** Evidence laedt die Diagrammbibliothek erst,
	// wenn ein Diagramm ins Bild kommt -- ohne Scrollen meldete dieselbe Seite je nach
	// Lage der ersten Grafik 1,5 statt 3,6 MB. Gemessen waere dann der Bildausschnitt.
	await cdp.auswerten(`
		return new Promise((fertig) => {
			let y = 0;
			const schritt = () => {
				y += window.innerHeight;
				window.scrollTo(0, y);
				if (y < document.body.scrollHeight) setTimeout(schritt, 250);
				else { window.scrollTo(0, 0); fertig(true); }
			};
			schritt();
		});
	`);
	zeitlimit = (await aufRuheWarten(cdp, Date.now(), 0)) || zeitlimit;

	const messung = await cdp.auswerten(ZEITLEISTE);
	messung.url = url;
	messung.zeitlimit = zeitlimit;

	if (INTERAKTION[pfad]) {
		const vorherAnfragen = messung.anfragen;
		const beginnInteraktion = Date.now();
		const umgestellt = await auswahlUmstellen(cdp, INTERAKTION[pfad]);
		await aufRuheWarten(cdp, beginnInteraktion, 0);
		const danach = await cdp.auswerten(ZEITLEISTE);
		messung.interaktion = {
			feld: INTERAKTION[pfad],
			...umgestellt,
			bytes: danach.bytes - messung.bytes,
			anfragen: danach.anfragen - vorherAnfragen,
			ms: Math.max(0, Date.now() - beginnInteraktion - RUHE_MS)
		};
	}
	return messung;
}

const mb = (b) => (b / 1024 / 1024).toFixed(2);
const sek = (ms) => (ms / 1000).toFixed(1);

async function main() {
	const { prozess, profil, port } = await browserStarten();
	let befunde = 0;
	try {
		const cdp = await verbinden(port);
		await cdp.senden('Page.enable');
		await cdp.senden('Network.enable');
		if (LANGSAM) {
			await cdp.senden('Network.emulateNetworkConditions', {
				offline: false,
				latency: 150,
				downloadThroughput: (1.6 * 1024 * 1024) / 8,
				uploadThroughput: (750 * 1024) / 8
			});
		}

		const ergebnisse = [];
		for (const seite of SEITEN) ergebnisse.push(await seiteMessen(cdp, seite));
		cdp.schliessen();

		if (ALS_JSON) {
			console.log(JSON.stringify({ basis: BASIS, langsam: LANGSAM, seiten: ergebnisse }, null, 2));
		} else {
			console.log(`ladezeit: ${BASIS}${LANGSAM ? '  (gedrosselt: 1,6 Mbit/s, 150 ms RTT)' : ''}`);
			console.log(
				[
					'Seite'.padEnd(30),
					'MB'.padStart(7),
					'Arrow'.padStart(8),
					'Parquet'.padStart(9),
					'Anfr.'.padStart(7),
					'DOM'.padStart(8),
					'fertig'.padStart(8)
				].join('')
			);
			for (const e of ergebnisse) {
				console.log(
					[
						new URL(e.url).pathname.padEnd(30),
						mb(e.bytes).padStart(7),
						mb(e.nach_art.vorgerechnet ?? 0).padStart(8),
						mb(e.nach_art.daten ?? 0).padStart(9),
						String(e.anfragen).padStart(7),
						(sek(e.dom_ms) + 's').padStart(8),
						(e.zeitlimit ? 'LIMIT' : sek(e.fertig_ms) + 's').padStart(8)
					].join('')
				);
			}
			for (const e of ergebnisse.filter((x) => x.interaktion)) {
				const i = e.interaktion;
				console.log(
					`ladezeit: ${new URL(e.url).pathname} -- "${i.feld}" umgestellt ` +
						`(${i.vorher} -> ${i.nachher}): +${mb(i.bytes)} MB, +${i.anfragen} Anfragen, ${sek(i.ms)}s`
				);
			}
			const groesste = ergebnisse.map((e) => e.groesste).sort((a, b) => b.bytes - a.bytes)[0];
			console.log(`ladezeit: groesste einzelne Antwort ${mb(groesste.bytes)} MB -- ${groesste.url}`);
		}

		for (const e of ergebnisse) {
			const pfad = new URL(e.url).pathname;
			if (e.zeitlimit) {
				console.error(`ladezeit: BEFUND -- ${pfad} war nach ${ZEITLIMIT_MS / 1000}s nicht fertig`);
				befunde++;
			}
			if (!e.hat_zahlen) {
				console.error(`ladezeit: BEFUND -- ${pfad} zeigt keine einzige Zahl`);
				befunde++;
			}
			// Eine Umstellung, die den Wert nicht aendert, ist keine Messung -- sie sieht
			// nur aus wie eine.
			if (e.interaktion && e.interaktion.vorher === e.interaktion.nachher) {
				console.error(
					`ladezeit: BEFUND -- ${pfad}: "${e.interaktion.feld}" stand vorher und nachher auf ` +
						`${e.interaktion.vorher} -- gemessen ist damit nur der erste Aufruf`
				);
				befunde++;
			}
		}
	} finally {
		prozess.kill();
		// Windows gibt die Profildateien erst frei, wenn der Prozess wirklich weg ist. Ein
		// liegengebliebenes Temp-Verzeichnis ist kein Grund, die Messung als gescheitert zu melden.
		await schlafen(500);
		try {
			rmSync(profil, { recursive: true, force: true });
		} catch {
			/* bleibt liegen */
		}
	}
	if (befunde) process.exit(2);
}

main().catch((fehler) => abbrechen(fehler.message, 1));
