// Package scope filters GTFS-RT trips down to the target area (VRN + Rhein-Main).
//
// The filter matches on a stop-ID allowlist, never on Verbund/Agency — VRN and
// RMV are tariff associations, not a data category, and an agency filter would
// incorrectly drop long-distance trains passing through (ADR-008). The
// allowlist is a runtime configuration file, not compiled into the binary, so
// widening the scope is a config change, not a redeploy.
package scope

import (
	"encoding/csv"
	"fmt"
	"io"
	"os"
	"strings"
)

// Filter decides whether a trip touches the configured target area.
type Filter struct {
	stopIDs map[string]struct{}
}

// LoadCSV reads a stop-list configuration (header: stop_id,stop_name,stop_lat,
// stop_lon — only stop_id is required) and builds a Filter from it.
func LoadCSV(path string) (*Filter, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, fmt.Errorf("scope: open config %q: %w", path, err)
	}
	defer f.Close()

	filter, err := newFilterFromReader(f)
	if err != nil {
		return nil, fmt.Errorf("scope: load config %q: %w", path, err)
	}
	return filter, nil
}

func newFilterFromReader(r io.Reader) (*Filter, error) {
	reader := csv.NewReader(r)
	reader.TrimLeadingSpace = true

	header, err := reader.Read()
	if err != nil {
		return nil, fmt.Errorf("read header: %w", err)
	}
	idCol, err := columnIndex(header, "stop_id")
	if err != nil {
		return nil, err
	}

	stopIDs := make(map[string]struct{})
	for {
		record, err := reader.Read()
		if err == io.EOF {
			break
		}
		if err != nil {
			return nil, fmt.Errorf("read row: %w", err)
		}
		id := strings.TrimSpace(record[idCol])
		if id == "" {
			continue
		}
		stopIDs[id] = struct{}{}
	}
	if len(stopIDs) == 0 {
		return nil, fmt.Errorf("no stop_id entries found")
	}
	return &Filter{stopIDs: stopIDs}, nil
}

func columnIndex(header []string, name string) (int, error) {
	for i, h := range header {
		if strings.TrimSpace(h) == name {
			return i, nil
		}
	}
	return -1, fmt.Errorf("header missing required column %q", name)
}

// Len returns the number of configured stop IDs.
func (f *Filter) Len() int {
	return len(f.stopIDs)
}

// HasStop reports whether the given stop_id lies in the target area.
func (f *Filter) HasStop(stopID string) bool {
	_, ok := f.stopIDs[stopID]
	return ok
}

// TripInScope reports whether a trip should be kept: it is in scope as soon
// as any one of its stops lies in the target area, so a through-running
// long-distance train is kept even though most of its stops are outside
// (see Q2 in Open Questions — the filter runs per touched stop, not per trip
// origin/destination).
func (f *Filter) TripInScope(stopIDs []string) bool {
	for _, id := range stopIDs {
		if f.HasStop(id) {
			return true
		}
	}
	return false
}
