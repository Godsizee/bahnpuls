package main

import (
	"context"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"bahnpuls/internal/gtfsrt"
	"bahnpuls/internal/scope"
)

func TestGroupByTrip(t *testing.T) {
	events := []gtfsrt.StopEvent{
		{TripID: "1", StartDate: "20260810", StopID: "A"},
		{TripID: "1", StartDate: "20260810", StopID: "B"},
		{TripID: "2", StartDate: "20260810", StopID: "C"},
		// Same trip_id, different Betriebstag: a different trip instance.
		{TripID: "1", StartDate: "20260811", StopID: "D"},
	}

	trips := groupByTrip(events)

	if len(trips) != 3 {
		t.Fatalf("len(trips) = %d, want 3", len(trips))
	}
	if got := trips[tripKey{"1", "20260810"}]; len(got) != 2 {
		t.Errorf("trip 1/20260810 has %d events, want 2", len(got))
	}
	if got := trips[tripKey{"2", "20260810"}]; len(got) != 1 {
		t.Errorf("trip 2/20260810 has %d events, want 1", len(got))
	}
	if got := trips[tripKey{"1", "20260811"}]; len(got) != 1 {
		t.Errorf("trip 1/20260811 has %d events, want 1", len(got))
	}
}

func testScopeFilter(t *testing.T) *scope.Filter {
	t.Helper()
	path := filepath.Join(t.TempDir(), "scope.csv")
	csv := "stop_id,stop_name\n8000244,Mannheim Hbf\n8000105,Frankfurt Hbf\n"
	if err := os.WriteFile(path, []byte(csv), 0o644); err != nil {
		t.Fatalf("write scope config: %v", err)
	}
	f, err := scope.LoadCSV(path)
	if err != nil {
		t.Fatalf("scope.LoadCSV: %v", err)
	}
	return f
}

func TestTripInScope(t *testing.T) {
	filter := testScopeFilter(t)

	tests := []struct {
		name   string
		events []gtfsrt.StopEvent
		want   bool
	}{
		{
			name:   "stop inside target area",
			events: []gtfsrt.StopEvent{{StopID: "8000244"}},
			want:   true,
		},
		{
			name:   "entirely outside target area",
			events: []gtfsrt.StopEvent{{StopID: "1"}, {StopID: "2"}},
			want:   false,
		},
		{
			name:   "trip-level-only CANCELED marker kept unconditionally",
			events: []gtfsrt.StopEvent{{TripID: "999", IsTripLevelOnly: true}},
			want:   true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := tripInScope(filter, tt.events); got != tt.want {
				t.Errorf("tripInScope() = %v, want %v", got, tt.want)
			}
		})
	}
}

func TestNextHourBoundary(t *testing.T) {
	tests := []struct {
		now  time.Time
		want time.Time
	}{
		{
			now:  time.Date(2026, 8, 10, 14, 23, 5, 0, time.UTC),
			want: time.Date(2026, 8, 10, 15, 0, 0, 0, time.UTC),
		},
		{
			// exactly on the boundary still rolls to the next hour
			now:  time.Date(2026, 8, 10, 14, 0, 0, 0, time.UTC),
			want: time.Date(2026, 8, 10, 15, 0, 0, 0, time.UTC),
		},
		{
			now:  time.Date(2026, 8, 10, 23, 59, 59, 0, time.UTC),
			want: time.Date(2026, 8, 11, 0, 0, 0, 0, time.UTC),
		},
	}

	for _, tt := range tests {
		if got := nextHourBoundary(tt.now); !got.Equal(tt.want) {
			t.Errorf("nextHourBoundary(%v) = %v, want %v", tt.now, got, tt.want)
		}
	}
}

// Regression fuer BPULS-057: der Flush-Timer wird nach jedem Flush gegen die
// naechste Stundengrenze gestellt. Feuert er verspaetet -- weil ein
// blockierender Fetch den gemeinsamen Loop aufgehalten hat --, muss die
// naechste Wartezeit *kuerzer* als eine Stunde sein, sonst wandert die
// Verspaetung dauerhaft mit und die hour=-Partition driftet gegen ihren Inhalt.
func TestFlushTimerHoltVerspaetungAuf(t *testing.T) {
	tests := []struct {
		name     string
		flushbar time.Time
		want     time.Duration
	}{
		{
			name:     "puenktlich",
			flushbar: time.Date(2026, 8, 19, 9, 0, 0, 0, time.UTC),
			want:     time.Hour,
		},
		{
			name:     "knapp verspaetet",
			flushbar: time.Date(2026, 8, 19, 12, 1, 48, 0, time.UTC),
			want:     58*time.Minute + 12*time.Second,
		},
		{
			name:     "stark verspaetet, Rest der Stunde bleibt",
			flushbar: time.Date(2026, 8, 20, 8, 2, 57, 0, time.UTC),
			want:     57*time.Minute + 3*time.Second,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := nextHourBoundary(tt.flushbar).Sub(tt.flushbar)
			if got != tt.want {
				t.Errorf("Wartezeit nach Flush um %v = %v, want %v", tt.flushbar, got, tt.want)
			}
			if got > time.Hour {
				t.Errorf("Wartezeit %v laenger als eine Stunde -- Flush wuerde eine Partition ueberspringen", got)
			}
		})
	}
}

func TestEnvDurationOr(t *testing.T) {
	const key = "BAHNPULS_TEST_ENV_DURATION"
	const fallback = 25 * time.Second

	tests := []struct {
		name string
		set  bool
		val  string
		want time.Duration
	}{
		{name: "unset falls back", set: false, want: fallback},
		{name: "empty falls back", set: true, val: "", want: fallback},
		{name: "valid overrides", set: true, val: "45s", want: 45 * time.Second},
		{name: "minutes work too", set: true, val: "1m30s", want: 90 * time.Second},
		// Eine kaputte Angabe darf den Collector nicht stoppen: sie faellt auf
		// den Default zurueck, statt den Prozess in eine Restart-Schleife zu
		// schicken (CLAUDE.md Regel 3).
		{name: "garbage falls back", set: true, val: "eine Stunde", want: fallback},
		{name: "unitless falls back", set: true, val: "30", want: fallback},
		{name: "zero falls back", set: true, val: "0s", want: fallback},
		{name: "negative falls back", set: true, val: "-5s", want: fallback},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if tt.set {
				t.Setenv(key, tt.val)
			} else {
				os.Unsetenv(key)
			}
			if got := envDurationOr(key, fallback); got != tt.want {
				t.Errorf("envDurationOr(%q) = %v, want %v", tt.val, got, tt.want)
			}
		})
	}
}

func TestEnvOr(t *testing.T) {
	const key = "BAHNPULS_TEST_ENV_OR"

	t.Run("unset falls back", func(t *testing.T) {
		os.Unsetenv(key)
		if got := envOr(key, "fallback"); got != "fallback" {
			t.Errorf("envOr() = %q, want fallback", got)
		}
	})

	t.Run("set overrides", func(t *testing.T) {
		t.Setenv(key, "override")
		if got := envOr(key, "fallback"); got != "override" {
			t.Errorf("envOr() = %q, want override", got)
		}
	})

	t.Run("empty string falls back", func(t *testing.T) {
		t.Setenv(key, "")
		if got := envOr(key, "fallback"); got != "fallback" {
			t.Errorf("envOr() = %q, want fallback for empty env value", got)
		}
	})
}

func TestFetchFeed(t *testing.T) {
	t.Run("success", func(t *testing.T) {
		srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			w.Write([]byte("payload"))
		}))
		defer srv.Close()

		body, err := fetchFeed(context.Background(), srv.Client(), srv.URL)
		if err != nil {
			t.Fatalf("fetchFeed: %v", err)
		}
		if string(body) != "payload" {
			t.Errorf("body = %q, want payload", body)
		}
	})

	t.Run("non-200 status is an error", func(t *testing.T) {
		srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			w.WriteHeader(http.StatusServiceUnavailable)
		}))
		defer srv.Close()

		if _, err := fetchFeed(context.Background(), srv.Client(), srv.URL); err == nil {
			t.Fatal("expected error for 503 response, got nil")
		}
	})
}

func TestFetchFeedWithRetry_SucceedsAfterTransientFailures(t *testing.T) {
	var attempts int
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		attempts++
		if attempts < 2 {
			w.WriteHeader(http.StatusServiceUnavailable)
			return
		}
		w.Write([]byte("ok"))
	}))
	defer srv.Close()

	body, err := fetchFeedWithRetry(context.Background(), srv.Client(), srv.URL)
	if err != nil {
		t.Fatalf("fetchFeedWithRetry: %v", err)
	}
	if string(body) != "ok" {
		t.Errorf("body = %q, want ok", body)
	}
	if attempts != 2 {
		t.Errorf("attempts = %d, want 2", attempts)
	}
}

func TestFetchFeedWithRetry_GivesUpAfterMaxAttempts(t *testing.T) {
	var attempts int
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		attempts++
		w.WriteHeader(http.StatusServiceUnavailable)
	}))
	defer srv.Close()

	_, err := fetchFeedWithRetry(context.Background(), srv.Client(), srv.URL)
	if err == nil {
		t.Fatal("expected error after exhausting retries, got nil")
	}
	if !strings.Contains(err.Error(), "after 3 attempts") {
		t.Errorf("error = %v, want it to mention attempt count", err)
	}
	if attempts != 3 {
		t.Errorf("attempts = %d, want 3", attempts)
	}
}
