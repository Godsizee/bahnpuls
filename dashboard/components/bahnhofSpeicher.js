/**
 * Der gemerkte Bahnhof (BPULS-088) -- eine Abkuerzung im Browser des Lesers, nie eine
 * Voraussetzung.
 *
 * **Warum im Browser und nicht auf dem Server:** die Seite ist statisch, es gibt keine
 * Anmeldung, und es werden keine personenbezogenen Daten verarbeitet (CLAUDE.md Regel
 * 12). Ein Bahnhofsname im eigenen `localStorage` verlaesst das Geraet nicht -- das ist
 * keine Ausnahme von der Regel, sondern ihre Einhaltung.
 *
 * **Jeder Zugriff ist gekapselt.** `localStorage` kann werfen, nicht nur leer sein: im
 * privaten Fenster, bei blockierten Website-Daten, in einem `file://`-Kontext. Ein
 * geworfener Fehler beim Lesen wuerde die ganze Seite mitreissen -- und die Seite muss
 * ohne Speicher vollstaendig bleiben.
 */
const SCHLUESSEL = 'bahnpuls.bahnhof';

/** @returns {{slug: string, name: string} | null} */
export function lesen() {
	if (typeof window === 'undefined') return null;
	try {
		const roh = window.localStorage.getItem(SCHLUESSEL);
		if (!roh) return null;
		const wert = JSON.parse(roh);
		// Nur was beide Felder traegt: ein halber Eintrag aus einer aelteren Fassung
		// ergaebe einen Verweis ins Leere.
		if (wert && typeof wert.slug === 'string' && typeof wert.name === 'string') return wert;
		return null;
	} catch {
		return null;
	}
}

export function merken(slug, name) {
	if (typeof window === 'undefined') return;
	try {
		window.localStorage.setItem(SCHLUESSEL, JSON.stringify({ slug, name }));
	} catch {
		// Kein Speicher, kein Drama: die Seite bleibt vollstaendig, der Knopf wirkt nur
		// nicht ueber den Besuch hinaus.
	}
}

export function vergessen() {
	if (typeof window === 'undefined') return;
	try {
		window.localStorage.removeItem(SCHLUESSEL);
	} catch {
		// siehe merken()
	}
}
