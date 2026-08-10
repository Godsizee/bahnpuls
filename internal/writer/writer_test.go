package writer

import (
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/parquet-go/parquet-go"

	"bahnpuls/internal/gtfsrt"
)

func TestFlush_EmptyBufferIsNoOp(t *testing.T) {
	w := New(t.TempDir())
	path, err := w.Flush(time.Now())
	if err != nil {
		t.Fatalf("Flush: %v", err)
	}
	if path != "" {
		t.Errorf("path = %q, want empty for a no-op flush", path)
	}
}

func TestFlush_PartitionsByDateAndHour(t *testing.T) {
	base := t.TempDir()
	w := New(base)
	w.Add(Row{TripID: "1", StopID: "A"})

	partitionTime := time.Date(2026, 8, 10, 14, 0, 0, 0, time.UTC)
	path, err := w.Flush(partitionTime)
	if err != nil {
		t.Fatalf("Flush: %v", err)
	}

	wantDir := filepath.Join(base, "date=2026-08-10", "hour=14")
	if gotDir := filepath.Dir(path); gotDir != wantDir {
		t.Errorf("partition dir = %q, want %q", gotDir, wantDir)
	}
	if _, err := os.Stat(path); err != nil {
		t.Errorf("flushed file does not exist: %v", err)
	}
	if w.Len() != 0 {
		t.Errorf("Len() after Flush = %d, want 0 (buffer must be cleared)", w.Len())
	}
}

func TestFlush_RoundTripsRows(t *testing.T) {
	w := New(t.TempDir())

	delay := int32(120)
	arrTime := int64(1786348800)
	var seq uint32 = 3

	w.Add(Row{
		TripID:                   "830397",
		StartDate:                "20260810",
		RouteID:                  "RE70",
		TripScheduleRelationship: "SCHEDULED",
		StopSequence:             &seq,
		StopID:                   "52980",
		ArrivalDelay:             &delay,
		ArrivalTime:              &arrTime,
		ScheduleRelationship:     "SCHEDULED",
		SnapshotTimestamp:        1786348520,
		FetchedAt:                1786348525,
	})
	// A row with unset optional fields — must round-trip as nil, not zero.
	w.Add(Row{
		TripID:                   "999",
		TripScheduleRelationship: "CANCELED",
		IsTripLevelOnly:          true,
		SnapshotTimestamp:        1786348520,
		FetchedAt:                1786348525,
	})

	path, err := w.Flush(time.Now())
	if err != nil {
		t.Fatalf("Flush: %v", err)
	}

	got, err := parquet.ReadFile[Row](path)
	if err != nil {
		t.Fatalf("parquet.ReadFile: %v", err)
	}
	if len(got) != 2 {
		t.Fatalf("len(rows) = %d, want 2", len(got))
	}

	first := got[0]
	if first.TripID != "830397" || first.StopID != "52980" {
		t.Errorf("first row = %+v, unexpected identity fields", first)
	}
	if first.StopSequence == nil || *first.StopSequence != 3 {
		t.Errorf("StopSequence = %v, want 3", first.StopSequence)
	}
	if first.ArrivalDelay == nil || *first.ArrivalDelay != 120 {
		t.Errorf("ArrivalDelay = %v, want 120", first.ArrivalDelay)
	}
	if first.DepartureDelay != nil {
		t.Errorf("DepartureDelay = %v, want nil (never set)", first.DepartureDelay)
	}

	second := got[1]
	if !second.IsTripLevelOnly {
		t.Error("IsTripLevelOnly = false, want true")
	}
	if second.StopSequence != nil {
		t.Errorf("StopSequence = %v, want nil for a trip-level-only row", second.StopSequence)
	}
	if second.ArrivalDelay != nil || second.ArrivalTime != nil {
		t.Errorf("Arrival = (%v, %v), want (nil, nil)", second.ArrivalDelay, second.ArrivalTime)
	}
}

func TestRowFromStopEvent(t *testing.T) {
	fetchedAt := time.Date(2026, 8, 10, 9, 55, 25, 0, time.UTC)
	delay := int32(60)

	ev := gtfsrt.StopEvent{
		TripID:                   "1",
		HasStopSequence:          true,
		StopSequence:             7,
		StopID:                   "A",
		ArrivalDelay:             &delay,
		ScheduleRelationship:     gtfsrt.ScheduleRelationshipScheduled,
		TripScheduleRelationship: gtfsrt.ScheduleRelationshipScheduled,
	}

	row := RowFromStopEvent(ev, 1786348520, fetchedAt)

	if row.StopSequence == nil || *row.StopSequence != 7 {
		t.Errorf("StopSequence = %v, want 7", row.StopSequence)
	}
	if row.ArrivalDelay == nil || *row.ArrivalDelay != 60 {
		t.Errorf("ArrivalDelay = %v, want 60", row.ArrivalDelay)
	}
	if row.SnapshotTimestamp != 1786348520 {
		t.Errorf("SnapshotTimestamp = %d, want 1786348520", row.SnapshotTimestamp)
	}
	if row.FetchedAt != fetchedAt.Unix() {
		t.Errorf("FetchedAt = %d, want %d", row.FetchedAt, fetchedAt.Unix())
	}

	t.Run("without stop sequence", func(t *testing.T) {
		ev2 := ev
		ev2.HasStopSequence = false
		ev2.StopSequence = 0
		row2 := RowFromStopEvent(ev2, 1786348520, fetchedAt)
		if row2.StopSequence != nil {
			t.Errorf("StopSequence = %v, want nil", row2.StopSequence)
		}
	})
}
