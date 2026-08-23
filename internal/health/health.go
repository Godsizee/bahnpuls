// Package health tracks and persists the collector's operational status —
// last poll, feed age, entity/change counts — so a Docker healthcheck
// (BPULS-022) and manual inspection can tell a running-but-stuck collector
// apart from one that's actually working. A feed outage or a stale process
// must never look like "no delays right now" (Bahnpuls_Architektur:
// Feed-Ausfall ≠ keine Verspätung).
package health

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
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
	// TrackedKeys is the size of the dedup tracker (BPULS-028).
	TrackedKeys int `json:"tracked_keys"`
	// OutsideCount counts stop events whose stop_id is not in the target area
	// (BPULS-074). A trip is kept as soon as one of its stops lies inside, so
	// a through-running long-distance train drags its whole route in — Munich
	// and Hamburg included. This counter reports how many stops that is.
	//
	// It is filled whether or not those stops are actually dropped: the drop
	// is only armed by BAHNPULS_STOP_FILTER=on. Measuring first is not
	// pedantry here — stop_ids rotate almost completely between timetable
	// releases, so a stop inside the area can fail the check simply because
	// its current id is missing from the list, and what the collector does not
	// write is gone for good (CLAUDE.md Regel 3).
	OutsideCount int `json:"outside_count"`
	// OutsideDropped is true when those events were discarded rather than
	// merely counted.
	OutsideDropped bool `json:"outside_dropped"`
	// ResidentKB is the process's resident set size. Without it, memory can
	// only be read by opening a shell in the container — and a collector that
	// has to run unattended for months must be measurable from the outside
	// (BPULS-059). 0 means "not determinable here", never "nothing used".
	ResidentKB int64 `json:"resident_kb"`
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

// procStatusPath is a variable so the parser can be tested against a fixture
// instead of only against whatever the test machine happens to expose.
var procStatusPath = "/proc/self/status"

// ResidentKB reports the process's resident set size in kilobytes, or 0 where
// that cannot be read — on Windows there is no /proc, and the development
// machine must not fail over a number that only matters in the container.
func ResidentKB() int64 {
	data, err := os.ReadFile(procStatusPath)
	if err != nil {
		return 0
	}
	return parseVmRSS(data)
}

// parseVmRSS picks the VmRSS line out of /proc/<pid>/status, which reads
// "VmRSS:\t 1264616 kB".
func parseVmRSS(data []byte) int64 {
	for _, line := range bytes.Split(data, []byte("\n")) {
		if !bytes.HasPrefix(line, []byte("VmRSS:")) {
			continue
		}
		fields := bytes.Fields(line[len("VmRSS:"):])
		if len(fields) == 0 {
			return 0
		}
		kb, err := strconv.ParseInt(string(fields[0]), 10, 64)
		if err != nil {
			return 0
		}
		return kb
	}
	return 0
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
