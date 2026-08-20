// Package static laedt die statischen GTFS-Fahrplaene von gtfs.de und legt sie
// versioniert ab (BPULS-023, CLAUDE.md Regel 9).
//
// Zwei Eigenschaften der Quelle bestimmen den Entwurf, beide gemessen und in
// Open Questions Q6 festgehalten:
//
//  1. Es gibt nur `latest.zip`. Eine aeltere Veroeffentlichung ist **nicht**
//     nachladbar. Was hier nicht gespeichert wird, ist fuer immer weg -- deshalb
//     wandert das vollstaendige Archiv unveraendert ins Volume und nicht nur die
//     Handvoll Dateien, die heute gebraucht werden.
//  2. Die stop_id-Werte rotieren zwischen Veroeffentlichungen fast vollstaendig,
//     und der Echtzeit-Feed referenziert mehrere Namensraeume gleichzeitig. Eine
//     Version abzuloesen wuerde also Halte namenlos machen, die weiterhin
//     gemeldet werden. Versionen werden deshalb **nebeneinander** abgelegt und
//     nachgelagert vereinigt, nie ersetzt.
package static

import (
	"context"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"

	"archive/zip"
)

// ErrVersionVorhanden meldet, dass fuer diese Version bereits ein Verzeichnis
// existiert. Kein Fehlerfall im Betrieb: der woechentliche Task darf mehrfach
// laufen, ohne eine vorhandene Version anzufassen (Regel 1).
var ErrVersionVorhanden = errors.New("static: version bereits vorhanden")

// Feed ist ein herunterzuladendes Archiv.
type Feed struct {
	// Name wird zum Dateinamen und zum Unterverzeichnis, z. B. "rv".
	Name string
	URL  string
}

// StandardFeeds sind die beiden schienenspezifischen Free-Feeds. Beide fuehren
// in routes.txt durchgehend route_type = 2, eine weitere Verkehrsartfilterung
// ist nicht noetig (Bahnpuls_Datenquellen.md).
func StandardFeeds() []Feed {
	return []Feed{
		{Name: "rv", URL: "https://download.gtfs.de/germany/rv_free/latest.zip"},
		{Name: "fv", URL: "https://download.gtfs.de/germany/fv_free/latest.zip"},
	}
}

// StandardDateien sind die Mitglieder, die zusaetzlich zum Archiv entpackt
// werden, damit dbt sie ohne Umweg lesen kann. stop_times.txt fehlt bewusst:
// es ist um Groessenordnungen groesser und wird derzeit nicht gebraucht -- im
// Archiv liegt es trotzdem, falls sich das aendert.
//
// trips.txt ist dabei kein Vorrat: der Echtzeit-Feed liefert route_id **leer**
// (gemessen 2026-08-20 an 2.346 Fahrten im Scope), aber trip_id gefuellt. Der
// Weg zum Liniennamen fuehrt deshalb ueber trip_id -> trips.txt -> route_id ->
// routes.txt, nicht direkt ueber routes.txt.
//
// feed_info.txt taugt **nicht** zur Aenderungserkennung: feed_version steht dort
// buchstaeblich auf "latest-rv-free" bzw. "latest-fv-free". Ob sich ein Fahrplan
// geaendert hat, laesst sich nur an den Inhalten sehen (Q6).
func StandardDateien() []string {
	return []string{"stops.txt", "routes.txt", "trips.txt", "agency.txt", "feed_info.txt"}
}

// Version bildet den Versionsnamen eines Zeitpunkts.
func Version(t time.Time) string { return t.UTC().Format("2006-01-02") }

// Pfad liefert das Verzeichnis einer Version unterhalb von baseDir.
func Pfad(baseDir, version string) string {
	return filepath.Join(baseDir, "v="+version)
}

// Laden holt alle Feeds und legt sie unter baseDir/v=<version>/ ab.
//
// Die Version entsteht erst am Ende durch ein Rename aus einem temporaeren
// Verzeichnis: ein abgebrochener Lauf hinterlaesst damit keine halbe Version,
// die nachgelagert wie eine vollstaendige aussaehe.
func Laden(ctx context.Context, client *http.Client, baseDir, version string, feeds []Feed, dateien []string) (string, error) {
	ziel := Pfad(baseDir, version)
	if _, err := os.Stat(ziel); err == nil {
		return ziel, ErrVersionVorhanden
	} else if !errors.Is(err, os.ErrNotExist) {
		return "", fmt.Errorf("static: version pruefen: %w", err)
	}

	if err := os.MkdirAll(baseDir, 0o755); err != nil {
		return "", fmt.Errorf("static: basisverzeichnis anlegen: %w", err)
	}
	tmp, err := os.MkdirTemp(baseDir, ".unvollstaendig-*")
	if err != nil {
		return "", fmt.Errorf("static: temporaeres verzeichnis: %w", err)
	}
	erfolgreich := false
	defer func() {
		if !erfolgreich {
			os.RemoveAll(tmp)
		}
	}()

	for _, feed := range feeds {
		archiv := filepath.Join(tmp, feed.Name+"_free.zip")
		if err := herunterladen(ctx, client, feed.URL, archiv); err != nil {
			return "", fmt.Errorf("static: feed %s: %w", feed.Name, err)
		}
		if err := entpacken(archiv, filepath.Join(tmp, feed.Name), dateien); err != nil {
			return "", fmt.Errorf("static: feed %s entpacken: %w", feed.Name, err)
		}
	}

	if err := os.Rename(tmp, ziel); err != nil {
		return "", fmt.Errorf("static: version veroeffentlichen: %w", err)
	}
	erfolgreich = true
	return ziel, nil
}

func herunterladen(ctx context.Context, client *http.Client, url, ziel string) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return fmt.Errorf("anfrage bauen: %w", err)
	}
	resp, err := client.Do(req)
	if err != nil {
		return fmt.Errorf("abrufen: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("unerwarteter status %s", resp.Status)
	}

	datei, err := os.Create(ziel)
	if err != nil {
		return fmt.Errorf("zieldatei anlegen: %w", err)
	}
	defer datei.Close()
	if _, err := io.Copy(datei, resp.Body); err != nil {
		return fmt.Errorf("schreiben: %w", err)
	}
	return datei.Close()
}

// entpacken holt genau die genannten Mitglieder heraus. Es vergleicht den
// Basisnamen und schreibt selbst gebildete Pfade -- ein Archiveintrag wie
// "../../etc/passwd" kann so nichts ausserhalb von ziel anfassen.
func entpacken(archiv, ziel string, dateien []string) error {
	gewuenscht := make(map[string]bool, len(dateien))
	for _, name := range dateien {
		gewuenscht[name] = true
	}

	r, err := zip.OpenReader(archiv)
	if err != nil {
		return fmt.Errorf("archiv oeffnen: %w", err)
	}
	defer r.Close()

	if err := os.MkdirAll(ziel, 0o755); err != nil {
		return fmt.Errorf("verzeichnis anlegen: %w", err)
	}

	for _, eintrag := range r.File {
		name := filepath.Base(filepath.FromSlash(eintrag.Name))
		if !gewuenscht[name] || strings.HasSuffix(eintrag.Name, "/") {
			continue
		}
		if err := mitgliedSchreiben(eintrag, filepath.Join(ziel, name)); err != nil {
			return fmt.Errorf("mitglied %q: %w", name, err)
		}
	}
	return nil
}

func mitgliedSchreiben(eintrag *zip.File, ziel string) error {
	quelle, err := eintrag.Open()
	if err != nil {
		return fmt.Errorf("lesen: %w", err)
	}
	defer quelle.Close()

	datei, err := os.Create(ziel)
	if err != nil {
		return fmt.Errorf("anlegen: %w", err)
	}
	defer datei.Close()
	if _, err := io.Copy(datei, quelle); err != nil {
		return fmt.Errorf("schreiben: %w", err)
	}
	return datei.Close()
}
