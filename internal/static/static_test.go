package static

import (
	"archive/zip"
	"bytes"
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"runtime"
	"testing"
	"time"
)

func testArchiv(t *testing.T, eintraege map[string]string) []byte {
	t.Helper()
	var puffer bytes.Buffer
	w := zip.NewWriter(&puffer)
	for name, inhalt := range eintraege {
		f, err := w.Create(name)
		if err != nil {
			t.Fatalf("zip.Create(%q): %v", name, err)
		}
		if _, err := f.Write([]byte(inhalt)); err != nil {
			t.Fatalf("schreiben: %v", err)
		}
	}
	if err := w.Close(); err != nil {
		t.Fatalf("zip schliessen: %v", err)
	}
	return puffer.Bytes()
}

func testServer(t *testing.T, archiv []byte) (*httptest.Server, *int) {
	t.Helper()
	abrufe := 0
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		abrufe++
		w.Write(archiv)
	}))
	t.Cleanup(srv.Close)
	return srv, &abrufe
}

func TestVersion(t *testing.T) {
	// Die Version ist ein UTC-Datum. Eine lokale Zeit wuerde je nach Serverzone
	// zwei verschiedene Versionsnamen fuer denselben Lauf ergeben.
	got := Version(time.Date(2026, 8, 20, 23, 30, 0, 0, time.FixedZone("MESZ", 2*3600)))
	if got != "2026-08-20" {
		t.Errorf("Version() = %q, want 2026-08-20", got)
	}
}

func TestLaden_LegtVersionAn(t *testing.T) {
	archiv := testArchiv(t, map[string]string{
		"stops.txt":      "stop_id,stop_name\n1,Mannheim Hbf\n",
		"routes.txt":     "route_id,route_short_name\nR1,RE 70\n",
		"stop_times.txt": "trip_id,stop_sequence,stop_id,arrival_time,departure_time\nT1,0,1,08:00:00,08:01:00\n",
	})
	srv, abrufe := testServer(t, archiv)
	basis := t.TempDir()

	ziel, err := Laden(context.Background(), srv.Client(), basis, "2026-08-20",
		[]Feed{{Name: "rv", URL: srv.URL}}, StandardDateien())
	if err != nil {
		t.Fatalf("Laden: %v", err)
	}
	if *abrufe != 1 {
		t.Errorf("%d Abrufe, want 1", *abrufe)
	}
	if filepath.Base(ziel) != "v=2026-08-20" {
		t.Errorf("Ziel = %q, want .../v=2026-08-20", ziel)
	}

	// Das vollstaendige Archiv bleibt liegen: latest.zip ist nicht nachladbar.
	if _, err := os.Stat(filepath.Join(ziel, "rv_free.zip")); err != nil {
		t.Errorf("Archiv fehlt: %v", err)
	}
	inhalt, err := os.ReadFile(filepath.Join(ziel, "rv", "stops.txt"))
	if err != nil {
		t.Fatalf("stops.txt: %v", err)
	}
	if !bytes.Contains(inhalt, []byte("Mannheim Hbf")) {
		t.Errorf("stops.txt = %q, want Mannheim Hbf", inhalt)
	}
	// stop_times.txt wird bewusst nicht als CSV entpackt -- 85 MB je Version --,
	// sondern auf fuenf Spalten reduziert nach Parquet umgeschrieben.
	if _, err := os.Stat(filepath.Join(ziel, "rv", "stop_times.txt")); !errors.Is(err, os.ErrNotExist) {
		t.Errorf("stop_times.txt wurde als CSV entpackt, want nur die Parquet-Fassung (err=%v)", err)
	}
	if _, err := os.Stat(filepath.Join(ziel, "rv", FahrplanDatei)); err != nil {
		t.Errorf("%s fehlt: %v", FahrplanDatei, err)
	}
}

func TestLaden_VorhandeneVersionBleibtUnangetastet(t *testing.T) {
	srv, abrufe := testServer(t, testArchiv(t, map[string]string{"stops.txt": "neu"}))
	basis := t.TempDir()

	vorhanden := Pfad(basis, "2026-08-20")
	if err := os.MkdirAll(vorhanden, 0o755); err != nil {
		t.Fatalf("vorbereiten: %v", err)
	}
	markierung := filepath.Join(vorhanden, "unberuehrt.txt")
	if err := os.WriteFile(markierung, []byte("alt"), 0o644); err != nil {
		t.Fatalf("vorbereiten: %v", err)
	}

	_, err := Laden(context.Background(), srv.Client(), basis, "2026-08-20",
		[]Feed{{Name: "rv", URL: srv.URL}}, StandardDateien())
	if !errors.Is(err, ErrVersionVorhanden) {
		t.Fatalf("Laden() = %v, want ErrVersionVorhanden", err)
	}
	// Weder heruntergeladen noch angefasst -- der Task darf mehrfach laufen.
	if *abrufe != 0 {
		t.Errorf("%d Abrufe trotz vorhandener Version, want 0", *abrufe)
	}
	if inhalt, _ := os.ReadFile(markierung); string(inhalt) != "alt" {
		t.Errorf("vorhandene Version wurde veraendert: %q", inhalt)
	}
}

func TestLaden_KeineHalbeVersionBeiFehler(t *testing.T) {
	// Zweiter Feed antwortet mit 500: die Version darf danach nicht existieren,
	// sonst saehe ein halber Stand nachgelagert wie ein vollstaendiger aus.
	archiv := testArchiv(t, map[string]string{"stops.txt": "stop_id\n1\n"})
	gut := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Write(archiv)
	}))
	defer gut.Close()
	kaputt := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		http.Error(w, "weg", http.StatusInternalServerError)
	}))
	defer kaputt.Close()

	basis := t.TempDir()
	_, err := Laden(context.Background(), gut.Client(), basis, "2026-08-20",
		[]Feed{{Name: "rv", URL: gut.URL}, {Name: "fv", URL: kaputt.URL}}, StandardDateien())
	if err == nil {
		t.Fatal("Laden() = nil, want Fehler")
	}
	if _, err := os.Stat(Pfad(basis, "2026-08-20")); !errors.Is(err, os.ErrNotExist) {
		t.Errorf("Version existiert nach Fehler (err=%v)", err)
	}
	uebrig, _ := os.ReadDir(basis)
	if len(uebrig) != 0 {
		t.Errorf("Reste im Basisverzeichnis: %v", uebrig)
	}
}

func TestLaden_ArchiveintragKannNichtAusbrechen(t *testing.T) {
	// Ein Eintrag mit Pfadanteilen darf nichts ausserhalb des Zielverzeichnisses
	// schreiben. Verglichen wird der Basisname, geschrieben ein selbst gebauter Pfad.
	archiv := testArchiv(t, map[string]string{
		"../../boeser/stops.txt": "stop_id\n99\n",
	})
	srv, _ := testServer(t, archiv)
	basis := t.TempDir()

	ziel, err := Laden(context.Background(), srv.Client(), basis, "2026-08-20",
		[]Feed{{Name: "rv", URL: srv.URL}}, StandardDateien())
	// Dieses Archiv hat keine stop_times.txt. Erwartet ist deshalb genau die
	// Warnung -- und **nicht** ein Abbruch: das Archiv ist nicht nachladbar und
	// muss auch dann gesichert werden, wenn die abgeleitete Datei scheitert.
	if err != nil && !errors.Is(err, ErrFahrplanUnvollstaendig) {
		t.Fatalf("Laden: %v", err)
	}
	if _, err := os.Stat(filepath.Join(basis, "..", "boeser")); err == nil {
		t.Fatal("Eintrag konnte ausserhalb schreiben")
	}
	if _, err := os.Stat(filepath.Join(ziel, "rv", "stops.txt")); err != nil {
		t.Errorf("Eintrag landete nicht im Ziel: %v", err)
	}
}

func TestLaden_VersionIstLesbarFuerAndere(t *testing.T) {
	// Der schreibende Prozess laeuft als root, der lesende als node. Legt die
	// Version mit 0700 an -- so tut es os.MkdirTemp von sich aus --, sieht der
	// Leser ein leeres Verzeichnis statt einer Fehlermeldung. Genau so ist es in
	// Produktion passiert (2026-08-20).
	if runtime.GOOS == "windows" {
		t.Skip("Unix-Dateirechte auf Windows nicht aussagekraeftig")
	}

	srv, _ := testServer(t, testArchiv(t, map[string]string{"stops.txt": "stop_id,stop_name"}))
	basis := t.TempDir()

	ziel, err := Laden(context.Background(), srv.Client(), basis, "2026-08-20",
		[]Feed{{Name: "rv", URL: srv.URL}}, StandardDateien())
	if err != nil && !errors.Is(err, ErrFahrplanUnvollstaendig) {
		t.Fatalf("Laden: %v", err)
	}

	info, err := os.Stat(ziel)
	if err != nil {
		t.Fatalf("Stat: %v", err)
	}
	if info.Mode().Perm()&0o055 == 0 {
		t.Errorf("Version hat Rechte %v -- fuer andere weder lesbar noch betretbar", info.Mode().Perm())
	}
}
