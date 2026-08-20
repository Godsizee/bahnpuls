// Package health tracks and persists the collector's operational status —
// last poll, feed age, entity/change counts — so a Docker healthcheck
// (BPULS-022) and manual inspection can tell a running-but-stuck collector
// apart from one that's actually working. A feed outage or a stale process
// must never look like "no delays right now" (Bahnpuls_Architektur:
// Feed-Ausfall ≠ keine Verspätung).
package health

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"time"
)

// Heartbeat is one point-in-time snapshot of collector health.
type Heartbeat struct {
	PolledAt      time.Time `json:"polled_at"`
	FeedTimestamp uint64    `json:"feed_timestamp"`
	FeedAgeSec    int64     `json:"feed_age_seconds"`
	EntityCount   int       `json:"entity_count"`
	InScopeCount  int       `json:"in_scope_count"`
	ChangedCount  int       `json:"changed_count"`
	// TrackedKeys is the size of the dedup tracker — the cheapest proxy for
	// the collector's memory trend there is, and the only one visible from
	// outside the container (BPULS-028).
	TrackedKeys int `json:"tracked_keys"`
	// Err carries the last poll error, if any, so a failing-but-alive
	// process is visible instead of silently going stale.
	Err string `json:"error,omitempty"`
}

// FeedAge returns how old the feed snapshot was relative to now. A
// feedTimestamp of 0 (header field absent) reports zero rather than a huge
// bogus age relative to the Unix epoch.
func FeedAge(feedTimestamp uint64, now time.Time) time.Duration {
	if feedTimestamp == 0 {
		return 0
	}
	return now.Sub(time.Unix(int64(feedTimestamp), 0))
}

// Writer persists heartbeats to a fixed path, one file that always holds the
// latest status.
type Writer struct {
	path string
}

// NewWriter returns a Writer that writes heartbeats to path.
func NewWriter(path string) *Writer {
	return &Writer{path: path}
}

// Write atomically replaces the heartbeat file's contents: write to a temp
// file in the same directory, then rename into place. A heartbeat is a live
// status signal, not history (unlike raw data — Rohdaten sind
// unveränderlich does not apply here), so overwriting is correct, but the
// write itself must still be atomic or a concurrent reader (the Docker
// healthcheck) could observe a half-written file.
func (w *Writer) Write(hb Heartbeat) error {
	data, err := json.MarshalIndent(hb, "", "  ")
	if err != nil {
		return fmt.Errorf("health: marshal heartbeat: %w", err)
	}

	dir := filepath.Dir(w.path)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return fmt.Errorf("health: create heartbeat dir %q: %w", dir, err)
	}

	tmp, err := os.CreateTemp(dir, ".heartbeat-*.tmp")
	if err != nil {
		return fmt.Errorf("health: create temp heartbeat file: %w", err)
	}
	tmpPath := tmp.Name()

	if _, err := tmp.Write(data); err != nil {
		tmp.Close()
		os.Remove(tmpPath)
		return fmt.Errorf("health: write temp heartbeat file: %w", err)
	}
	if err := tmp.Close(); err != nil {
		os.Remove(tmpPath)
		return fmt.Errorf("health: close temp heartbeat file: %w", err)
	}
	if err := os.Rename(tmpPath, w.path); err != nil {
		os.Remove(tmpPath)
		return fmt.Errorf("health: rename heartbeat file into place: %w", err)
	}
	return nil
}
