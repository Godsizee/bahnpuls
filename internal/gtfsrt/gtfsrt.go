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
}

// Decode parses a raw GTFS-RT FeedMessage protobuf payload.
func Decode(raw []byte) (*Feed, error) {
	msg := &gtfs.FeedMessage{}
	if err := proto.Unmarshal(raw, msg); err != nil {
		return nil, fmt.Errorf("gtfsrt: unmarshal feed message: %w", err)
	}

	feed := &Feed{Timestamp: msg.GetHeader().GetTimestamp()}
	for _, entity := range msg.GetEntity() {
		tu := entity.GetTripUpdate()
		if tu == nil {
			continue
		}
		feed.StopEvents = append(feed.StopEvents, stopEventsFromTripUpdate(tu)...)
	}
	return feed, nil
}

func stopEventsFromTripUpdate(tu *gtfs.TripUpdate) []StopEvent {
	trip := tu.GetTrip()
	tripSchedRel := ScheduleRelationship(trip.GetScheduleRelationship().String())

	updates := tu.GetStopTimeUpdate()
	events := make([]StopEvent, 0, len(updates))
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
