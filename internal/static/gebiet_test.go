package static

import (
	"os"
	"path/filepath"
	"testing"

	"bahnpuls/internal/scope"
)

func schreibeDatei(t *testing.T, pfad, inhalt string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(pfad), 0o755); err != nil {
		t.Fatalf("verzeichnis: %v", err)
	}
	if err := os.WriteFile(pfad, []byte(inhalt), 0o644); err != nil {
		t.Fatalf("schreiben: %v", err)
	}
}

const vorlageCSV = `stop_id,stop_name,stop_lat,stop_lon
8000244,Mannheim Hbf,49.4794,8.4689
`

func TestNeuesteVersion(t *testing.T) {
	base := t.TempDir()
	for _, name := range []string{"v=2026-08-13", "v=2026-08-22", "v=2026-08-06", "sonstiges"} {
		if err := os.MkdirAll(filepath.Join(base, name), 0o755); err != nil {
			t.Fatalf("mkdir: %v", err)
		}
	}
	ziel, err := NeuesteVersion(base)
	if err != nil {
		t.Fatalf("NeuesteVersion: %v", err)
	}
	if filepath.Base(ziel) != "v=2026-08-22" {
		t.Errorf("ziel = %s, want v=2026-08-22", ziel)
	}
}

func TestNeuesteVersionOhneVersion(t *testing.T) {
	if _, err := NeuesteVersion(t.TempDir()); err == nil {
		t.Fatal("erwartete einen Fehler, bekam keinen")
	}
}

func TestGebietslisteNachtragen(t *testing.T) {
	base := t.TempDir()
	version := Pfad(base, "2026-08-22")
	schreibeDatei(t, filepath.Join(version, "rv", halteQuelle),
		"stop_id,stop_name,stop_lat,stop_lon\n100001,Mannheim Hbf,49.4794,8.4689\n")
	schreibeDatei(t, filepath.Join(version, "fv", halteQuelle),
		"stop_id,stop_name,stop_lat,stop_lon\n200001,Mannheim Hbf,49.4795,8.4690\n")
	// Der Nahverkehrsfeed darf das Gebiet nicht vergroessern: seine Halteliste
	// liegt als Parquet und traegt hier gar keine stops.txt -- ein Zugriff
	// darauf wuerde den Lauf abbrechen lassen, und genau das prueft dieser Fall.
	schreibeDatei(t, filepath.Join(version, "nv", "belegt.txt"), "x\n")

	vorlage := filepath.Join(base, "vorlage.csv")
	schreibeDatei(t, vorlage, vorlageCSV)
	liste := GebietslistePfad(base)

	bericht, herkunft, err := GebietslisteNachtragen(version, liste, vorlage, StandardFeeds())
	if err != nil {
		t.Fatalf("GebietslisteNachtragen: %v", err)
	}
	if herkunft != vorlage {
		t.Errorf("herkunft = %s, want %s", herkunft, vorlage)
	}
	if bericht.Neu != 2 {
		t.Errorf("neu = %d, want 2", bericht.Neu)
	}

	filter, err := scope.LoadCSV(liste)
	if err != nil {
		t.Fatalf("LoadCSV: %v", err)
	}
	if filter.Len() != 3 {
		t.Errorf("filter.Len() = %d, want 3", filter.Len())
	}

	// Zweiter Lauf: der Bestand kommt jetzt vom Volume, nicht mehr aus der
	// Vorlage, und es kommt nichts hinzu.
	bericht, herkunft, err = GebietslisteNachtragen(version, liste, vorlage, StandardFeeds())
	if err != nil {
		t.Fatalf("GebietslisteNachtragen (2): %v", err)
	}
	if herkunft != liste {
		t.Errorf("herkunft = %s, want %s", herkunft, liste)
	}
	if bericht.Neu != 0 || bericht.Bestand != 3 {
		t.Errorf("neu/bestand = %d/%d, want 0/3", bericht.Neu, bericht.Bestand)
	}
}

func TestGebietslisteNachtragenOhneStopsTxt(t *testing.T) {
	base := t.TempDir()
	version := Pfad(base, "2026-08-22")
	if err := os.MkdirAll(version, 0o755); err != nil {
		t.Fatalf("mkdir: %v", err)
	}
	vorlage := filepath.Join(base, "vorlage.csv")
	schreibeDatei(t, vorlage, vorlageCSV)

	if _, _, err := GebietslisteNachtragen(version, GebietslistePfad(base), vorlage, StandardFeeds()); err == nil {
		t.Fatal("erwartete einen Fehler, bekam keinen")
	}
	// Die alte Liste darf dabei nicht angetastet worden sein.
	if _, err := os.Stat(GebietslistePfad(base)); !os.IsNotExist(err) {
		t.Errorf("es wurde eine Liste geschrieben, obwohl die Quelle fehlte")
	}
}
