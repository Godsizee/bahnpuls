package static

import (
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"

	"bahnpuls/internal/scope"
)

// GebietslisteDatei ist der Name der abgeleiteten Gebietsliste auf dem Volume.
//
// Sie liegt neben den Versionen, nicht in einer: sie gilt fuer alle. Und sie
// liegt auf dem Volume, nicht im Image -- eine Liste, die nur ein Rebuild
// aendern kann, ist genau die Liste, die zwischen zwei Deploys veraltet
// (BPULS-073).
const GebietslisteDatei = "scope_stops.csv"

// GebietslistePfad liefert den Ort der abgeleiteten Liste unterhalb von baseDir.
func GebietslistePfad(baseDir string) string {
	return filepath.Join(baseDir, GebietslisteDatei)
}

// NeuesteVersion liefert das Verzeichnis der juengsten abgelegten Version.
//
// Die Versionsnamen sind ISO-Datumsangaben, also ist die lexikalisch groesste
// auch die juengste -- kein Parsen noetig, und ein von Hand angelegter Name wie
// `v=probe` sortiert sich nicht versehentlich nach vorn.
func NeuesteVersion(baseDir string) (string, error) {
	eintraege, err := os.ReadDir(baseDir)
	if err != nil {
		return "", fmt.Errorf("static: verzeichnis lesen: %w", err)
	}
	neueste := ""
	for _, e := range eintraege {
		if !e.IsDir() || !hatVersionsPraefix(e.Name()) {
			continue
		}
		if e.Name() > neueste {
			neueste = e.Name()
		}
	}
	if neueste == "" {
		return "", fmt.Errorf("static: keine version unter %s", baseDir)
	}
	return filepath.Join(baseDir, neueste), nil
}

// GebietslisteNachtragen ergaenzt die Gebietsliste um die IDs der genannten
// Version und schreibt sie auf das Volume. Zurueck kommt der Bericht und der
// Pfad, aus dem der Bestand kam.
//
// Warum das zum Static-Load gehoert und nicht zum Collector: hier liegt die neue
// stops.txt, und hier ist der einzige Zeitpunkt, an dem sich die Zuordnung von
// Name zu Nummer aendert. Der Collector soll sammeln, nicht ableiten (SRP).
//
// vorlage traegt den ersten Lauf: solange auf dem Volume noch keine Liste liegt,
// kommt der Bestand aus dem Image (`config/scope_stops.csv`). Danach ist die
// Datei auf dem Volume die Autoritaet und waechst mit jeder Veroeffentlichung.
func GebietslisteNachtragen(versionsPfad, listePfad, vorlagePfad string, feeds []Feed) (scope.Bericht, string, error) {
	bestand, herkunft, err := bestandLesen(listePfad, vorlagePfad)
	if err != nil {
		return scope.Bericht{}, "", err
	}

	var quellen []io.Reader
	var offen []*os.File
	defer func() {
		for _, f := range offen {
			f.Close()
		}
	}()

	for _, feed := range feeds {
		if feed.NurHalte {
			// Der Nahverkehrsfeed ist Negativliste, nicht Fahrplan (BPULS-070).
			// Seine Halte duerfen das Gebiet nicht vergroessern -- sonst holte
			// jede Bushaltestelle an einem Bahnhof ihre eigene Nummer herein.
			continue
		}
		pfad := filepath.Join(versionsPfad, feed.Name, halteQuelle)
		f, err := os.Open(pfad)
		if err != nil {
			return scope.Bericht{}, "", fmt.Errorf("static: gebietsliste, %s lesen: %w", pfad, err)
		}
		offen = append(offen, f)
		quellen = append(quellen, f)
	}

	ergaenzt, bericht, err := scope.Nachtragen(bestand, quellen...)
	if err != nil {
		return scope.Bericht{}, "", fmt.Errorf("static: gebietsliste ableiten: %w", err)
	}
	if err := scope.Schreiben(listePfad, ergaenzt); err != nil {
		return scope.Bericht{}, "", err
	}
	return bericht, herkunft, nil
}

// GebietslisteDeckung zaehlt, wie viele IDs der Liste die Version noch kennt.
//
// Das ist die Zahl, die am 2026-08-22 gefehlt hat. Der Anteil der Fahrten im
// Scope blieb damals unauffaellig, weil Nahverkehr die Luecke fuellte -- erst
// diese Zahl haette gezeigt, dass die Liste auf einen abgeloesten Nummernkreis
// zeigt: 48 statt 1.843 (BPULS-073).
func GebietslisteDeckung(versionsPfad, listePfad string, feeds []Feed) (treffer, gesamt int, err error) {
	bestand, err := scope.Lesen(listePfad)
	if err != nil {
		return 0, 0, err
	}
	inVersion := make(map[string]struct{})
	for _, feed := range feeds {
		if feed.NurHalte {
			continue
		}
		pfad := filepath.Join(versionsPfad, feed.Name, halteQuelle)
		f, err := os.Open(pfad)
		if err != nil {
			return 0, 0, fmt.Errorf("static: gebietsliste pruefen, %s lesen: %w", pfad, err)
		}
		halte, err := scope.Haltestellen(f)
		f.Close()
		if err != nil {
			return 0, 0, err
		}
		for _, h := range halte {
			inVersion[h.StopID] = struct{}{}
		}
	}
	for _, e := range bestand {
		if _, ok := inVersion[e.StopID]; ok {
			treffer++
		}
	}
	return treffer, len(bestand), nil
}

// bestandLesen nimmt die Liste vom Volume, solange es eine gibt, und faellt sonst
// auf die mitgelieferte Vorlage im Image zurueck.
func bestandLesen(listePfad, vorlagePfad string) ([]scope.Eintrag, string, error) {
	bestand, err := scope.Lesen(listePfad)
	if err == nil {
		return bestand, listePfad, nil
	}
	if !errors.Is(err, os.ErrNotExist) {
		return nil, "", err
	}
	bestand, err = scope.Lesen(vorlagePfad)
	if err != nil {
		return nil, "", err
	}
	return bestand, vorlagePfad, nil
}
