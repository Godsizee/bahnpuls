package static

import (
	"context"
	"os"
	"path/filepath"
	"testing"

	"github.com/parquet-go/parquet-go"
)

func TestHalteSchreiben_NimmtSpaltenUeberDenNamen(t *testing.T) {
	// stops.txt fuehrt je Feed andere Spalten in anderer Reihenfolge. Wer nach
	// Position liest, vertauscht hier Nummer und Name -- und das faellt erst auf,
	// wenn eine Auswertung Bahnhoefe mit Koordinaten als Namen zeigt.
	archiv := filepath.Join(t.TempDir(), "nv.zip")
	schreibeArchiv(t, archiv, map[string]string{
		"stops.txt": "stop_lat,stop_name,stop_lon,stop_id\n" +
			"52.37,Hannover Aegidientorplatz,9.74,517463\n" +
			"49.47,Mannheim Hbf,8.46,442196\n",
	})

	ziel := filepath.Join(t.TempDir(), "unterverzeichnis", HalteDatei)
	zeilen, err := HalteSchreiben(archiv, ziel)
	if err != nil {
		t.Fatalf("HalteSchreiben: %v", err)
	}
	if zeilen != 2 {
		t.Errorf("zeilen = %d, want 2", zeilen)
	}

	halte := leseHalte(t, ziel)
	if len(halte) != 2 {
		t.Fatalf("%d Halte gelesen, want 2", len(halte))
	}
	if halte[0].StopID != "517463" || halte[0].StopName != "Hannover Aegidientorplatz" {
		t.Errorf("erster Halt = %+v", halte[0])
	}
	if halte[1].StopID != "442196" || halte[1].StopName != "Mannheim Hbf" {
		t.Errorf("zweiter Halt = %+v", halte[1])
	}
}

func TestHalteSchreiben_LaesstNichtsHalbesLiegen(t *testing.T) {
	// Ohne stop_name ist die Liste als Negativliste wertlos. Sie darf dann gar
	// nicht entstehen -- eine halbe Datei sieht nachgelagert aus wie eine ganze
	// und liesse Fremdverkehr durch, statt ihn zu melden.
	archiv := filepath.Join(t.TempDir(), "nv.zip")
	schreibeArchiv(t, archiv, map[string]string{
		"stops.txt": "stop_id,stop_lat\n517463,52.37\n",
	})

	ziel := filepath.Join(t.TempDir(), HalteDatei)
	if _, err := HalteSchreiben(archiv, ziel); err == nil {
		t.Fatal("HalteSchreiben ohne stop_name: kein Fehler")
	}
	if _, err := os.Stat(ziel); !os.IsNotExist(err) {
		t.Errorf("Zieldatei existiert trotz Fehler: %v", err)
	}
	if _, err := os.Stat(ziel + ".unvollstaendig"); !os.IsNotExist(err) {
		t.Errorf("Zwischendatei liegen geblieben: %v", err)
	}
}

func TestLaden_NurHalte_BehaeltDieListeUndVerwirftDasArchiv(t *testing.T) {
	// Der Nahverkehrsfeed ist Unterscheidungsmerkmal, nicht Gegenstand: 264 MB je
	// Veroeffentlichung waeren das Doppelte der gesamten eigenen Historie im Jahr.
	archiv := testArchiv(t, map[string]string{
		"stops.txt":      "stop_id,stop_name\n517463,Hannover Aegidientorplatz\n",
		"routes.txt":     "route_id,route_short_name\nR9,U9\n",
		"stop_times.txt": "trip_id,stop_sequence,stop_id,arrival_time,departure_time\nT9,0,517463,08:00:00,08:01:00\n",
	})
	srv, _ := testServer(t, archiv)
	basis := t.TempDir()

	ziel, err := Laden(context.Background(), srv.Client(), basis, "2026-08-24",
		[]Feed{{Name: "nv", URL: srv.URL, NurHalte: true}}, StandardDateien())
	if err != nil {
		t.Fatalf("Laden: %v", err)
	}

	if _, err := os.Stat(filepath.Join(ziel, "nv", HalteDatei)); err != nil {
		t.Errorf("Halteliste fehlt: %v", err)
	}
	if _, err := os.Stat(filepath.Join(ziel, "nv_free.zip")); !os.IsNotExist(err) {
		t.Errorf("Archiv wurde behalten: %v", err)
	}
	// Weder Soll-Halte noch die uebrigen Mitglieder: beides gehoert zum
	// Bahnfahrplan, und aus diesem Feed wuerde beides nur Volumen kosten.
	for _, unerwuenscht := range []string{FahrplanDatei, "stops.txt", "routes.txt"} {
		if _, err := os.Stat(filepath.Join(ziel, "nv", unerwuenscht)); !os.IsNotExist(err) {
			t.Errorf("%s wurde entpackt, sollte es nicht: %v", unerwuenscht, err)
		}
	}
}

func TestLaden_NurHalte_ScheitertNichtDieGanzeVersion(t *testing.T) {
	// Ein Archiv ohne stops.txt darf die Bahn-Feeds nicht mitreissen: die Version
	// ist gesichert, nur die Trennschaerfe fehlt -- dieselbe Abwaegung wie bei den
	// Soll-Halten.
	archiv := testArchiv(t, map[string]string{"agency.txt": "agency_id\n1\n"})
	srv, _ := testServer(t, archiv)
	basis := t.TempDir()

	ziel, err := Laden(context.Background(), srv.Client(), basis, "2026-08-24",
		[]Feed{{Name: "nv", URL: srv.URL, NurHalte: true}}, StandardDateien())
	if err == nil {
		t.Fatal("Laden ohne stops.txt: kein Hinweis auf die fehlende Liste")
	}
	if ziel == "" {
		t.Error("Version wurde nicht veroeffentlicht, obwohl der Download geglueckt ist")
	}
	if _, err := os.Stat(ziel); err != nil {
		t.Errorf("Version fehlt: %v", err)
	}
}

func leseHalte(t *testing.T, pfad string) []Halt {
	t.Helper()
	halte, err := parquet.ReadFile[Halt](pfad)
	if err != nil {
		t.Fatalf("Parquet lesen: %v", err)
	}
	return halte
}
