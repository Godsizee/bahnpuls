// Package dedup decides which decoded GTFS-RT stop events are worth writing.
//
// GTFS-RT is polled every 30 seconds, but the underlying prediction changes
// far less often — over 90% of stop_time_update rows in a raw snapshot repeat
// the previous poll's state (Bahnpuls_Datenquellen). Writing every poll would
// multiply storage for no analytical value, since only the change matters,
// not how many times a value was re-confirmed.
package dedup

import (
	"strconv"

	"bahnpuls/internal/gtfsrt"
)

// key identifies one (trip instance, position in the trip) that is tracked
// independently. StopPos is the stop_sequence when the feed delivered one
// (the reliable join key per Bahnpuls_Datenmodell), falling back to stop_id,
// and finally a dedicated marker for a trip-level-only event (a CANCELED
// trip with no stop_time_update at all — see gtfsrt.StopEvent.IsTripLevelOnly).
type key struct {
	tripID    string
	startDate string
	stopPos   string
}

const tripLevelMarker = "\x00trip"

func keyFor(ev gtfsrt.StopEvent) key {
	pos := tripLevelMarker
	switch {
	case ev.IsTripLevelOnly:
		// keep the marker
	case ev.HasStopSequence:
		pos = strconv.FormatUint(uint64(ev.StopSequence), 10)
	default:
		pos = ev.StopID
	}
	return key{tripID: ev.TripID, startDate: ev.StartDate, stopPos: pos}
}

// snapshot is the subset of a StopEvent that decides whether something
// "changed". Fields not listed here (e.g. RouteID) are considered static
// for a given trip and don't trigger a rewrite on their own.
type snapshot struct {
	arrivalDelay             *int32
	arrivalTime              *int64
	departureDelay           *int32
	departureTime            *int64
	scheduleRelationship     gtfsrt.ScheduleRelationship
	tripScheduleRelationship gtfsrt.ScheduleRelationship
}

func snapshotFor(ev gtfsrt.StopEvent) snapshot {
	return snapshot{
		arrivalDelay:             ev.ArrivalDelay,
		arrivalTime:              ev.ArrivalTime,
		departureDelay:           ev.DepartureDelay,
		departureTime:            ev.DepartureTime,
		scheduleRelationship:     ev.ScheduleRelationship,
		tripScheduleRelationship: ev.TripScheduleRelationship,
	}
}

func equalSnapshot(a, b snapshot) bool {
	return equalInt32(a.arrivalDelay, b.arrivalDelay) &&
		equalInt64(a.arrivalTime, b.arrivalTime) &&
		equalInt32(a.departureDelay, b.departureDelay) &&
		equalInt64(a.departureTime, b.departureTime) &&
		a.scheduleRelationship == b.scheduleRelationship &&
		a.tripScheduleRelationship == b.tripScheduleRelationship
}

func equalInt32(a, b *int32) bool {
	if a == nil || b == nil {
		return a == b
	}
	return *a == *b
}

func equalInt64(a, b *int64) bool {
	if a == nil || b == nil {
		return a == b
	}
	return *a == *b
}

// Tracker remembers the last-written state per (trip, stop position) and
// decides whether a new event is a real change worth writing.
//
// Not safe for concurrent use — the collector's poll loop is single-threaded
// by design (Bahnpuls_Architektur), so a mutex would be unused complexity.
//
// State is never evicted. Bounding memory for a wider (e.g. nationwide)
// scope by discarding entries for completed trips is BPULS-028, deliberately
// deferred until the scope decision (Q12) is made.
type Tracker struct {
	seen map[key]snapshot
}

// NewTracker returns an empty Tracker.
func NewTracker() *Tracker {
	return &Tracker{seen: make(map[key]snapshot)}
}

// Changed reports whether ev differs from the last-seen state for its
// (trip, stop) key — true for the first time a key is seen. It records ev as
// the new last-seen state as a side effect, so call it exactly once per
// incoming event, in poll order.
func (t *Tracker) Changed(ev gtfsrt.StopEvent) bool {
	k := keyFor(ev)
	next := snapshotFor(ev)

	prev, ok := t.seen[k]
	t.seen[k] = next
	if !ok {
		return true
	}
	return !equalSnapshot(prev, next)
}

// Len returns the number of tracked (trip, stop) keys.
func (t *Tracker) Len() int {
	return len(t.seen)
}
