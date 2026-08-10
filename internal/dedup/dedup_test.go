package dedup

import (
	"testing"

	"bahnpuls/internal/gtfsrt"
)

func i32(v int32) *int32 { return &v }
func i64(v int64) *int64 { return &v }

func baseEvent() gtfsrt.StopEvent {
	return gtfsrt.StopEvent{
		TripID:                   "830397",
		StartDate:                "20260810",
		HasStopSequence:          true,
		StopSequence:             3,
		StopID:                   "52980",
		ArrivalDelay:             i32(60),
		ArrivalTime:              i64(1786348800),
		DepartureDelay:           i32(90),
		DepartureTime:            i64(1786348830),
		ScheduleRelationship:     gtfsrt.ScheduleRelationshipScheduled,
		TripScheduleRelationship: gtfsrt.ScheduleRelationshipScheduled,
	}
}

func TestTracker_FirstSeenIsAlwaysChanged(t *testing.T) {
	tr := NewTracker()
	if !tr.Changed(baseEvent()) {
		t.Error("Changed() = false for a never-seen key, want true")
	}
}

func TestTracker_RepeatIsNotChanged(t *testing.T) {
	tr := NewTracker()
	ev := baseEvent()
	tr.Changed(ev)

	if tr.Changed(ev) {
		t.Error("Changed() = true for an identical repeat, want false")
	}
}

func TestTracker_DelayChangeIsChanged(t *testing.T) {
	tr := NewTracker()
	ev := baseEvent()
	tr.Changed(ev)

	ev.ArrivalDelay = i32(180)
	if !tr.Changed(ev) {
		t.Error("Changed() = false after arrival delay changed, want true")
	}
}

func TestTracker_NilToValueIsChanged(t *testing.T) {
	tr := NewTracker()
	ev := baseEvent()
	ev.DepartureDelay = nil
	ev.DepartureTime = nil
	tr.Changed(ev)

	ev.DepartureDelay = i32(30)
	ev.DepartureTime = i64(1786348860)
	if !tr.Changed(ev) {
		t.Error("Changed() = false after delay went from absent to present, want true")
	}
}

func TestTracker_ValueToNilIsChanged(t *testing.T) {
	tr := NewTracker()
	ev := baseEvent()
	tr.Changed(ev)

	ev.DepartureDelay = nil
	ev.DepartureTime = nil
	if !tr.Changed(ev) {
		t.Error("Changed() = false after delay went from present to absent, want true")
	}
}

func TestTracker_ScheduleRelationshipChangeIsChanged(t *testing.T) {
	tr := NewTracker()
	ev := baseEvent()
	tr.Changed(ev)

	ev.ScheduleRelationship = gtfsrt.ScheduleRelationshipSkipped
	if !tr.Changed(ev) {
		t.Error("Changed() = false after stop-level schedule_relationship changed to SKIPPED, want true")
	}
}

func TestTracker_TripCanceledIsChanged(t *testing.T) {
	tr := NewTracker()
	ev := baseEvent()
	tr.Changed(ev)

	ev.TripScheduleRelationship = gtfsrt.ScheduleRelationshipCanceled
	if !tr.Changed(ev) {
		t.Error("Changed() = false after trip-level schedule_relationship changed to CANCELED, want true")
	}
}

func TestTracker_DifferentStopsTrackedIndependently(t *testing.T) {
	tr := NewTracker()
	ev := baseEvent()
	tr.Changed(ev)

	other := baseEvent()
	other.StopSequence = 4
	other.StopID = "52981"
	if !tr.Changed(other) {
		t.Error("Changed() = false for a different stop on the same trip, want true (independent key)")
	}
	if tr.Len() != 2 {
		t.Errorf("Len() = %d, want 2", tr.Len())
	}
}

func TestTracker_DifferentTripsTrackedIndependently(t *testing.T) {
	tr := NewTracker()
	ev := baseEvent()
	tr.Changed(ev)

	other := baseEvent()
	other.TripID = "999999"
	if !tr.Changed(other) {
		t.Error("Changed() = false for a different trip with the same stop_sequence, want true (independent key)")
	}
}

func TestTracker_DifferentOperatingDaysTrackedIndependently(t *testing.T) {
	tr := NewTracker()
	ev := baseEvent()
	tr.Changed(ev)

	other := baseEvent()
	other.StartDate = "20260811"
	if !tr.Changed(other) {
		t.Error("Changed() = false for the same trip_id on a different start_date, want true (independent key)")
	}
}

func TestTracker_FallsBackToStopIDWithoutStopSequence(t *testing.T) {
	tr := NewTracker()
	ev := baseEvent()
	ev.HasStopSequence = false
	ev.StopSequence = 0
	tr.Changed(ev)

	if tr.Changed(ev) {
		t.Error("Changed() = true for an identical repeat keyed by stop_id, want false")
	}

	other := ev
	other.StopID = "different-stop"
	if !tr.Changed(other) {
		t.Error("Changed() = false for a different stop_id, want true")
	}
}

func TestTracker_TripLevelOnlyDoesNotCollideWithStopKeys(t *testing.T) {
	tr := NewTracker()

	tripLevel := gtfsrt.StopEvent{
		TripID:                   "830397",
		StartDate:                "20260810",
		IsTripLevelOnly:          true,
		TripScheduleRelationship: gtfsrt.ScheduleRelationshipCanceled,
	}
	if !tr.Changed(tripLevel) {
		t.Fatal("Changed() = false for the first trip-level marker, want true")
	}

	// A stop with an empty stop_id and no stop_sequence must not be treated
	// as the same key as the trip-level marker.
	stopEv := gtfsrt.StopEvent{
		TripID:    "830397",
		StartDate: "20260810",
		StopID:    "",
	}
	if !tr.Changed(stopEv) {
		t.Error("Changed() = false for a stop-level event with empty stop_id, want true (distinct from trip-level marker)")
	}
	if tr.Len() != 2 {
		t.Errorf("Len() = %d, want 2", tr.Len())
	}
}
