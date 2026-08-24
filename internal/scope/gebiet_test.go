package scope

import (
	"math"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// Bestand mit zwei Stationen, eine davon mit einem Namensvetter weit weg.
const gebietCSV = `stop_id,stop_name,stop_lat,stop_lon
8000244,Mannheim Hbf,49.4794,8.4689
8000105,Frankfurt Hbf,50.1069,8.6633
`

// Eine neue Veroeffentlichung: dieselben Stationen unter neuen Nummern, dazu ein
// Bahnsteig, ein Namensvetter in Bayern und eine Station ausserhalb des Gebiets.
const neueVersion = `stop_id,stop_name,stop_lat,stop_lon,location_type,parent_station
100001,Mannheim Hbf,49.4794,8.4689,1,
100002,Mannheim Hbf,49.4796,8.4691,0,100001
100003,Frankfurt Hbf,50.1069,8.6633,1,
100004,Mannheim Hbf,48.1000,11.5000,1,
100005,Hamburg Hbf,53.5528,10.0068,1,
`

func TestNachtragen(t *testing.T) {
	bestand, err := lesen(strings.NewReader(gebietCSV))
	if err != nil {
		t.Fatalf("lesen: %v", err)
	}

	ergaenzt, bericht, err := Nachtragen(bestand, strings.NewReader(neueVersion))
	if err != nil {
		t.Fatalf("Nachtragen: %v", err)
	}

	if bericht.Bestand != 2 || bericht.Namen != 2 {
		t.Errorf("bestand/namen = %d/%d, want 2/2", bericht.Bestand, bericht.Namen)
	}
	// 100001, 100002, 100003 -- nicht 100004 (gleicher Name, 150 km weiter) und
	// nicht 100005 (Name nicht im Gebiet).
	if bericht.Neu != 3 {
		t.Errorf("neu = %d, want 3", bericht.Neu)
	}
	if bericht.OrtZuWeit != 1 {
		t.Errorf("ortZuWeit = %d, want 1", bericht.OrtZuWeit)
	}
	if bericht.NamenMitTreffer != 2 {
		t.Errorf("namenMitTreffer = %d, want 2", bericht.NamenMitTreffer)
	}
	if len(ergaenzt) != 5 {
		t.Fatalf("len(ergaenzt) = %d, want 5", len(ergaenzt))
	}

	ids := map[string]bool{}
	for _, e := range ergaenzt {
		ids[e.StopID] = true
	}
	for _, want := range []string{"8000244", "8000105", "100001", "100002", "100003"} {
		if !ids[want] {
			t.Errorf("stop_id %s fehlt", want)
		}
	}
	for _, nicht := range []string{"100004", "100005"} {
		if ids[nicht] {
			t.Errorf("stop_id %s haette nicht aufgenommen werden duerfen", nicht)
		}
	}
}

// Der Bestand darf nie schrumpfen: was nicht gesammelt wird, ist endgueltig weg
// (CLAUDE.md Regel 3).
func TestNachtragenBehaeltBestand(t *testing.T) {
	bestand, err := lesen(strings.NewReader(gebietCSV))
	if err != nil {
		t.Fatalf("lesen: %v", err)
	}
	// Eine Version, in der keine der beiden Stationen mehr vorkommt.
	ergaenzt, bericht, err := Nachtragen(bestand, strings.NewReader(
		"stop_id,stop_name,stop_lat,stop_lon\n900001,Rostock Hbf,54.0784,12.1311\n"))
	if err != nil {
		t.Fatalf("Nachtragen: %v", err)
	}
	if len(ergaenzt) != 2 {
		t.Errorf("len(ergaenzt) = %d, want 2", len(ergaenzt))
	}
	if bericht.NamenMitTreffer != 0 {
		t.Errorf("namenMitTreffer = %d, want 0", bericht.NamenMitTreffer)
	}
}

func TestNachtragenIstIdempotent(t *testing.T) {
	bestand, err := lesen(strings.NewReader(gebietCSV))
	if err != nil {
		t.Fatalf("lesen: %v", err)
	}
	einmal, _, err := Nachtragen(bestand, strings.NewReader(neueVersion))
	if err != nil {
		t.Fatalf("Nachtragen: %v", err)
	}
	zweimal, bericht, err := Nachtragen(einmal, strings.NewReader(neueVersion))
	if err != nil {
		t.Fatalf("Nachtragen (2): %v", err)
	}
	if bericht.Neu != 0 {
		t.Errorf("zweiter Lauf brachte %d neue IDs, want 0", bericht.Neu)
	}
	if len(zweimal) != len(einmal) {
		t.Errorf("len = %d, want %d", len(zweimal), len(einmal))
	}
}

// Ohne Koordinate laesst sich ein Namensvetter nicht abweisen -- die Zeile wird
// aufgenommen, statt sie stillschweigend zu verwerfen.
func TestNachtragenOhneKoordinate(t *testing.T) {
	bestand, err := lesen(strings.NewReader(
		"stop_id,stop_name,stop_lat,stop_lon\n1,Mannheim Hbf,,\n"))
	if err != nil {
		t.Fatalf("lesen: %v", err)
	}
	if !math.IsNaN(bestand[0].Lat) {
		t.Fatalf("Lat = %v, want NaN", bestand[0].Lat)
	}
	_, bericht, err := Nachtragen(bestand, strings.NewReader(
		"stop_id,stop_name,stop_lat,stop_lon\n2,Mannheim Hbf,48.1,11.5\n"))
	if err != nil {
		t.Fatalf("Nachtragen: %v", err)
	}
	if bericht.Neu != 1 || bericht.OrtZuWeit != 0 {
		t.Errorf("neu/ortZuWeit = %d/%d, want 1/0", bericht.Neu, bericht.OrtZuWeit)
	}
}

// Der Fallstrick, der schon einmal den Collector am Start gehindert hat: 363
// Bahnhofsnamen tragen selbst ein Komma.
func TestSchreibenUndLesenMitKommaImNamen(t *testing.T) {
	pfad := filepath.Join(t.TempDir(), "unter", "scope_stops.csv")
	eintraege := []Eintrag{
		{StopID: "1", StopName: "Aglasterhausen, Bahnhof", Lat: 49.35, Lon: 9.03},
		{StopID: "2", StopName: "Ohne Ort", Lat: math.NaN(), Lon: math.NaN()},
	}
	if err := Schreiben(pfad, eintraege); err != nil {
		t.Fatalf("Schreiben: %v", err)
	}

	filter, err := LoadCSV(pfad)
	if err != nil {
		t.Fatalf("LoadCSV: %v", err)
	}
	if filter.Len() != 2 {
		t.Errorf("filter.Len() = %d, want 2", filter.Len())
	}

	gelesen, err := Lesen(pfad)
	if err != nil {
		t.Fatalf("Lesen: %v", err)
	}
	if gelesen[0].StopName != "Aglasterhausen, Bahnhof" {
		t.Errorf("StopName = %q", gelesen[0].StopName)
	}
	if !math.IsNaN(gelesen[1].Lat) {
		t.Errorf("Lat = %v, want NaN", gelesen[1].Lat)
	}

	// Kein temporaerer Rest neben der Datei.
	eintraegeImVerzeichnis, err := os.ReadDir(filepath.Dir(pfad))
	if err != nil {
		t.Fatalf("ReadDir: %v", err)
	}
	if len(eintraegeImVerzeichnis) != 1 {
		t.Errorf("%d Dateien im Verzeichnis, want 1", len(eintraegeImVerzeichnis))
	}
}

// stops.txt fuehrt je Veroeffentlichung unterschiedlich viele Spalten; ein
// fester Satz haette die neuen Bahnsteige gekostet.
func TestHaltestellenWechselndeSpaltenzahl(t *testing.T) {
	halte, err := Haltestellen(strings.NewReader(
		"stop_id,stop_name,stop_lat,stop_lon,location_type\n" +
			"1,Mannheim Hbf,49.4794,8.4689,1\n" +
			"2,Nur vier Felder,49.5,8.5\n"))
	if err != nil {
		t.Fatalf("Haltestellen: %v", err)
	}
	if len(halte) != 2 {
		t.Fatalf("len = %d, want 2", len(halte))
	}
}
