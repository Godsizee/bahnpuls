// Package writer persists decoded, deduped stop events as partitioned
// Parquet+ZSTD files on the Persistent Volume (ADR-003, ADR-004).
//
// Rohdaten sind unveränderlich: Flush always creates a new file, never
// appends to or overwrites an existing one, so a retried or resumed flush
// can never corrupt previously written history.
package writer

import (
	"fmt"
	"os"
	"path/filepath"
	"time"

	"github.com/parquet-go/parquet-go"

	"bahnpuls/internal/gtfsrt"
)

// Row is one raw stop-event record as persisted to Parquet. Column names and
// types mirror gtfsrt.StopEvent as closely as possible — the writer does not
// interpret or reshape data, only serializes it.
type Row struct {
	TripID                   string  `parquet:"trip_id"`
	StartDate                string  `parquet:"start_date"`
	RouteID                  string  `parquet:"route_id"`
	TripScheduleRelationship string  `parquet:"trip_schedule_relationship"`
	StopSequence             *uint32 `parquet:"stop_sequence,optional"`
	StopID                   string  `parquet:"stop_id"`
	ArrivalDelay             *int32  `parquet:"arrival_delay,optional"`
	ArrivalTime              *int64  `parquet:"arrival_time,optional"`
	DepartureDelay           *int32  `parquet:"departure_delay,optional"`
	DepartureTime            *int64  `parquet:"departure_time,optional"`
	ScheduleRelationship     string  `parquet:"schedule_relationship"`
	IsTripLevelOnly          bool    `parquet:"is_trip_level_only"`
	// SnapshotTimestamp is the feed's own header.timestamp (Unix seconds) —
	// when the producer generated this snapshot.
	SnapshotTimestamp int64 `parquet:"snapshot_timestamp"`
	// FetchedAt is the collector's wall-clock time at poll (Unix seconds) —
	// distinct from SnapshotTimestamp, needed to diagnose feed lag.
	FetchedAt int64 `parquet:"fetched_at"`
}

// RowFromStopEvent converts a decoded StopEvent into a storable Row.
// feedTimestamp is the feed's header.timestamp; fetchedAt is the collector's
// wall-clock time when the poll happened.
func RowFromStopEvent(ev gtfsrt.StopEvent, feedTimestamp uint64, fetchedAt time.Time) Row {
	row := Row{
		TripID:                   ev.TripID,
		StartDate:                ev.StartDate,
		RouteID:                  ev.RouteID,
		TripScheduleRelationship: string(ev.TripScheduleRelationship),
		StopID:                   ev.StopID,
		ArrivalDelay:             ev.ArrivalDelay,
		ArrivalTime:              ev.ArrivalTime,
		DepartureDelay:           ev.DepartureDelay,
		DepartureTime:            ev.DepartureTime,
		ScheduleRelationship:     string(ev.ScheduleRelationship),
		IsTripLevelOnly:          ev.IsTripLevelOnly,
		SnapshotTimestamp:        int64(feedTimestamp),
		FetchedAt:                fetchedAt.Unix(),
	}
	if ev.HasStopSequence {
		seq := ev.StopSequence
		row.StopSequence = &seq
	}
	return row
}

// Writer buffers rows in memory and flushes them to Parquet files under
// baseDir, partitioned as date=YYYY-MM-DD/hour=HH.
//
// Not safe for concurrent use — the collector's poll loop is single-threaded
// by design (Bahnpuls_Architektur).
type Writer struct {
	baseDir string
	buf     []Row
}

// New returns a Writer that writes partitions under baseDir.
func New(baseDir string) *Writer {
	return &Writer{baseDir: baseDir}
}

// Add appends a row to the in-memory buffer.
func (w *Writer) Add(row Row) {
	w.buf = append(w.buf, row)
}

// Len returns the number of buffered, not-yet-flushed rows.
func (w *Writer) Len() int {
	return len(w.buf)
}

// Flush writes all buffered rows to a new Parquet file under the partition
// for partitionTime and clears the buffer. It is a no-op — no file is
// created — when the buffer is empty, so a periodic flush tick with nothing
// new to write doesn't litter the volume with empty files.
//
// partitionTime is the collector's wall-clock time, not a resolved
// Betriebstag (CLAUDE.md Regel 6 — that resolution happens in dbt, never
// here).
func (w *Writer) Flush(partitionTime time.Time) (path string, err error) {
	if len(w.buf) == 0 {
		return "", nil
	}

	dir := filepath.Join(
		w.baseDir,
		fmt.Sprintf("date=%s", partitionTime.Format("2006-01-02")),
		fmt.Sprintf("hour=%02d", partitionTime.Hour()),
	)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return "", fmt.Errorf("writer: create partition dir %q: %w", dir, err)
	}

	path = filepath.Join(dir, fmt.Sprintf("%d.parquet", time.Now().UnixNano()))
	if err := parquet.WriteFile(path, w.buf, parquet.Compression(&parquet.Zstd)); err != nil {
		return "", fmt.Errorf("writer: write parquet file %q: %w", path, err)
	}

	w.buf = w.buf[:0]
	return path, nil
}
