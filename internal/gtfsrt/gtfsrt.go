// Package gtfsrt decodes GTFS-RT FeedMessage protobuf payloads into a flat
// list of stop events, ready for scope filtering, dedup and storage.
//
// Decoding intentionally does no interpretation — no "final" Ist-value
// selection, no Betriebstag resolution (CLAUDE.md Regel 6). That happens in
// the dbt transformation layer, never here; raw values are stored as
// delivered by the feed.
//
// Only TripUpdate entities are extracted. Alert entities (roughly half of
// every snapshot, see Bahnpuls_Datenquellen) and VehiclePosition entities
// (gtfs.de does not deliver any) have no place in fct_stop_events
// (Bahnpuls_Datenmodell) and are skipped.
package gtfsrt

import (
	"fmt"

	"github.com/MobilityData/gtfs-realtime-bindings/golang/gtfs"
	"google.golang.org/protobuf/encoding/protowire"
	"google.golang.org/protobuf/proto"
)

// ScheduleRelationship mirrors the GTFS-RT enum values as strings, so
// downstream code and Parquet columns don't depend on the vendored protobuf
// types.
type ScheduleRelationship string

const (
	ScheduleRelationshipScheduled   ScheduleRelationship = "SCHEDULED"
	ScheduleRelationshipSkipped     ScheduleRelationship = "SKIPPED"
	ScheduleRelationshipNoData      ScheduleRelationship = "NO_DATA"
	ScheduleRelationshipAdded       ScheduleRelationship = "ADDED"
	ScheduleRelationshipCanceled    ScheduleRelationship = "CANCELED"
	ScheduleRelationshipUnscheduled ScheduleRelationship = "UNSCHEDULED"
	ScheduleRelationshipDuplicated  ScheduleRelationship = "DUPLICATED"
	ScheduleRelationshipReplacement ScheduleRelationship = "REPLACEMENT"
)

// Feed is a decoded GTFS-RT snapshot.
type Feed struct {
	// Timestamp is the feed's own creation time (header.timestamp, Unix
	// seconds) — used for Feed-Alter health checks, not wall-clock time.
	Timestamp  uint64
	StopEvents []StopEvent
}

// StopEvent is one row of TripUpdate.StopTimeUpdate, flattened with its
// parent trip's identifying fields.
//
// Arrival/Departure delay and time are pointers because "absent" and "zero"
// are different facts: delay == 0 means exactly on time, delay == nil means
// the field was not delivered in this snapshot (Bahnpuls_Datenquellen: delay
// was populated in 87-91% of stop_time_updates in a real snapshot, not all).
type StopEvent struct {
	TripID                   string
	StartDate                string // trip.start_date, YYYYMMDD as delivered, not yet a Betriebstag
	RouteID                  string
	TripScheduleRelationship ScheduleRelationship

	// StopSequence and StopID: per Bahnpuls_Datenmodell, either may be
	// unset in a given snapshot — StopSequence is the reliable join key,
	// StopID is display-only and can repeat within one trip (loops,
	// terminus stations). HasStopSequence distinguishes "0" from "absent".
	StopSequence    uint32
	HasStopSequence bool
	StopID          string

	ArrivalDelay   *int32
	ArrivalTime    *int64
	DepartureDelay *int32
	DepartureTime  *int64

	ScheduleRelationship ScheduleRelationship

	// IsTripLevelOnly is true for a synthetic event with no per-stop data,
	// emitted when a TripUpdate carries zero stop_time_update entries — the
	// documented GTFS-RT shape for a fully CANCELED trip. Without it, a
	// cancellation with no stop_time_update would produce no row at all and
	// vanish from the raw data entirely, which the "Ausfall muss immer
	// danebenstehen" rule (Bahnpuls_Datenmodell) forbids. Callers cannot
	// scope-filter this event by stop (there is no stop to check) — see
	// cmd/collector for how that's handled.
	IsTripLevelOnly bool
}

// Decode parses a raw GTFS-RT FeedMessage protobuf payload.
// Field numbers of FeedMessage, needed because the snapshot is walked entity
// by entity instead of being unmarshalled in one piece (see WalkTripUpdates).
const (
	fieldHeader = 1
	fieldEntity = 2
)

// Decode unmarshals a whole snapshot into memory. Convenient for tests and
// small payloads; the collector uses WalkTripUpdates instead, because a real
// nationwide snapshot is around 40 MB and materialising all of it at once
// costs several hundred MB of heap (BPULS-059).
func Decode(raw []byte) (*Feed, error) {
	ts, err := DecodeTimestamp(raw)
	if err != nil {
		return nil, err
	}
	feed := &Feed{Timestamp: ts}
	err = WalkTripUpdates(raw, func(events []StopEvent) error {
		feed.StopEvents = append(feed.StopEvents, events...)
		return nil
	})
	if err != nil {
		return nil, err
	}
	return feed, nil
}

// DecodeTimestamp reads only header.timestamp, skipping over the entity
// payload without decoding it. The header is normally the first field on the
// wire, but nothing guarantees that, so it gets its own cheap pass rather
// than an assumption.
func DecodeTimestamp(raw []byte) (uint64, error) {
	var ts uint64
	err := walkFields(raw, func(num protowire.Number, payload []byte) error {
		if num != fieldHeader {
			return nil
		}
		header := &gtfs.FeedHeader{}
		if err := proto.Unmarshal(payload, header); err != nil {
			return fmt.Errorf("unmarshal feed header: %w", err)
		}
		ts = header.GetTimestamp()
		return nil
	})
	if err != nil {
		return 0, fmt.Errorf("gtfsrt: %w", err)
	}
	return ts, nil
}

// WalkTripUpdates calls fn once per TripUpdate entity, with that trip's stop
// events. Entities that carry no TripUpdate — roughly half of every snapshot
// is Alerts (Bahnpuls_Datenquellen) — never reach the caller and are never
// converted.
//
// The slice handed to fn is reused between calls: copy what you keep, never
// retain it. That reuse is the whole point — it lets the collector filter to
// its target area (~4 % of stop events) while only one trip is in memory at
// a time, instead of building the nationwide list first (BPULS-059).
//
// Returns the number of TripUpdate entities seen, whether or not fn kept them.
func WalkTripUpdates(raw []byte, fn func(events []StopEvent) error) error {
	entity := &gtfs.FeedEntity{}
	var events []StopEvent

	err := walkFields(raw, func(num protowire.Number, payload []byte) error {
		if num != fieldEntity {
			return nil
		}
		// proto.Unmarshal resets entity first, so one instance serves the
		// whole walk instead of one allocation per entity.
		if err := proto.Unmarshal(payload, entity); err != nil {
			return fmt.Errorf("unmarshal feed entity: %w", err)
		}
		tu := entity.GetTripUpdate()
		if tu == nil {
			return nil
		}
		events = appendStopEvents(events[:0], tu)
		return fn(events)
	})
	if err != nil {
		return fmt.Errorf("gtfsrt: %w", err)
	}
	return nil
}

// walkFields iterates the top-level fields of a protobuf message, handing
// each length-delimited payload to fn without copying it. Fields of other
// wire types are skipped, so an added scalar field in a future FeedMessage
// version does not break the walk.
func walkFields(raw []byte, fn func(num protowire.Number, payload []byte) error) error {
	for len(raw) > 0 {
		num, typ, n := protowire.ConsumeTag(raw)
		if n < 0 {
			return fmt.Errorf("read field tag: %w", protowire.ParseError(n))
		}
		raw = raw[n:]

		if typ != protowire.BytesType {
			n = protowire.ConsumeFieldValue(num, typ, raw)
			if n < 0 {
				return fmt.Errorf("skip field %d: %w", num, protowire.ParseError(n))
			}
			raw = raw[n:]
			continue
		}

		payload, n := protowire.ConsumeBytes(raw)
		if n < 0 {
			return fmt.Errorf("read field %d: %w", num, protowire.ParseError(n))
		}
		raw = raw[n:]

		if err := fn(num, payload); err != nil {
			return err
		}
	}
	return nil
}

// appendStopEvents appends one trip's stop events to dst and returns it, so
// the caller can keep reusing one buffer across entities.
func appendStopEvents(dst []StopEvent, tu *gtfs.TripUpdate) []StopEvent {
	trip := tu.GetTrip()
	tripSchedRel := ScheduleRelationship(trip.GetScheduleRelationship().String())

	updates := tu.GetStopTimeUpdate()
	if len(updates) == 0 {
		return append(dst, StopEvent{
			TripID:                   trip.GetTripId(),
			StartDate:                trip.GetStartDate(),
			RouteID:                  trip.GetRouteId(),
			TripScheduleRelationship: tripSchedRel,
			IsTripLevelOnly:          true,
		})
	}

	events := dst
	for _, stu := range updates {
		ev := StopEvent{
			TripID:                   trip.GetTripId(),
			StartDate:                trip.GetStartDate(),
			RouteID:                  trip.GetRouteId(),
			TripScheduleRelationship: tripSchedRel,
			StopID:                   stu.GetStopId(),
			ScheduleRelationship:     ScheduleRelationship(stu.GetScheduleRelationship().String()),
		}
		if stu.StopSequence != nil {
			ev.StopSequence = stu.GetStopSequence()
			ev.HasStopSequence = true
		}
		if arr := stu.GetArrival(); arr != nil {
			ev.ArrivalDelay = arr.Delay
			ev.ArrivalTime = arr.Time
		}
		if dep := stu.GetDeparture(); dep != nil {
			ev.DepartureDelay = dep.Delay
			ev.DepartureTime = dep.Time
		}
		events = append(events, ev)
	}
	return events
}

// StopIDs returns the distinct, non-empty stop IDs touched by a trip's
// events — the input shape internal/scope.Filter.TripInScope expects.
func StopIDs(events []StopEvent) []string {
	seen := make(map[string]struct{}, len(events))
	ids := make([]string, 0, len(events))
	for _, ev := range events {
		if ev.StopID == "" {
			continue
		}
		if _, ok := seen[ev.StopID]; ok {
			continue
		}
		seen[ev.StopID] = struct{}{}
		ids = append(ids, ev.StopID)
	}
	return ids
}
