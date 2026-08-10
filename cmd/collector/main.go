// Command collector polls the gtfs.de GTFS-RT feed, filters it to the
// VRN+Rhein-Main target area, keeps only changed stop events, and writes
// them as partitioned Parquet+ZSTD files. See Bahnpuls_Architektur for the
// full design and CLAUDE.md for the non-negotiable operating rules.
package main

import (
	"context"
	"flag"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	// Embeds the IANA timezone database in the binary, so Europe/Berlin
	// resolves even in a minimal container image without a system tzdata
	// package (CLAUDE.md Regel 5 — preferred over relying on the image).
	_ "time/tzdata"

	"bahnpuls/internal/dedup"
	"bahnpuls/internal/gtfsrt"
	"bahnpuls/internal/health"
	"bahnpuls/internal/scope"
	"bahnpuls/internal/writer"
)

func main() {
	feedURL := flag.String("feed-url", envOr("BAHNPULS_FEED_URL", "https://realtime.gtfs.de/realtime-free.pb"), "GTFS-RT feed URL")
	scopePath := flag.String("scope-config", envOr("BAHNPULS_SCOPE_CONFIG", "config/scope_stops.csv"), "path to the target-area stop-list CSV")
	dataDir := flag.String("data-dir", envOr("BAHNPULS_DATA_DIR", "data/raw"), "base directory for partitioned Parquet output (Persistent Volume in production)")
	heartbeatPath := flag.String("heartbeat-path", envOr("BAHNPULS_HEARTBEAT_PATH", "data/heartbeat.json"), "path to the heartbeat status file")
	pollInterval := flag.Duration("poll-interval", 30*time.Second, "how often to poll the feed")
	fetchTimeout := flag.Duration("fetch-timeout", 15*time.Second, "per-attempt HTTP timeout")
	flag.Parse()

	log.SetFlags(log.LstdFlags | log.Lmicroseconds)

	scopeFilter, err := scope.LoadCSV(*scopePath)
	if err != nil {
		log.Fatalf("collector: load scope config: %v", err)
	}
	log.Printf("collector: scope loaded from %s, %d stops", *scopePath, scopeFilter.Len())

	rawWriter := writer.New(*dataDir)
	hbWriter := health.NewWriter(*heartbeatPath)
	tracker := dedup.NewTracker()
	httpClient := &http.Client{Timeout: *fetchTimeout}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	log.Printf("collector: starting, polling %s every %s", *feedURL, *pollInterval)
	pollSafely(ctx, httpClient, *feedURL, scopeFilter, tracker, rawWriter, hbWriter)

	pollTicker := time.NewTicker(*pollInterval)
	defer pollTicker.Stop()

	now := time.Now().UTC()
	flushTimer := time.NewTimer(nextHourBoundary(now).Sub(now))
	defer flushTimer.Stop()

	for {
		select {
		case <-ctx.Done():
			log.Println("collector: shutdown signal received, flushing buffer before exit")
			flushBuffer(rawWriter)
			log.Println("collector: shutdown complete")
			return

		case <-pollTicker.C:
			pollSafely(ctx, httpClient, *feedURL, scopeFilter, tracker, rawWriter, hbWriter)

		case <-flushTimer.C:
			flushBuffer(rawWriter)
			flushTimer.Reset(time.Hour)
		}
	}
}

// pollSafely wraps poll with panic recovery. This is the only place recover
// runs in the whole program (CLAUDE.md: "Panic-Recovery ausschließlich im
// äußeren Poll-Loop") — a crash inside decode or filter logic must cost at
// most the current buffered hour, never bring down the process that months
// of unattended collection depend on.
func pollSafely(ctx context.Context, client *http.Client, feedURL string, scopeFilter *scope.Filter, tracker *dedup.Tracker, w *writer.Writer, hbWriter *health.Writer) {
	defer func() {
		if r := recover(); r != nil {
			log.Printf("collector: recovered from panic during poll: %v", r)
		}
	}()
	poll(ctx, client, feedURL, scopeFilter, tracker, w, hbWriter)
}

func poll(ctx context.Context, client *http.Client, feedURL string, scopeFilter *scope.Filter, tracker *dedup.Tracker, w *writer.Writer, hbWriter *health.Writer) {
	now := time.Now().UTC()
	hb := health.Heartbeat{PolledAt: now}

	raw, err := fetchFeedWithRetry(ctx, client, feedURL)
	if err != nil {
		// Feed-Ausfall ≠ keine Verspätung: record the failure explicitly
		// instead of silently skipping this poll, so a stuck feed shows up
		// as a data gap, not as "everything was on time".
		hb.Err = err.Error()
		log.Printf("collector: fetch failed: %v", err)
		if werr := hbWriter.Write(hb); werr != nil {
			log.Printf("collector: write heartbeat failed: %v", werr)
		}
		return
	}

	feed, err := gtfsrt.Decode(raw)
	if err != nil {
		hb.Err = err.Error()
		log.Printf("collector: decode failed: %v", err)
		if werr := hbWriter.Write(hb); werr != nil {
			log.Printf("collector: write heartbeat failed: %v", werr)
		}
		return
	}
	hb.FeedTimestamp = feed.Timestamp
	hb.FeedAgeSec = int64(health.FeedAge(feed.Timestamp, now).Seconds())

	trips := groupByTrip(feed.StopEvents)
	hb.EntityCount = len(trips)

	for _, events := range trips {
		if !tripInScope(scopeFilter, events) {
			continue
		}
		hb.InScopeCount++
		for _, ev := range events {
			if tracker.Changed(ev) {
				hb.ChangedCount++
				w.Add(writer.RowFromStopEvent(ev, feed.Timestamp, now))
			}
		}
	}

	if err := hbWriter.Write(hb); err != nil {
		log.Printf("collector: write heartbeat failed: %v", err)
	}
	log.Printf("collector: poll ok — %d trips, %d in scope, %d changed, feed age %ds, buffer %d rows",
		hb.EntityCount, hb.InScopeCount, hb.ChangedCount, hb.FeedAgeSec, w.Len())
}

// tripKey groups a flat StopEvent list back into per-trip-instance batches.
type tripKey struct {
	tripID    string
	startDate string
}

func groupByTrip(events []gtfsrt.StopEvent) map[tripKey][]gtfsrt.StopEvent {
	trips := make(map[tripKey][]gtfsrt.StopEvent)
	for _, ev := range events {
		k := tripKey{tripID: ev.TripID, startDate: ev.StartDate}
		trips[k] = append(trips[k], ev)
	}
	return trips
}

// tripInScope decides whether a trip's events should be kept. A trip with no
// stop IDs at all — gtfsrt.StopEvent.IsTripLevelOnly, a fully CANCELED trip
// whose feed entry carries no stop_time_update — cannot be checked against
// the target area at all. It is kept unconditionally: dropping it risks
// silently losing a cancellation for a trip that does run through
// VRN+Rhein-Main, and "Verworfene Daten sind endgültig weg" (ADR-008) — the
// filter must err generous, not strict.
func tripInScope(filter *scope.Filter, events []gtfsrt.StopEvent) bool {
	ids := gtfsrt.StopIDs(events)
	if len(ids) == 0 {
		return true
	}
	return filter.TripInScope(ids)
}

func fetchFeedWithRetry(ctx context.Context, client *http.Client, url string) ([]byte, error) {
	const maxAttempts = 3
	var lastErr error
	for attempt := 1; attempt <= maxAttempts; attempt++ {
		body, err := fetchFeed(ctx, client, url)
		if err == nil {
			return body, nil
		}
		lastErr = err
		if attempt == maxAttempts {
			break
		}
		backoff := time.Duration(attempt) * 2 * time.Second
		select {
		case <-ctx.Done():
			return nil, ctx.Err()
		case <-time.After(backoff):
		}
	}
	return nil, fmt.Errorf("fetch feed after %d attempts: %w", maxAttempts, lastErr)
}

func fetchFeed(ctx context.Context, client *http.Client, url string) ([]byte, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return nil, fmt.Errorf("build request: %w", err)
	}
	resp, err := client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("do request: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("unexpected status %s", resp.Status)
	}
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("read body: %w", err)
	}
	return body, nil
}

func flushBuffer(w *writer.Writer) {
	if w.Len() == 0 {
		return
	}
	path, err := w.Flush(time.Now().UTC())
	if err != nil {
		log.Printf("collector: flush failed: %v", err)
		return
	}
	log.Printf("collector: flushed %s", path)
}

// nextHourBoundary returns the next full wall-clock hour after now, so
// flushes align with the date=/hour= partition scheme instead of drifting
// with process start time.
func nextHourBoundary(now time.Time) time.Time {
	return now.Truncate(time.Hour).Add(time.Hour)
}

func envOr(key, fallback string) string {
	if v, ok := os.LookupEnv(key); ok && v != "" {
		return v
	}
	return fallback
}
