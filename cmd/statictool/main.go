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
	flag.Parse()

	log.SetFlags(log.LstdFlags | log.Lmicroseconds)

	if *version == "" {
		*version = static.Version(time.Now())
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
