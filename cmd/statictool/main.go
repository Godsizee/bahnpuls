// Command statictool laedt die statischen GTFS-Fahrplaene und legt sie
// versioniert auf dem Volume ab (BPULS-023).
//
// Laeuft als woechentlicher Coolify Scheduled Task, nicht im Collector: der
// Collector hat Vorrang und darf nicht fuer einen Download blockieren
// (CLAUDE.md Regel 3). Ein Lauf ohne neue Version ist ein No-op -- der Task
// darf beliebig oft laufen, ohne Vorhandenes anzufassen.
package main

import (
	"context"
	"errors"
	"flag"
	"log"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"syscall"
	"time"

	_ "time/tzdata"

	"bahnpuls/internal/static"
)

func main() {
	baseDir := flag.String("static-dir", envOr("BAHNPULS_STATIC_DIR", "data/static"), "Zielverzeichnis fuer die versionierten Fahrplaene")
	version := flag.String("version", "", "Versionsname, Standard: heutiges UTC-Datum")
	timeout := flag.Duration("timeout", 10*time.Minute, "Gesamtzeit fuer alle Downloads")
	nachtragen := flag.Bool("fahrplan-nachtragen", false,
		"Nur die Soll-Halte fuer bereits abgelegte Versionen aus deren Archiv erzeugen, nichts laden")
	gebietsliste := flag.String("gebietsliste", envOr("BAHNPULS_SCOPE_CONFIG", ""),
		"Ziel der abgeleiteten Gebietsliste, Standard: <static-dir>/"+static.GebietslisteDatei)
	vorlage := flag.String("gebietsliste-vorlage", "config/scope_stops.csv",
		"Bestand fuer den ersten Lauf, solange auf dem Volume noch keine Liste liegt")
	nurGebietsliste := flag.Bool("gebietsliste-nachtragen", false,
		"Nur die Gebietsliste aus der juengsten abgelegten Version ableiten, nichts laden")
	pruefen := flag.Bool("gebietsliste-pruefen", false,
		"Nur zaehlen, wie viele IDs der Gebietsliste die juengste Version kennt; Exit 1 unter -mindest-ids")
	mindestIDs := flag.Int("mindest-ids", 500,
		"Untergrenze fuer -gebietsliste-pruefen; das Gebiet hat rund 1.700 Stationen")
	flag.Parse()

	log.SetFlags(log.LstdFlags | log.Lmicroseconds)

	if *version == "" {
		*version = static.Version(time.Now())
	}
	if *gebietsliste == "" {
		*gebietsliste = static.GebietslistePfad(*baseDir)
	}

	if *pruefen {
		// Nur messen, nichts anfassen -- gedacht fuer die stuendliche fachliche
		// Pruefung (BPULS-026). Sie lief bisher an genau diesem Punkt vorbei.
		ziel, err := static.NeuesteVersion(*baseDir)
		if err != nil {
			log.Fatalf("statictool: %v", err)
		}
		treffer, gesamt, err := static.GebietslisteDeckung(ziel, *gebietsliste, static.StandardFeeds())
		if err != nil {
			log.Fatalf("statictool: %v", err)
		}
		log.Printf("statictool: gebietsliste -- %d von %d IDs stehen in %s",
			treffer, gesamt, filepath.Base(ziel))
		if treffer < *mindestIDs {
			log.Printf("statictool: BEFUND -- unter %d IDs. Die Liste zeigt auf einen "+
				"abgeloesten Nummernkreis; der Collector sammelt dann Nahverkehr statt Bahn "+
				"(BPULS-073). Behebung: 'statictool -gebietsliste-nachtragen'", *mindestIDs)
			os.Exit(1)
		}
		return
	}

	if *nurGebietsliste {
		// Getrennter Weg aus demselben Grund wie -fahrplan-nachtragen: eine
		// bereits abgelegte Version wird nicht neu geladen, nur ausgewertet.
		// Gebraucht, wenn die Ableitung beim Laden schiefging oder die Liste
		// erstmals auf das Volume soll.
		ziel, err := static.NeuesteVersion(*baseDir)
		if err != nil {
			log.Fatalf("statictool: %v", err)
		}
		if err := gebietslisteSchreiben(ziel, *gebietsliste, *vorlage); err != nil {
			log.Fatalf("statictool: %v", err)
		}
		return
	}

	if *nachtragen {
		// Erzeugt ausschliesslich fehlende abgeleitete Dateien aus dem
		// mitgespeicherten Archiv. Ohne diesen Weg bliebe die Ausfall-Luecke bis
		// zur naechsten woechentlichen Ladung offen, obwohl alles Noetige laengst
		// auf dem Volume liegt.
		ergebnis, err := static.FahrplanNachtragen(*baseDir, static.StandardFeeds())
		if err != nil {
			log.Fatalf("statictool: %v", err)
		}
		if len(ergebnis) == 0 {
			log.Printf("statictool: nichts nachzutragen, alle Versionen haben ihre Soll-Halte")
			return
		}
		for wo, zeilen := range ergebnis {
			log.Printf("statictool: %s -- %d Soll-Halte geschrieben", wo, zeilen)
		}
		return
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	ctx, abbrechen := context.WithTimeout(ctx, *timeout)
	defer abbrechen()

	client := &http.Client{Timeout: *timeout}
	feeds := static.StandardFeeds()

	log.Printf("statictool: lade version %s nach %s", *version, *baseDir)
	ziel, err := static.Laden(ctx, client, *baseDir, *version, feeds, static.StandardDateien())
	geladen := true
	switch {
	case errors.Is(err, static.ErrVersionVorhanden):
		// Kein Fehler: die Version steht schon, und eine vorhandene Version wird
		// nie ueberschrieben (Regel 1). Exit 0, damit der Task nicht rot wird.
		//
		// Die Gebietsliste wird trotzdem abgeleitet. Sie ist keine Datei *in* der
		// Version, sondern eine Ableitung *aus* ihr, und das Nachtragen ist
		// idempotent -- ein zweiter Lauf bringt null neue IDs. Damit heilt ein
		// taeglicher Task eine Ableitung, die beim Laden fehlgeschlagen ist.
		// Sonst bliebe der Collector auf einer Liste stehen, die bis zur
		// naechsten Veroeffentlichung niemand nachzieht, und genau diese Stille
		// war der Schaden vom 22.08. (BPULS-073).
		geladen = false
		log.Printf("statictool: version %s existiert bereits, nur die Gebietsliste wird nachgezogen", *version)
	case errors.Is(err, static.ErrFahrplanUnvollstaendig):
		// Die Version ist abgelegt und das Archiv unveraendert gesichert -- nur die
		// Soll-Halte fehlen. Kein Fatalfehler: ein roter Task suggerierte, es sei
		// nichts gespeichert worden, und genau das Gegenteil ist der Fall. Aber
		// laut genug, dass es auffaellt.
		log.Printf("statictool: WARNUNG -- %v", err)
		log.Printf("statictool: version %s ist gesichert, die Ausfall-Auswertung fehlt ihr aber. "+
			"Ursache pruefen, dann 'statictool -fahrplan-nachtragen' laufen lassen", *version)
	case err != nil:
		log.Fatalf("statictool: %v", err)
	}

	if geladen {
		log.Printf("statictool: version abgelegt unter %s", ziel)
	}

	// Ohne diesen Schritt ist die Version zwar da, der Collector sammelt aber
	// weiter gegen die IDs der vorigen -- und die sind nach einer
	// Veroeffentlichung fast vollstaendig weg (BPULS-073). Der Fehler faellt
	// nicht auf, weil die Liste dann Nahverkehr trifft statt nichts.
	if err := gebietslisteSchreiben(ziel, *gebietsliste, *vorlage); err != nil {
		// Nicht fatal, aus demselben Grund wie bei den Soll-Halten: die Version
		// ist gesichert, und die Ableitung ist daraus jederzeit nachholbar
		// (`-gebietsliste-nachtragen`). Ein harter Abbruch verschleierte, dass
		// das Archiv unversehrt liegt.
		log.Printf("statictool: WARNUNG -- %v", err)
		log.Printf("statictool: der Collector sammelt weiter gegen die alten IDs. " +
			"Ursache pruefen, dann 'statictool -gebietsliste-nachtragen' laufen lassen")
	}
}

// gebietslisteSchreiben leitet die Gebietsliste aus einer abgelegten Version ab
// und meldet, was sich geaendert hat.
func gebietslisteSchreiben(versionsPfad, listePfad, vorlagePfad string) error {
	bericht, herkunft, err := static.GebietslisteNachtragen(versionsPfad, listePfad, vorlagePfad, static.StandardFeeds())
	if err != nil {
		return err
	}
	log.Printf("statictool: gebietsliste %s -- Bestand %d aus %s, %d neue IDs, "+
		"%d von %d Namen in dieser Version, %d gleichnamige anderswo verworfen",
		listePfad, bericht.Bestand, herkunft, bericht.Neu,
		bericht.NamenMitTreffer, bericht.Namen, bericht.OrtZuWeit)
	// Der Fall, um den es geht: die Version fuehrt die Stationen unter neuen
	// Nummern, und keine davon kommt an. Dann greift die Liste ab dem naechsten
	// Feed-Wechsel ins Leere, und niemand sieht es an der Promille-Zahl.
	if bericht.NamenMitTreffer*2 < bericht.Namen {
		log.Printf("statictool: WARNUNG -- nur %d von %d Stationsnamen stehen in dieser "+
			"Version. Entweder hat sich die Schreibweise geaendert oder die Version ist "+
			"unvollstaendig; die Liste beschreibt dann nicht mehr das Gebiet",
			bericht.NamenMitTreffer, bericht.Namen)
	}
	return nil
}

func envOr(key, fallback string) string {
	if v, ok := os.LookupEnv(key); ok && v != "" {
		return v
	}
	return fallback
}
