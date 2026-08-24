package scope

import (
	"encoding/csv"
	"fmt"
	"io"
	"math"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
)

// Der Name ist der bestaendige Schluessel des Gebiets, die stop_id ist es nicht
// (BPULS-073).
//
// Gemessen am 2026-08-23: von den 1.916 IDs, mit denen der Collector seit dem
// 19.08. lief, standen nach der Veroeffentlichung vom 22.08. noch **48** im
// Fahrplan. Der Echtzeit-Feed folgt der neuen Version sofort -- von 69.260
// stop_id-Werten eines Live-Abrufs loesten **alle** in v=2026-08-22 auf und
// keiner in einer aelteren. Die Liste war damit ab 22.08. 08:41 blind fuer die
// Bahn und traf nur noch, was zufaellig dieselbe Nummer im Nahverkehrsfeed
// hatte: die Bilanz sah 84-93 % gebietsfremde Fahrten, und das war kein Fehler
// der Bewertung, sondern ihr richtiges Urteil ueber falsch eingesammelte Daten.
//
// Ein Bahnhof wechselt aber nicht das Gebiet, weil er eine neue Nummer bekommt.
// Deshalb wird die ID-Liste nach jeder Veroeffentlichung **aus den Namen neu
// abgeleitet**, statt von Hand nachgezogen zu werden -- derselbe Gedanke, der in
// stg_de_static fuer Namen und in stg_de_gebietshalt fuer die Zugehoerigkeit
// schon gilt (BPULS-075).

// Eintrag ist eine Zeile der Gebietsliste: die Station mit ihrem Ort und der
// ID, unter der eine Fahrplanversion sie fuehrt.
type Eintrag struct {
	StopID   string
	StopName string
	Lat      float64
	Lon      float64
}

// Bericht haelt fest, was ein Nachtragen veraendert hat. Er ist nicht Kosmetik:
// an ihm entscheidet sich, ob die neue Version die Liste traegt oder ob sie
// gerade lautlos leerlaeuft.
type Bericht struct {
	Bestand         int
	Namen           int
	NamenMitTreffer int
	Neu             int
	OrtZuWeit       int
}

// Diese Spannen trennen dieselbe Station von einer gleichnamigen anderswo.
//
// Bahnsteige und DELFI-Schreibvarianten derselben Station liegen wenige hundert
// Meter auseinander; ein Namensvetter liegt Bundeslaender entfernt. Gemessen an
// v=2026-08-22: von 1.804 IDs, die der Namensabgleich liefert, liegt genau
// **eine** ausserhalb -- `Altenstadt Bahnhof` in Bayern gegen `Altenstadt(Hess)`
// im RMV. Ohne die Ortspruefung waere sie mit eingesammelt worden.
//
// Grad statt Kilometer, weil dafuer keine Projektion noetig ist: 0,1 Grad Breite
// sind rund 11 km, 0,15 Grad Laenge auf 50 Grad Nord rund 10,7 km.
const (
	maxBreitenabstand = 0.1
	maxLaengenabstand = 0.15
)

// Lesen liest eine Gebietsliste (stop_id,stop_name,stop_lat,stop_lon).
func Lesen(pfad string) ([]Eintrag, error) {
	f, err := os.Open(pfad)
	if err != nil {
		return nil, fmt.Errorf("scope: gebietsliste %q oeffnen: %w", pfad, err)
	}
	defer f.Close()

	eintraege, err := lesen(f)
	if err != nil {
		return nil, fmt.Errorf("scope: gebietsliste %q lesen: %w", pfad, err)
	}
	return eintraege, nil
}

func lesen(r io.Reader) ([]Eintrag, error) {
	reader := csv.NewReader(r)
	reader.TrimLeadingSpace = true

	header, err := reader.Read()
	if err != nil {
		return nil, fmt.Errorf("read header: %w", err)
	}
	idCol, err := columnIndex(header, "stop_id")
	if err != nil {
		return nil, err
	}
	nameCol, err := columnIndex(header, "stop_name")
	if err != nil {
		return nil, err
	}
	latCol, err := columnIndex(header, "stop_lat")
	if err != nil {
		return nil, err
	}
	lonCol, err := columnIndex(header, "stop_lon")
	if err != nil {
		return nil, err
	}

	var eintraege []Eintrag
	for {
		record, err := reader.Read()
		if err == io.EOF {
			break
		}
		if err != nil {
			return nil, fmt.Errorf("read row: %w", err)
		}
		id := strings.TrimSpace(record[idCol])
		if id == "" {
			continue
		}
		eintraege = append(eintraege, Eintrag{
			StopID:   id,
			StopName: strings.TrimSpace(record[nameCol]),
			Lat:      gradOderNaN(record[latCol]),
			Lon:      gradOderNaN(record[lonCol]),
		})
	}
	if len(eintraege) == 0 {
		return nil, fmt.Errorf("no stop_id entries found")
	}
	return eintraege, nil
}

// gradOderNaN liefert NaN statt eines Fehlers: eine Zeile ohne Koordinate ist
// als Filtereintrag brauchbar, sie kann nur keinen Namensvetter mehr abweisen.
func gradOderNaN(feld string) float64 {
	wert, err := strconv.ParseFloat(strings.TrimSpace(feld), 64)
	if err != nil {
		return math.NaN()
	}
	return wert
}

// Nachtragen ergaenzt die Liste um die IDs, unter denen dieselben Stationen in
// einer neuen Fahrplanversion gefuehrt werden. Die stops.txt-Quellen sind die
// Bahn-Feeds dieser Version, nicht der Nahverkehr.
//
// **Ergaenzen, nicht ersetzen** -- und zwar nicht aus Vorsicht vor der Rotation,
// sondern wegen Regel 3: die Liste entscheidet, was ueberhaupt mitgeschrieben
// wird, und was nicht mitgeschrieben wird, ist endgueltig weg. Eine alte ID zu
// behalten kostet Fremdverkehr, den die Transformationsschicht ausschliesst; eine
// zu frueh entfernte kostet Historie.
func Nachtragen(bestand []Eintrag, quellen ...io.Reader) ([]Eintrag, Bericht, error) {
	bekannt := make(map[string]struct{}, len(bestand))
	orte := make(map[string][]Eintrag)
	for _, e := range bestand {
		bekannt[e.StopID] = struct{}{}
		orte[e.StopName] = append(orte[e.StopName], e)
	}

	bericht := Bericht{Bestand: len(bestand), Namen: len(orte)}
	getroffen := make(map[string]struct{}, len(orte))
	ergebnis := append([]Eintrag(nil), bestand...)

	for _, quelle := range quellen {
		kandidaten, err := Haltestellen(quelle)
		if err != nil {
			return nil, Bericht{}, err
		}
		for _, k := range kandidaten {
			anker, gefuehrt := orte[k.StopName]
			if !gefuehrt {
				continue
			}
			getroffen[k.StopName] = struct{}{}
			if _, schon := bekannt[k.StopID]; schon {
				continue
			}
			if !inDerNaehe(k, anker) {
				bericht.OrtZuWeit++
				continue
			}
			bekannt[k.StopID] = struct{}{}
			ergebnis = append(ergebnis, k)
			bericht.Neu++
		}
	}
	bericht.NamenMitTreffer = len(getroffen)

	sortieren(ergebnis)
	return ergebnis, bericht, nil
}

// inDerNaehe prueft den Kandidaten gegen die bereits bekannten Orte desselben
// Namens. Ein Eintrag ohne Koordinate kann nichts abweisen -- er laesst durch,
// weil eine fehlende Angabe kein Gegenbeweis ist (dieselbe Richtung wie
// int_de_gebietsfremd bei 0 zu 0).
func inDerNaehe(kandidat Eintrag, anker []Eintrag) bool {
	if math.IsNaN(kandidat.Lat) || math.IsNaN(kandidat.Lon) {
		return true
	}
	for _, a := range anker {
		if math.IsNaN(a.Lat) || math.IsNaN(a.Lon) {
			return true
		}
		if math.Abs(a.Lat-kandidat.Lat) <= maxBreitenabstand &&
			math.Abs(a.Lon-kandidat.Lon) <= maxLaengenabstand {
			return true
		}
	}
	return false
}

// Haltestellen liest eine GTFS-stops.txt auf die vier gebrauchten Spalten.
//
// Spaltenreihenfolge und -zahl wechseln zwischen Veroeffentlichungen: v=2026-08-22
// fuehrt stop_name zuerst und stop_id an dritter Stelle. Gelesen wird deshalb ueber
// die Kopfzeile, nie ueber die Position.
func Haltestellen(r io.Reader) ([]Eintrag, error) {
	reader := csv.NewReader(r)
	reader.TrimLeadingSpace = true
	// stops.txt fuehrt je nach Veroeffentlichung unterschiedlich viele Spalten
	// (seit v=2026-08-22 zusaetzlich parent_station und location_type). Ein
	// fester Satz wuerde hier abbrechen, statt die neuen Bahnsteige zu sehen.
	reader.FieldsPerRecord = -1

	header, err := reader.Read()
	if err != nil {
		return nil, fmt.Errorf("scope: stops.txt kopfzeile: %w", err)
	}
	idCol, err := columnIndex(header, "stop_id")
	if err != nil {
		return nil, fmt.Errorf("scope: stops.txt: %w", err)
	}
	nameCol, err := columnIndex(header, "stop_name")
	if err != nil {
		return nil, fmt.Errorf("scope: stops.txt: %w", err)
	}
	latCol, err := columnIndex(header, "stop_lat")
	if err != nil {
		return nil, fmt.Errorf("scope: stops.txt: %w", err)
	}
	lonCol, err := columnIndex(header, "stop_lon")
	if err != nil {
		return nil, fmt.Errorf("scope: stops.txt: %w", err)
	}
	noetig := max(idCol, nameCol, latCol, lonCol) + 1

	var eintraege []Eintrag
	for {
		record, err := reader.Read()
		if err == io.EOF {
			break
		}
		if err != nil {
			return nil, fmt.Errorf("scope: stops.txt zeile: %w", err)
		}
		if len(record) < noetig {
			continue
		}
		id := strings.TrimSpace(record[idCol])
		name := strings.TrimSpace(record[nameCol])
		if id == "" || name == "" {
			continue
		}
		eintraege = append(eintraege, Eintrag{
			StopID:   id,
			StopName: name,
			Lat:      gradOderNaN(record[latCol]),
			Lon:      gradOderNaN(record[lonCol]),
		})
	}
	return eintraege, nil
}

// Schreiben legt die Liste ab -- erst vollstaendig daneben, dann umbenennen.
// Der Collector liest diese Datei im Betrieb neu; eine halb geschriebene Datei
// wuerde ihn genau so blind machen wie eine veraltete.
func Schreiben(pfad string, eintraege []Eintrag) error {
	if err := os.MkdirAll(filepath.Dir(pfad), 0o755); err != nil {
		return fmt.Errorf("scope: verzeichnis anlegen: %w", err)
	}
	tmp, err := os.CreateTemp(filepath.Dir(pfad), ".gebietsliste-*")
	if err != nil {
		return fmt.Errorf("scope: temporaere datei: %w", err)
	}
	fertig := false
	defer func() {
		if !fertig {
			os.Remove(tmp.Name())
		}
	}()

	// csv.Writer statt Formatstring: 363 Bahnhofsnamen tragen selbst ein Komma
	// ("Aglasterhausen, Bahnhof"). Von Hand zusammengesetzt wird daraus eine
	// Zeile mit fuenf Feldern, und der Collector startet nicht mehr.
	w := csv.NewWriter(tmp)
	if err := w.Write([]string{"stop_id", "stop_name", "stop_lat", "stop_lon"}); err != nil {
		return fmt.Errorf("scope: kopfzeile schreiben: %w", err)
	}
	for _, e := range eintraege {
		if err := w.Write([]string{e.StopID, e.StopName, grad(e.Lat), grad(e.Lon)}); err != nil {
			return fmt.Errorf("scope: zeile schreiben: %w", err)
		}
	}
	w.Flush()
	if err := w.Error(); err != nil {
		return fmt.Errorf("scope: schreiben: %w", err)
	}
	if err := tmp.Close(); err != nil {
		return fmt.Errorf("scope: schliessen: %w", err)
	}
	// Die Datei wird vom Collector gelesen, der sie nicht angelegt hat.
	if err := os.Chmod(tmp.Name(), 0o644); err != nil {
		return fmt.Errorf("scope: rechte setzen: %w", err)
	}
	if err := os.Rename(tmp.Name(), pfad); err != nil {
		return fmt.Errorf("scope: gebietsliste veroeffentlichen: %w", err)
	}
	fertig = true
	return nil
}

func grad(wert float64) string {
	if math.IsNaN(wert) {
		return ""
	}
	return strconv.FormatFloat(wert, 'f', -1, 64)
}

// sortieren macht den Unterschied zweier Laeufe lesbar: neue IDs stehen bei
// ihrer Station, nicht am Dateiende.
func sortieren(eintraege []Eintrag) {
	sort.SliceStable(eintraege, func(i, j int) bool {
		if eintraege[i].StopName != eintraege[j].StopName {
			return eintraege[i].StopName < eintraege[j].StopName
		}
		return eintraege[i].StopID < eintraege[j].StopID
	})
}
