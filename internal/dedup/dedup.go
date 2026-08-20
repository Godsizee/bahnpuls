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

// entry is one tracked key's last-written state plus the snapshot generation
// it was last present in, which is what makes eviction possible.
type entry struct {
	snap     snapshot
	lastSeen uint64
}

// Tracker remembers the last-written state per (trip, stop position) and
// decides whether a new event is a real change worth writing.
//
// Not safe for concurrent use — the collector's poll loop is single-threaded
// by design (Bahnpuls_Architektur), so a mutex would be unused complexity.
//
// Keys are forgotten once they have been absent from the feed for
// maxIdlePolls snapshots (BPULS-028). Without that the map grows for the
// lifetime of the process: the key carries the Betriebstag, so yesterday's
// keys can never recur and would be kept forever.
//
// A forgotten key that reappears is written once more as a change. That is a
// duplicate row, not a lost one — and raw duplicates have to be handled
// downstream anyway, because a Coolify redeploy runs the old and the new
// container side by side for a moment (BPULS-030).
type Tracker struct {
	seen         map[key]entry
	gen          uint64
	maxIdlePolls uint64
	evictable    bool
}

// NewTracker returns an empty Tracker that forgets a key after maxIdlePolls
// consecutive snapshots without it. A value <= 0 disables eviction entirely,
// which is what the tests that only care about change detection use.
func NewTracker(maxIdlePolls int) *Tracker {
	t := &Tracker{seen: make(map[key]entry)}
	if maxIdlePolls > 0 {
		t.maxIdlePolls = uint64(maxIdlePolls)
		t.evictable = true
	}
	return t
}

// StartPoll opens a new snapshot generation and forgets every key that has
// been absent for longer than maxIdlePolls generations. It returns how many
// keys were forgotten.
//
// Call it once per *successfully decoded* poll, before feeding that poll's
// events to Changed. Deliberately not called on a failed fetch: generations
// count observations, not wall-clock time, so a feed outage must not age out
// trips that are still running.
func (t *Tracker) StartPoll() int {
	t.gen++
	if !t.evictable || t.gen <= t.maxIdlePolls {
		return 0
	}
	cutoff := t.gen - t.maxIdlePolls
	evicted := 0
	for k, e := range t.seen {
		if e.lastSeen < cutoff {
			delete(t.seen, k)
			evicted++
		}
	}
	return evicted
}

// Changed reports whether ev differs from the last-seen state for its
// (trip, stop) key — true for the first time a key is seen. It records ev as
// the new last-seen state as a side effect, so call it exactly once per
// incoming event, in poll order.
func (t *Tracker) Changed(ev gtfsrt.StopEvent) bool {
	k := keyFor(ev)
	next := snapshotFor(ev)

	prev, ok := t.seen[k]
	t.seen[k] = entry{snap: next, lastSeen: t.gen}
	if !ok {
		return true
	}
	return !equalSnapshot(prev.snap, next)
}

// Len returns the number of tracked (trip, stop) keys.
func (t *Tracker) Len() int {
	return len(t.seen)
}
