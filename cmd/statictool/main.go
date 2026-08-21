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
	flag.Parse()

	log.SetFlags(log.LstdFlags | log.Lmicroseconds)

	if *version == "" {
		*version = static.Version(time.Now())
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
	switch {
	case errors.Is(err, static.ErrVersionVorhanden):
		// Kein Fehler: die Version steht schon, und eine vorhandene Version wird
		// nie ueberschrieben (Regel 1). Exit 0, damit der Task nicht rot wird.
		log.Printf("statictool: version %s existiert bereits, nichts zu tun", *version)
		return
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

	log.Printf("statictool: version abgelegt unter %s", ziel)
	log.Printf("statictool: Hinweis -- Haltestellenlisten und Namenszuordnungen werden " +
		"aus allen Versionen vereinigt, nie ersetzt (Q6: die stop_id-Werte rotieren " +
		"zwischen Veroeffentlichungen fast vollstaendig)")
}

func envOr(key, fallback string) string {
	if v, ok := os.LookupEnv(key); ok && v != "" {
		return v
	}
	return fallback
}
