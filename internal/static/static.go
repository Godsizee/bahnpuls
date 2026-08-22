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

// ErrFahrplanUnvollstaendig meldet, dass die Version abgelegt wurde, aber ohne
// die abgeleiteten Soll-Halte. Die Version ist damit **gueltig und vollstaendig
// gesichert** -- das Archiv liegt unveraendert da --, nur die Auswertung der
// Ausfaelle fehlt, bis `-fahrplan-nachtragen` laeuft.
var ErrFahrplanUnvollstaendig = errors.New("static: soll-halte nicht erzeugt")

// Feed ist ein herunterzuladendes Archiv.
type Feed struct {
	// Name wird zum Dateinamen und zum Unterverzeichnis, z. B. "rv".
	Name string
	URL  string
	// NurHalte laesst von diesem Feed ausschliesslich die Halteliste uebrig --
	// weder das Archiv noch die uebrigen Mitglieder werden behalten. Siehe
	// NahverkehrFeed.
	NurHalte bool
}

// StandardFeeds sind die beiden schienenspezifischen Free-Feeds plus die
// Halteliste des Nahverkehrs. Die ersten beiden fuehren in routes.txt
// durchgehend route_type = 2, eine weitere Verkehrsartfilterung ist dort nicht
// noetig (Bahnpuls_Datenquellen.md).
func StandardFeeds() []Feed {
	return []Feed{
		{Name: "rv", URL: "https://download.gtfs.de/germany/rv_free/latest.zip"},
		{Name: "fv", URL: "https://download.gtfs.de/germany/fv_free/latest.zip"},
		NahverkehrFeed(),
	}
}

// NahverkehrFeed liefert den Nahverkehrs-Feed, von dem **nur** die Halteliste
// behalten wird (BPULS-070).
//
// Er ist nicht Gegenstand des Projekts, sondern Unterscheidungsmerkmal: der
// Echtzeit-Feed fuehrt seit dem 2026-08-22 Nahverkehr aus dem ganzen
// Bundesgebiet, dessen stop_id-Nummernkreis mit dem des Bahnfahrplans
// kollidiert. Ohne diese Liste ist eine Hannoveraner Bushaltestelle von einem
// Bahnhof im Zielgebiet nicht zu unterscheiden.
//
// **Warum das Archiv hier nicht mitgesichert wird**, anders als bei rv und fv:
// es sind 264 MB je Veroeffentlichung, also rund 13,7 GB im Jahr gegen 6,9 GB
// fuer die gesamte eigene Historie. Die Begruendung der Archivregel greift hier
// nicht -- unwiederbringlich ist der **Echtzeit**-Datensatz, und was von diesem
// Feed gebraucht wird, sind zwei Spalten. Wird die Halteliste einmal gebraucht
// und fehlt, kostet das die Trennschaerfe einer Woche, nicht Historie.
func NahverkehrFeed() Feed {
	return Feed{
		Name:     "nv",
		URL:      "https://download.gtfs.de/germany/nv_free/latest.zip",
		NurHalte: true,
	}
}

// StandardDateien sind die Mitglieder, die zusaetzlich zum Archiv unveraendert
// entpackt werden, damit dbt sie ohne Umweg lesen kann.
//
// stop_times.txt steht bewusst **nicht** in dieser Liste, obwohl es gebraucht
// wird: 85,35 MB je Version als CSV waeren 4,4 GB im Jahr. Es wird stattdessen
// auf fuenf Spalten reduziert nach Parquet+ZSTD umgeschrieben (7,04 MB je
// Version), siehe FahrplanSchreiben in fahrplan.go.
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
	// MkdirTemp legt mit 0700 an, und os.Rename behaelt das bei -- die fertige
	// Version waere damit nur fuer den schreibenden Nutzer lesbar. Das faellt hier
	// nicht auf, sondern erst nebenan: der Collector schreibt als root, das
	// Dashboard liest als node und sah "keine Dateien gefunden", obwohl die Dateien
	// da waren. Wer schreiben darf, ist eine andere Frage als wer lesen darf.
	if err := os.Chmod(tmp, 0o755); err != nil {
		os.RemoveAll(tmp)
		return "", fmt.Errorf("static: rechte am temporaeren verzeichnis: %w", err)
	}
	erfolgreich := false
	defer func() {
		if !erfolgreich {
			os.RemoveAll(tmp)
		}
	}()

	var fahrplanFehler []string
	for _, feed := range feeds {
		archiv := filepath.Join(tmp, feed.Name+"_free.zip")
		if err := herunterladen(ctx, client, feed.URL, archiv); err != nil {
			return "", fmt.Errorf("static: feed %s: %w", feed.Name, err)
		}
		if feed.NurHalte {
			// Von diesem Feed bleibt genau die Halteliste uebrig, siehe
			// NahverkehrFeed. Das Archiv wird sofort wieder geloescht -- ein
			// Aufheben kostete das Doppelte der gesamten eigenen Historie.
			//
			// **Ebenso wenig fatal wie die Soll-Halte**: schlaegt es fehl, wird die
			// Version trotzdem veroeffentlicht. Die Bahn-Feeds sind davon
			// unberuehrt, und ohne die Liste faellt lediglich die Trennung von
			// Fremdverkehr aus -- die dbt-Seite meldet das als eigenen Befund,
			// statt stillschweigend alles durchzulassen.
			if _, err := HalteSchreiben(archiv, filepath.Join(tmp, feed.Name, HalteDatei)); err != nil {
				fahrplanFehler = append(fahrplanFehler, fmt.Sprintf("%s: %v", feed.Name, err))
			}
			if err := os.Remove(archiv); err != nil {
				return "", fmt.Errorf("static: feed %s archiv verwerfen: %w", feed.Name, err)
			}
			continue
		}
		if err := entpacken(archiv, filepath.Join(tmp, feed.Name), dateien); err != nil {
			return "", fmt.Errorf("static: feed %s entpacken: %w", feed.Name, err)
		}
		// stop_times.txt wird nicht entpackt, sondern umgeschrieben: 85 MB CSV je
		// Version gegen 7 MB Parquet. Ohne diese Datei bleibt ein vollstaendig
		// ausgefallener Zug unsichtbar -- er kommt ohne stop_time_update, es gibt
		// also keinen Halt, an dem der Ausfall haengen koennte (BPULS-032).
		//
		// **Bewusst nicht fatal.** Scheitert das Umschreiben -- geaendertes Format,
		// fehlende Spalte, umbenanntes Mitglied --, wird die Version trotzdem
		// veroeffentlicht. Der Grund steht oben im Paketkommentar: es gibt nur
		// latest.zip, eine aeltere Veroeffentlichung ist nicht nachladbar. Ein
		// harter Abbruch opferte das unwiederbringliche Archiv fuer eine Datei, die
		// daraus jederzeit wieder herstellbar ist (`-fahrplan-nachtragen`). Der
		// Fehler wird gemeldet und ist am fehlenden stop_times.parquet erkennbar.
		if _, err := FahrplanSchreiben(archiv, filepath.Join(tmp, feed.Name, FahrplanDatei)); err != nil {
			fahrplanFehler = append(fahrplanFehler, fmt.Sprintf("%s: %v", feed.Name, err))
		}
	}

	if err := os.Rename(tmp, ziel); err != nil {
		return "", fmt.Errorf("static: version veroeffentlichen: %w", err)
	}
	erfolgreich = true
	if len(fahrplanFehler) > 0 {
		return ziel, fmt.Errorf("%w: %s", ErrFahrplanUnvollstaendig, strings.Join(fahrplanFehler, "; "))
	}
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
