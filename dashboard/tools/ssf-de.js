// Deutsche Schreibweise fuer alle Zahlen der Seite (BPULS-080).
//
// WARUM diese Datei ueberhaupt existiert: Evidence formatiert jede Zahl -- BigValue,
// DataTable, Diagrammachse, Tooltip -- ueber `ssf` (SheetJS). `ssf` kennt keine Locale;
// Gruppierung und Dezimaltrenner sind fest englisch verdrahtet. Ueber `fmt` ist das
// nicht zu erreichen: `[$-407]#,##0.0` wird als Waehrungsangabe missverstanden
// (`$12,345.7`), `#.##0,0` als kaputter Code (`12345.678`). Evidence 40.1.8 -- die zum
// Zeitpunkt der Umsetzung neueste Fassung -- hat keinen Locale-Haken.
//
// `32,126.0` liest ein deutscher Leser nicht nur ungewohnt, sondern falsch: als
// zweiunddreissig Komma eins. Deshalb wird hier die Ausgabe von `ssf` nachbehandelt,
// statt die Zahlen in SQL zu Zeichenketten zu machen -- Zeichenketten kaemen ohne
// Sortierung in den Tabellen und ohne Achsenbeschriftung in den Diagrammen an.
//
// Eingebaut wird die Datei von `tools/zahlen-auf-deutsch-einbauen.mjs`, das die
// `ssf`-Importe in `@evidence-dev/component-utilities` hierher umbiegt.
import ssf from 'ssf';

// Nur zusammenhaengende Ziffernlaeufe werden getauscht, nicht der ganze Text: ein
// Formatcode darf Literale wie `#,##0 "Min."` enthalten, und deren Punkt ist ein
// Satzzeichen, kein Dezimaltrenner. Ein Trenner am Ende eines Laufs zaehlt aus dem
// gleichen Grund nicht dazu.
const ZAHLENLAUF = /\d[\d.,]*\d|\d/g;

const trennerTauschen = (lauf) => lauf.replace(/[.,]/g, (zeichen) => (zeichen === ',' ? '.' : ','));

export const aufDeutsch = (text) => text.replace(ZAHLENLAUF, trennerTauschen);

function format(formatCode, wert, optionen) {
	const englisch = ssf.format(formatCode, wert, optionen);

	if (typeof englisch !== 'string') return englisch;
	// Datumsangaben bleiben unberuehrt: in `24.08.2026` sind die Punkte Datumstrenner,
	// ein Tausch machte daraus `24,08,2026`. Daten kommen als `Date` herein; ein Datum
	// als Zahl (Excel-Serie) verraet sich ueber den Formatcode.
	if (typeof wert !== 'number') return englisch;
	try {
		if (ssf.is_date(formatCode)) return englisch;
	} catch {
		// Unlesbarer Formatcode: dann hat ssf oben ohnehin nichts Sinnvolles geliefert.
		return englisch;
	}

	return aufDeutsch(englisch);
}

export default { ...ssf, format };
