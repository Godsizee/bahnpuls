package static

import (
	"errors"
	"os"
	"path/filepath"
	"testing"

	"github.com/parquet-go/parquet-go"
)

func schreibeArchiv(t *testing.T, pfad string, eintraege map[string]string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(pfad), 0o755); err != nil {
		t.Fatalf("verzeichnis: %v", err)
	}
	if err := os.WriteFile(pfad, testArchiv(t, eintraege), 0o644); err != nil {
		t.Fatalf("archiv schreiben: %v", err)
	}
}

func leseFahrplan(t *testing.T, pfad string) []Fahrplanhalt {
	t.Helper()
	zeilen, err := parquet.ReadFile[Fahrplanhalt](pfad)
	if err != nil {
		t.Fatalf("parquet lesen: %v", err)
	}
	return zeilen
}

func TestFahrplanSchreiben_UebernimmtDieFuenfSpalten(t *testing.T) {
	basis := t.TempDir()
	archiv := filepath.Join(basis, "rv_free.zip")
	// Spaltenreihenfolge bewusst anders als in fahrplanSpalten und mit einer
	// Spalte dazwischen, die nicht gebraucht wird: die Zuordnung muss ueber den
	// Namen laufen. Ueber die Position gelesen vertauschte sie Haltestelle und
	// Uhrzeit, und das Ergebnis saehe weiter plausibel aus.
	schreibeArchiv(t, archiv, map[string]string{
		"stop_times.txt": "trip_id,arrival_time,departure_time,stop_headsign,stop_id,stop_sequence\n" +
			"t1,09:12:00,09:12:00,Ziel,A,0\n" +
			"t1,25:30:00,25:32:00,Ziel,B,1\n",
	})

	ziel := filepath.Join(basis, FahrplanDatei)
	zeilen, err := FahrplanSchreiben(archiv, ziel)
	if err != nil {
		t.Fatalf("FahrplanSchreiben: %v", err)
	}
	if zeilen != 2 {
		t.Errorf("zeilen = %d, want 2", zeilen)
	}

	got := leseFahrplan(t, ziel)
	if len(got) != 2 {
		t.Fatalf("gelesen = %d Zeilen, want 2", len(got))
	}
	if got[0] != (Fahrplanhalt{TripID: "t1", StopSequence: "0", StopID: "A", ArrivalTime: "09:12:00", DepartureTime: "09:12:00"}) {
		t.Errorf("erste Zeile falsch zugeordnet: %+v", got[0])
	}
	// Betriebstag != Kalendertag: "25:30:00" ist eine gueltige GTFS-Zeit und muss
	// unveraendert durchkommen. Wer sie hier als Uhrzeit parst, verliert genau die
	// Nachtfahrten (CLAUDE.md Regel 6).
	if got[1].ArrivalTime != "25:30:00" || got[1].DepartureTime != "25:32:00" {
		t.Errorf("Zeit jenseits 24 Uhr veraendert: %+v", got[1])
	}
}

func TestFahrplanSchreiben_MeldetFehlendeSpalte(t *testing.T) {
	basis := t.TempDir()
	archiv := filepath.Join(basis, "rv_free.zip")
	schreibeArchiv(t, archiv, map[string]string{
		"stop_times.txt": "trip_id,arrival_time,stop_id\nt1,09:12:00,A\n",
	})

	ziel := filepath.Join(basis, FahrplanDatei)
	if _, err := FahrplanSchreiben(archiv, ziel); err == nil {
		t.Fatal("fehlende Spalte blieb unbemerkt")
	}
	// Und sie hinterlaesst keine halbe Datei, die nachgelagert wie eine ganze
	// aussaehe.
	if _, err := os.Stat(ziel); !errors.Is(err, os.ErrNotExist) {
		t.Errorf("nach dem Fehler liegt eine Zieldatei: %v", err)
	}
	if _, err := os.Stat(ziel + ".unvollstaendig"); !errors.Is(err, os.ErrNotExist) {
		t.Errorf("temporaere Datei nicht aufgeraeumt: %v", err)
	}
}

func TestFahrplanSchreiben_MeldetFehlendesMitglied(t *testing.T) {
	basis := t.TempDir()
	archiv := filepath.Join(basis, "rv_free.zip")
	schreibeArchiv(t, archiv, map[string]string{"stops.txt": "stop_id,stop_name\nA,Anfang\n"})

	if _, err := FahrplanSchreiben(archiv, filepath.Join(basis, FahrplanDatei)); err == nil {
		t.Fatal("fehlendes Archivmitglied blieb unbemerkt")
	}
}

func TestFahrplanNachtragen_ErzeugtNurFehlendeUndFasstNichtsAn(t *testing.T) {
	basis := t.TempDir()
	feeds := []Feed{{Name: "rv"}, {Name: "fv"}}

	// Version 1: beide Archive da, nichts abgeleitet.
	schreibeArchiv(t, filepath.Join(basis, "v=2026-08-20", "rv_free.zip"), map[string]string{
		"stop_times.txt": "trip_id,stop_sequence,stop_id,arrival_time,departure_time\nt1,0,A,09:00:00,09:01:00\n",
	})
	schreibeArchiv(t, filepath.Join(basis, "v=2026-08-20", "fv_free.zip"), map[string]string{
		"stop_times.txt": "trip_id,stop_sequence,stop_id,arrival_time,departure_time\nt9,0,Z,10:00:00,10:01:00\n",
	})
	// Version 2: rv hat die Datei schon, mit einem Inhalt, den ein Neuschreiben
	// zerstoeren wuerde. fv hat gar kein Archiv -- das darf den Lauf nicht
	// abbrechen, sondern nur uebersprungen werden.
	vorhanden := filepath.Join(basis, "v=2026-08-13", "rv", FahrplanDatei)
	if err := os.MkdirAll(filepath.Dir(vorhanden), 0o755); err != nil {
		t.Fatalf("verzeichnis: %v", err)
	}
	if err := os.WriteFile(vorhanden, []byte("nicht anfassen"), 0o644); err != nil {
		t.Fatalf("schreiben: %v", err)
	}
	schreibeArchiv(t, filepath.Join(basis, "v=2026-08-13", "rv_free.zip"), map[string]string{
		"stop_times.txt": "trip_id,stop_sequence,stop_id,arrival_time,departure_time\nt2,0,B,08:00:00,08:01:00\n",
	})
	// Kein Versionsverzeichnis: muss ignoriert werden.
	if err := os.MkdirAll(filepath.Join(basis, "irgendwas"), 0o755); err != nil {
		t.Fatalf("verzeichnis: %v", err)
	}

	ergebnis, err := FahrplanNachtragen(basis, feeds)
	if err != nil {
		t.Fatalf("FahrplanNachtragen: %v", err)
	}

	if len(ergebnis) != 2 {
		t.Errorf("ergebnis = %v, want genau die beiden fehlenden aus v=2026-08-20", ergebnis)
	}
	for _, wo := range []string{"v=2026-08-20/rv", "v=2026-08-20/fv"} {
		if ergebnis[wo] != 1 {
			t.Errorf("ergebnis[%q] = %d, want 1", wo, ergebnis[wo])
		}
	}

	// Die vorhandene Datei ist unveraendert -- eine veroeffentlichte Version wird
	// nicht ueberschrieben (Regel 1).
	inhalt, err := os.ReadFile(vorhanden)
	if err != nil {
		t.Fatalf("lesen: %v", err)
	}
	if string(inhalt) != "nicht anfassen" {
		t.Errorf("vorhandene Datei wurde ueberschrieben: %q", inhalt)
	}

	// Zweiter Lauf ist ein No-op.
	zweiter, err := FahrplanNachtragen(basis, feeds)
	if err != nil {
		t.Fatalf("zweiter Lauf: %v", err)
	}
	if len(zweiter) != 0 {
		t.Errorf("zweiter Lauf hat %v nachgetragen, want nichts", zweiter)
	}
}
