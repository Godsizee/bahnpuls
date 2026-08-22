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

// HalteDatei ist der Name der abgeleiteten Halteliste je Feed und Version.
//
// Bewusst `stops.parquet` und nicht `stops.txt`: die dbt-Quelle fuer die
// Bahn-Halte liest per Glob `v=*/*/stops.txt` und wuerde eine gleichnamige
// Datei mit einlesen. Genau das darf nicht passieren -- die Namensraeume der
// beiden Feeds kollidieren zahlenmaessig, eine Vereinigung ueber beide wuerde
// Halte im Zielgebiet mit Bushaltestellen anderswo verschmelzen.
const HalteDatei = "stops.parquet"

// halteQuelle ist das Archivmitglied, aus dem sie entsteht.
const halteQuelle = "stops.txt"

// Halt ist ein Eintrag aus stops.txt, reduziert auf das, was zur Unterscheidung
// gebraucht wird.
//
// **Warum es diese Datei gibt (BPULS-070):** der Echtzeit-Feed fuehrt seit dem
// 2026-08-22 auch Nahverkehr aus dem ganzen Bundesgebiet. Dessen stop_id-Werte
// stammen aus einem eigenen Nummernkreis, kollidieren aber zahlenmaessig mit dem
// des Bahnfahrplans -- eine Hannoveraner Bushaltestelle traegt zufaellig die
// Nummer eines Bahnhofs im Zielgebiet, und der Scope-Filter des Collectors haelt
// sie fuer einen Treffer. Gemessen an einem Nachmittag: von 3.842 unbekannten
// IDs loesen **116** im Bahnfahrplan auf und **3.756** im Nahverkehrsfeed.
//
// Aus einer ID allein ist das nicht zu entscheiden. Erst der Vergleich ueber die
// **ganze Fahrt** trennt beides: gehen mehr ihrer Halte im Nahverkehrsfeed auf
// als im Bahnfahrplan, ist es keine Bahnfahrt. Diese Datei ist die dafuer noetige
// Negativliste.
type Halt struct {
	StopID   string `parquet:"stop_id"`
	StopName string `parquet:"stop_name"`
}

// halteSpalten sind die Kopfzeilen, die gebraucht werden -- in der Reihenfolge
// der Struct-Felder.
var halteSpalten = []string{"stop_id", "stop_name"}

// HalteSchreiben liest stops.txt aus dem Archiv und legt es als Parquet+ZSTD
// unter ziel ab. Gleiches Vorgehen wie FahrplanSchreiben: Stapel statt alles auf
// einmal, und erst am Ende umbenennen.
//
// Die Stapelgroesse ist hier nicht kosmetisch: die Halteliste des
// Nahverkehrsfeeds hat rund 684.000 Zeilen, und der Loader laeuft im
// Collector-Container (Regel 3).
func HalteSchreiben(archiv, ziel string) (zeilen int, err error) {
	r, err := zip.OpenReader(archiv)
	if err != nil {
		return 0, fmt.Errorf("archiv oeffnen: %w", err)
	}
	defer r.Close()

	var eintrag *zip.File
	for _, f := range r.File {
		if filepath.Base(f.Name) == halteQuelle {
			eintrag = f
			break
		}
	}
	if eintrag == nil {
		return 0, fmt.Errorf("%s nicht im archiv", halteQuelle)
	}

	quelle, err := eintrag.Open()
	if err != nil {
		return 0, fmt.Errorf("%s oeffnen: %w", halteQuelle, err)
	}
	defer quelle.Close()

	tmp := ziel + ".unvollstaendig"
	if err := os.MkdirAll(filepath.Dir(ziel), 0o755); err != nil {
		return 0, fmt.Errorf("zielverzeichnis anlegen: %w", err)
	}
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

	zeilen, err = halteUmschreiben(quelle, datei)
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

func halteUmschreiben(quelle io.Reader, ziel io.Writer) (int, error) {
	leser := csv.NewReader(quelle)
	leser.ReuseRecord = true
	leser.FieldsPerRecord = -1

	kopf, err := leser.Read()
	if err != nil {
		return 0, fmt.Errorf("kopfzeile lesen: %w", err)
	}
	// Ueber den Namen suchen, nicht ueber die Position: stops.txt fuehrt je nach
	// Feed unterschiedlich viele Spalten in unterschiedlicher Reihenfolge.
	index := make([]int, len(halteSpalten))
	for i, name := range halteSpalten {
		index[i] = -1
		for j, vorhanden := range kopf {
			if vorhanden == name {
				index[i] = j
				break
			}
		}
		if index[i] < 0 {
			return 0, fmt.Errorf("spalte %q fehlt in %s", name, halteQuelle)
		}
	}

	schreiber := parquet.NewGenericWriter[Halt](ziel, parquet.Compression(&parquet.Zstd))
	stapel := make([]Halt, 0, stapelGroesse)
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
		hoechster := index[0]
		for _, i := range index {
			if i > hoechster {
				hoechster = i
			}
		}
		if len(satz) <= hoechster {
			return 0, fmt.Errorf("zeile %d hat nur %d felder", gesamt+2, len(satz))
		}
		stapel = append(stapel, Halt{
			StopID:   satz[index[0]],
			StopName: satz[index[1]],
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
