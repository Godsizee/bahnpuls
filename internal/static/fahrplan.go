package static

import (
	"archive/zip"
	"encoding/csv"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"

	"github.com/parquet-go/parquet-go"
)

// FahrplanDatei ist der Name der abgeleiteten Datei je Feed und Version.
const FahrplanDatei = "stop_times.parquet"

// fahrplanQuelle ist das Archivmitglied, aus dem sie entsteht.
const fahrplanQuelle = "stop_times.txt"

// stapelGroesse begrenzt, wie viele Zeilen gleichzeitig im Speicher stehen.
// Der Loader laeuft als Scheduled Task **im Collector-Container**, dessen RSS bei
// 250-290 MB liegt; 1,59 Mio. Zeilen auf einmal zu halten waere rund ein Drittel
// davon obendrauf, fuer nichts. Der Collector hat Vorrang (CLAUDE.md Regel 3).
const stapelGroesse = 50_000

// Fahrplanhalt ist ein Soll-Halt aus stop_times.txt.
//
// **Warum ueberhaupt:** Ein vollstaendig ausgefallener Zug erscheint im
// GTFS-RT-Feed als Meldung ueber die ganze Fahrt, **ohne** stop_time_update --
// es gibt keinen Halt, an dem der Ausfall haengen koennte. Gemessen am
// Produktionsstand vom 2026-08-21 (drei Betriebstage, 52.263 Fahrten) erreicht
// dadurch **kein einziger** Ausfall die Kennzahlen, waehrend 21.823 ausgelassene
// Halte ankommen. Erst die Soll-Halte von hier machen aus so einer Meldung
// wieder Halte, denen sich der Ausfall zuordnen laesst (BPULS-032, A5).
//
// **Warum nur fuenf Spalten:** stop_times.txt fuehrt acht. Die uebrigen
// (stop_headsign, pickup_type, drop_off_type) braucht keine Auswertung. Das
// vollstaendige Archiv liegt unveraendert daneben -- was hier fehlt, ist nicht
// verloren, sondern nur nicht vorentpackt (Regel 1 bleibt gewahrt).
//
// **Warum Parquet+ZSTD und nicht die CSV:** gemessen an der Veroeffentlichung
// vom 2026-08-21 sind es 85,35 MB entpackte CSV je Version gegen **7,04 MB**
// als Parquet -- 4,4 GB gegen 366 MB im Jahr. Das Format ist ausserdem das
// Hausformat der Rohdaten (ADR-004), kein zweites Bulk-Format.
//
// **Warum die Zeiten als Text bleiben:** GTFS schreibt Zeiten wie "25:30:00" --
// Sekunden seit Betriebstagsbeginn, keine Uhrzeit. Sie hier zu parsen hiesse,
// genau den Fehler einzubauen, vor dem CLAUDE.md Regel 6 warnt. Die Umrechnung
// gehoert nach dbt.
type Fahrplanhalt struct {
	TripID        string `parquet:"trip_id"`
	StopSequence  string `parquet:"stop_sequence"`
	StopID        string `parquet:"stop_id"`
	ArrivalTime   string `parquet:"arrival_time"`
	DepartureTime string `parquet:"departure_time"`
}

// fahrplanSpalten sind die Kopfzeilen, die gebraucht werden -- in der Reihenfolge
// der Struct-Felder.
var fahrplanSpalten = []string{"trip_id", "stop_sequence", "stop_id", "arrival_time", "departure_time"}

// FahrplanSchreiben liest stop_times.txt aus dem Archiv und legt es als
// Parquet+ZSTD unter ziel ab. Geschrieben wird in Stapeln, damit der
// Speicherbedarf nicht mit der Fahrplangroesse waechst.
//
// Geschrieben wird zuerst nach ziel+".unvollstaendig" und erst am Ende
// umbenannt: dieselbe Regel wie bei der Version selbst -- ein Abbruch
// hinterlaesst keine halbe Datei, die nachgelagert wie eine ganze aussaehe.
func FahrplanSchreiben(archiv, ziel string) (zeilen int, err error) {
	r, err := zip.OpenReader(archiv)
	if err != nil {
		return 0, fmt.Errorf("archiv oeffnen: %w", err)
	}
	defer r.Close()

	var eintrag *zip.File
	for _, f := range r.File {
		if filepath.Base(f.Name) == fahrplanQuelle {
			eintrag = f
			break
		}
	}
	if eintrag == nil {
		return 0, fmt.Errorf("%s nicht im archiv", fahrplanQuelle)
	}

	quelle, err := eintrag.Open()
	if err != nil {
		return 0, fmt.Errorf("%s oeffnen: %w", fahrplanQuelle, err)
	}
	defer quelle.Close()

	tmp := ziel + ".unvollstaendig"
	datei, err := os.Create(tmp)
	if err != nil {
		return 0, fmt.Errorf("zieldatei anlegen: %w", err)
	}
	fertig := false
	defer func() {
		datei.Close()
		if !fertig {
			os.Remove(tmp)
		}
	}()

	zeilen, err = fahrplanUmschreiben(quelle, datei)
	if err != nil {
		return 0, err
	}
	if err := datei.Close(); err != nil {
		return 0, fmt.Errorf("zieldatei schliessen: %w", err)
	}
	// Lesbar auch fuer den Nachbarcontainer, der als anderer Nutzer liest.
	if err := os.Chmod(tmp, 0o644); err != nil {
		return 0, fmt.Errorf("rechte setzen: %w", err)
	}
	if err := os.Rename(tmp, ziel); err != nil {
		return 0, fmt.Errorf("veroeffentlichen: %w", err)
	}
	fertig = true
	return zeilen, nil
}

func fahrplanUmschreiben(quelle io.Reader, ziel io.Writer) (int, error) {
	leser := csv.NewReader(quelle)
	leser.ReuseRecord = true
	leser.FieldsPerRecord = -1 // Zeilen mit abweichender Feldzahl selbst behandeln

	kopf, err := leser.Read()
	if err != nil {
		return 0, fmt.Errorf("kopfzeile lesen: %w", err)
	}
	// Spalten ueber den Namen suchen, nicht ueber die Position: die Reihenfolge
	// in stop_times.txt ist nicht zugesichert, und eine stille Verschiebung
	// vertauschte hier Haltestelle und Uhrzeit.
	index := make([]int, len(fahrplanSpalten))
	for i, name := range fahrplanSpalten {
		index[i] = -1
		for j, vorhanden := range kopf {
			if vorhanden == name {
				index[i] = j
				break
			}
		}
		if index[i] < 0 {
			return 0, fmt.Errorf("spalte %q fehlt in %s", name, fahrplanQuelle)
		}
	}

	schreiber := parquet.NewGenericWriter[Fahrplanhalt](ziel, parquet.Compression(&parquet.Zstd))
	stapel := make([]Fahrplanhalt, 0, stapelGroesse)
	gesamt := 0

	schreibeStapel := func() error {
		if len(stapel) == 0 {
			return nil
		}
		if _, err := schreiber.Write(stapel); err != nil {
			return fmt.Errorf("parquet schreiben: %w", err)
		}
		stapel = stapel[:0]
		return nil
	}

	for {
		satz, err := leser.Read()
		if errors.Is(err, io.EOF) {
			break
		}
		if err != nil {
			return 0, fmt.Errorf("zeile %d lesen: %w", gesamt+2, err)
		}
		if len(satz) <= index[len(index)-1] {
			return 0, fmt.Errorf("zeile %d hat nur %d felder", gesamt+2, len(satz))
		}
		stapel = append(stapel, Fahrplanhalt{
			TripID:        satz[index[0]],
			StopSequence:  satz[index[1]],
			StopID:        satz[index[2]],
			ArrivalTime:   satz[index[3]],
			DepartureTime: satz[index[4]],
		})
		gesamt++
		if len(stapel) == stapelGroesse {
			if err := schreibeStapel(); err != nil {
				return 0, err
			}
		}
	}
	if err := schreibeStapel(); err != nil {
		return 0, err
	}
	if err := schreiber.Close(); err != nil {
		return 0, fmt.Errorf("parquet abschliessen: %w", err)
	}
	return gesamt, nil
}

// FahrplanNachtragen erzeugt die Parquet-Fassung fuer Versionen, die vor der
// Einfuehrung dieser Datei abgelegt wurden. Es liest ausschliesslich aus dem
// mitgespeicherten Archiv und **legt nur neue Dateien an** -- eine vorhandene
// wird nie angefasst.
//
// Das steht bewusst neben Laden und nicht darin: eine veroeffentlichte Version
// wird sonst nie mehr beruehrt (Regel 1). Hier ist die Ausnahme eng gefasst und
// verlustfrei -- die abgeleitete Datei war aus dem danebenliegenden Archiv
// jederzeit herstellbar, es geht keine Information verloren, und ohne den
// Nachtrag bliebe die Ausfall-Luecke bis zur naechsten woechentlichen Ladung
// offen.
func FahrplanNachtragen(baseDir string, feeds []Feed) (map[string]int, error) {
	eintraege, err := os.ReadDir(baseDir)
	if err != nil {
		return nil, fmt.Errorf("static: verzeichnis lesen: %w", err)
	}

	ergebnis := make(map[string]int)
	for _, e := range eintraege {
		if !e.IsDir() || !hatVersionsPraefix(e.Name()) {
			continue
		}
		for _, feed := range feeds {
			verzeichnis := filepath.Join(baseDir, e.Name(), feed.Name)
			ziel := filepath.Join(verzeichnis, FahrplanDatei)
			if _, err := os.Stat(ziel); err == nil {
				continue // schon da, nicht anfassen
			} else if !errors.Is(err, os.ErrNotExist) {
				return nil, fmt.Errorf("static: %s pruefen: %w", ziel, err)
			}
			archiv := filepath.Join(baseDir, e.Name(), feed.Name+"_free.zip")
			if _, err := os.Stat(archiv); err != nil {
				// Ohne Archiv laesst sich nichts nachtragen. Kein Abbruch: eine
				// aeltere Version kann aus anderen Gruenden unvollstaendig sein,
				// und der Rest soll trotzdem nachgezogen werden.
				continue
			}
			if err := os.MkdirAll(verzeichnis, 0o755); err != nil {
				return nil, fmt.Errorf("static: %s anlegen: %w", verzeichnis, err)
			}
			zeilen, err := FahrplanSchreiben(archiv, ziel)
			if err != nil {
				return nil, fmt.Errorf("static: %s nachtragen: %w", ziel, err)
			}
			ergebnis[e.Name()+"/"+feed.Name] = zeilen
		}
	}
	return ergebnis, nil
}

func hatVersionsPraefix(name string) bool {
	return len(name) > 2 && name[:2] == "v="
}
