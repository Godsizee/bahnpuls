// Prueft die deutsche Schreibweise der Zahlen (BPULS-080).
//
// Geprueft wird der Wrapper und der eingebaute Zustand von `autoFormatting.js` -- also
// auch der Pfad fuer Spalten ganz ohne Formatangabe. `formatting.js` und
// `builtInFormats.js` importieren ohne Dateiendung und laufen nur im Bundler; dass der
// Einbau dort greift, zeigt der Evidence-Bau selbst.
//
// Lauf: `node --test tools/ssf-de.test.mjs` im Ordner dashboard/, nach
// `node tools/zahlen-auf-deutsch-einbauen.mjs`.
import { strict as assert } from 'node:assert';
import test from 'node:test';

import ssfDe from './ssf-de.js';
import {
	autoFormat,
	fallbackFormat,
	generateImplicitNumberFormat
} from '../node_modules/@evidence-dev/component-utilities/src/autoFormatting.js';

// Der Punkt muss im Formatcode als Literal stehen. `dd.mm.yyyy` wirft in ssf
// `bad second format` -- es liest den Punkt hinter `mm` als Bruchteil einer Sekunde.
// Deshalb steht auf den Seiten die gequotete Form.
const DATUM_DE = 'dd"."mm"."yyyy';

const faelle = [
	['Tausendertrenner und Dezimalstelle', () => ssfDe.format('#,##0.0', 32126), '32.126,0'],
	['mehrere Tausendergruppen', () => ssfDe.format('#,##0', 1234567), '1.234.567'],
	['zwei Nachkommastellen', () => ssfDe.format('#,##0.00', 4.1), '4,10'],
	['negative Zahl', () => ssfDe.format('#,##0.0', -1234.5), '-1.234,5'],
	['Prozent', () => ssfDe.format('0.0%', 0.828), '82,8%'],
	// Der Punkt im Literal ist ein Satzzeichen, kein Dezimaltrenner.
	['Literal im Formatcode', () => ssfDe.format('#,##0 "Min."', 1234), '1.234 Min.'],
	['Datum als Datumswert', () => ssfDe.format(DATUM_DE, new Date(2026, 7, 24)), '24.08.2026'],
	// Datumsformat auf eine Zahl angewandt: die Punkte sind auch dann Datumstrenner.
	['Datum als Excel-Serie', () => ssfDe.format(DATUM_DE, 46258), '24.08.2026'],
	['Text bleibt Text', () => ssfDe.format('@', 'Frankfurt, Hbf'), 'Frankfurt, Hbf'],
	['ohne jede Formatangabe', () => fallbackFormat(1234.5), '1.234,5'],
	['ganze Zahl ohne Formatangabe', () => fallbackFormat(32126), '32.126']
];

test('ungequoteter Datumscode wirft weiterhin', () => {
	assert.throws(() => ssfDe.format('dd.mm.yyyy', new Date(2026, 7, 24)));
});

for (const [name, rechnen, erwartet] of faelle) {
	test(name, () => assert.equal(rechnen(), erwartet));
}

test('automatisch abgeleitetes Zahlenformat mit Einheit', () => {
	const spalte = { min: 100, max: 90000, median: 32126, maxDecimals: 1, unitType: 'number' };
	assert.equal(autoFormat(32126.4, generateImplicitNumberFormat(spalte), spalte), '32,1k');
});
