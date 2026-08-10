package gtfsrt

import (
	"testing"

	"github.com/MobilityData/gtfs-realtime-bindings/golang/gtfs"
	"google.golang.org/protobuf/proto"
)

func mustMarshal(t *testing.T, msg *gtfs.FeedMessage) []byte {
	t.Helper()
	raw, err := proto.Marshal(msg)
	if err != nil {
		t.Fatalf("proto.Marshal: %v", err)
	}
	return raw
}

func baseHeader() *gtfs.FeedHeader {
	return &gtfs.FeedHeader{
		GtfsRealtimeVersion: proto.String("2.0"),
		Timestamp:           proto.Uint64(1786348520),
	}
}

func TestDecode_FlattensStopTimeUpdates(t *testing.T) {
	msg := &gtfs.FeedMessage{
		Header: baseHeader(),
		Entity: []*gtfs.FeedEntity{
			{
				Id: proto.String("1"),
				TripUpdate: &gtfs.TripUpdate{
					Trip: &gtfs.TripDescriptor{
						TripId:    proto.String("830397"),
						RouteId:   proto.String("RE70"),
						StartDate: proto.String("20260810"),
					},
					StopTimeUpdate: []*gtfs.TripUpdate_StopTimeUpdate{
						{
							StopSequence: proto.Uint32(3),
							StopId:       proto.String("52980"),
							Arrival: &gtfs.TripUpdate_StopTimeEvent{
								Delay: proto.Int32(120),
								Time:  proto.Int64(1786348800),
							},
							Departure: &gtfs.TripUpdate_StopTimeEvent{
								Delay: proto.Int32(90),
								Time:  proto.Int64(1786348830),
							},
						},
					},
				},
			},
			// Alert entity — must be skipped, not part of fct_stop_events.
			{
				Id:    proto.String("2"),
				Alert: &gtfs.Alert{},
			},
		},
	}

	feed, err := Decode(mustMarshal(t, msg))
	if err != nil {
		t.Fatalf("Decode: %v", err)
	}

	if feed.Timestamp != 1786348520 {
		t.Errorf("Timestamp = %d, want 1786348520", feed.Timestamp)
	}
	if len(feed.StopEvents) != 1 {
		t.Fatalf("len(StopEvents) = %d, want 1 (alert entity must be skipped)", len(feed.StopEvents))
	}

	ev := feed.StopEvents[0]
	if ev.TripID != "830397" || ev.RouteID != "RE70" || ev.StartDate != "20260810" {
		t.Errorf("trip fields = %+v, unexpected", ev)
	}
	if !ev.HasStopSequence || ev.StopSequence != 3 {
		t.Errorf("StopSequence = (%v, %d), want (true, 3)", ev.HasStopSequence, ev.StopSequence)
	}
	if ev.StopID != "52980" {
		t.Errorf("StopID = %q, want 52980", ev.StopID)
	}
	if ev.ArrivalDelay == nil || *ev.ArrivalDelay != 120 {
		t.Errorf("ArrivalDelay = %v, want 120", ev.ArrivalDelay)
	}
	if ev.DepartureTime == nil || *ev.DepartureTime != 1786348830 {
		t.Errorf("DepartureTime = %v, want 1786348830", ev.DepartureTime)
	}
	if ev.TripScheduleRelationship != ScheduleRelationshipScheduled {
		t.Errorf("TripScheduleRelationship = %q, want SCHEDULED", ev.TripScheduleRelationship)
	}
	if ev.ScheduleRelationship != ScheduleRelationshipScheduled {
		t.Errorf("ScheduleRelationship = %q, want SCHEDULED", ev.ScheduleRelationship)
	}
	if ev.IsTripLevelOnly {
		t.Error("IsTripLevelOnly = true, want false for a normal stop_time_update row")
	}
}

func TestDecode_MissingDelayAndStopSequence(t *testing.T) {
	// Real snapshots showed delay/time absent together, and stop_sequence
	// can be absent while only stop_id is delivered (Bahnpuls_Datenmodell
	// Fallstrick). Decode must not fabricate zero values that look real.
	msg := &gtfs.FeedMessage{
		Header: baseHeader(),
		Entity: []*gtfs.FeedEntity{
			{
				Id: proto.String("1"),
				TripUpdate: &gtfs.TripUpdate{
					Trip: &gtfs.TripDescriptor{TripId: proto.String("415343")},
					StopTimeUpdate: []*gtfs.TripUpdate_StopTimeUpdate{
						{
							StopId:               proto.String("497709"),
							ScheduleRelationship: gtfs.TripUpdate_StopTimeUpdate_SKIPPED.Enum(),
						},
					},
				},
			},
		},
	}

	feed, err := Decode(mustMarshal(t, msg))
	if err != nil {
		t.Fatalf("Decode: %v", err)
	}
	ev := feed.StopEvents[0]

	if ev.HasStopSequence {
		t.Errorf("HasStopSequence = true, want false for an update without stop_sequence")
	}
	if ev.ArrivalDelay != nil || ev.ArrivalTime != nil {
		t.Errorf("Arrival = (%v, %v), want (nil, nil)", ev.ArrivalDelay, ev.ArrivalTime)
	}
	if ev.ScheduleRelationship != ScheduleRelationshipSkipped {
		t.Errorf("ScheduleRelationship = %q, want SKIPPED", ev.ScheduleRelationship)
	}
}

func TestDecode_CanceledTrip(t *testing.T) {
	// A CANCELED trip typically carries zero stop_time_update entries. Decode
	// must still emit one trip-level marker row — dropping it silently would
	// make the cancellation invisible in the raw data (see IsTripLevelOnly).
	msg := &gtfs.FeedMessage{
		Header: baseHeader(),
		Entity: []*gtfs.FeedEntity{
			{
				Id: proto.String("1"),
				TripUpdate: &gtfs.TripUpdate{
					Trip: &gtfs.TripDescriptor{
						TripId:               proto.String("999"),
						ScheduleRelationship: gtfs.TripDescriptor_CANCELED.Enum(),
					},
				},
			},
		},
	}

	feed, err := Decode(mustMarshal(t, msg))
	if err != nil {
		t.Fatalf("Decode: %v", err)
	}
	if len(feed.StopEvents) != 1 {
		t.Fatalf("len(StopEvents) = %d, want 1 (trip-level marker for the cancellation)", len(feed.StopEvents))
	}

	ev := feed.StopEvents[0]
	if !ev.IsTripLevelOnly {
		t.Error("IsTripLevelOnly = false, want true")
	}
	if ev.TripID != "999" {
		t.Errorf("TripID = %q, want 999", ev.TripID)
	}
	if ev.TripScheduleRelationship != ScheduleRelationshipCanceled {
		t.Errorf("TripScheduleRelationship = %q, want CANCELED", ev.TripScheduleRelationship)
	}
	if ev.StopID != "" || ev.HasStopSequence {
		t.Errorf("expected no stop info, got StopID=%q HasStopSequence=%v", ev.StopID, ev.HasStopSequence)
	}
}

func TestDecode_InvalidPayload(t *testing.T) {
	if _, err := Decode([]byte{0xff, 0xff, 0xff}); err == nil {
		t.Fatal("expected error for invalid protobuf payload, got nil")
	}
}

func TestStopIDs(t *testing.T) {
	events := []StopEvent{
		{StopID: "A"},
		{StopID: "B"},
		{StopID: "A"},
		{StopID: ""},
		{StopID: "C"},
	}
	got := StopIDs(events)
	want := []string{"A", "B", "C"}
	if len(got) != len(want) {
		t.Fatalf("StopIDs() = %v, want %v", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Errorf("StopIDs()[%d] = %q, want %q", i, got[i], want[i])
		}
	}
}
