package scope

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

const validCSV = `stop_id,stop_name,stop_lat,stop_lon
8000244,Mannheim Hbf,49.4794,8.4689
8000105,Frankfurt Hbf,50.1069,8.6633
`

func TestNewFilterFromReader(t *testing.T) {
	tests := []struct {
		name    string
		csv     string
		wantLen int
		wantErr bool
	}{
		{
			name:    "valid config",
			csv:     validCSV,
			wantLen: 2,
		},
		{
			name: "ignores blank stop_id",
			csv: `stop_id,stop_name
8000244,Mannheim Hbf
,Ohne ID
`,
			wantLen: 1,
		},
		{
			name: "duplicate stop_id counted once",
			csv: `stop_id,stop_name
8000244,Mannheim Hbf
8000244,Mannheim Hbf (Dup)
`,
			wantLen: 1,
		},
		{
			name:    "missing stop_id column",
			csv:     "stop_name\nMannheim Hbf\n",
			wantErr: true,
		},
		{
			name:    "header only, no rows",
			csv:     "stop_id,stop_name\n",
			wantErr: true,
		},
		{
			name:    "empty input",
			csv:     "",
			wantErr: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			f, err := newFilterFromReader(strings.NewReader(tt.csv))
			if tt.wantErr {
				if err == nil {
					t.Fatalf("expected error, got nil")
				}
				return
			}
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			if f.Len() != tt.wantLen {
				t.Errorf("Len() = %d, want %d", f.Len(), tt.wantLen)
			}
		})
	}
}

func TestFilter_HasStop(t *testing.T) {
	f, err := newFilterFromReader(strings.NewReader(validCSV))
	if err != nil {
		t.Fatalf("newFilterFromReader: %v", err)
	}

	if !f.HasStop("8000244") {
		t.Error("HasStop(8000244) = false, want true")
	}
	if f.HasStop("9999999") {
		t.Error("HasStop(9999999) = true, want false")
	}
}

func TestFilter_TripInScope(t *testing.T) {
	f, err := newFilterFromReader(strings.NewReader(validCSV))
	if err != nil {
		t.Fatalf("newFilterFromReader: %v", err)
	}

	tests := []struct {
		name    string
		stopIDs []string
		want    bool
	}{
		{"no stops", nil, false},
		{"entirely outside", []string{"1", "2", "3"}, false},
		{"single stop inside", []string{"8000244"}, true},
		{
			name:    "long-distance train mostly outside, one stop inside",
			stopIDs: []string{"111", "222", "8000105", "333"},
			want:    true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := f.TripInScope(tt.stopIDs); got != tt.want {
				t.Errorf("TripInScope(%v) = %v, want %v", tt.stopIDs, got, tt.want)
			}
		})
	}
}

func TestLoadCSV(t *testing.T) {
	t.Run("missing file", func(t *testing.T) {
		if _, err := LoadCSV(filepath.Join(t.TempDir(), "does-not-exist.csv")); err == nil {
			t.Fatal("expected error for missing file, got nil")
		}
	})

	t.Run("real config file", func(t *testing.T) {
		path := filepath.Join(t.TempDir(), "scope_stops.csv")
		if err := os.WriteFile(path, []byte(validCSV), 0o644); err != nil {
			t.Fatalf("write test file: %v", err)
		}

		f, err := LoadCSV(path)
		if err != nil {
			t.Fatalf("LoadCSV: %v", err)
		}
		if f.Len() != 2 {
			t.Errorf("Len() = %d, want 2", f.Len())
		}
	})
}

// TestLoadCSVQuotedNameWithComma sichert den Fehler vom 2026-08-23 ab: die
// erzeugte Haltestellenliste wurde mit einem f-string statt mit einem
// CSV-Writer geschrieben, und 363 der Namen tragen selbst ein Komma
// ("Aglasterhausen, Bahnhof"). Der Collector startete daraufhin nicht mehr --
// gefangen erst vom Healthcheck im Deploy, nicht von einem Test.
func TestLoadCSVQuotedNameWithComma(t *testing.T) {
	inhalt := "stop_id,stop_name,stop_lat,stop_lon\n" +
		"123,\"Aglasterhausen, Bahnhof\",49.35,8.99\n" +
		"456,Mannheim Hbf,49.48,8.47\n"

	filter, err := newFilterFromReader(strings.NewReader(inhalt))
	if err != nil {
		t.Fatalf("Liste mit gequotetem Komma nicht ladbar: %v", err)
	}
	if filter.Len() != 2 {
		t.Errorf("Len() = %d, want 2", filter.Len())
	}
	if !filter.HasStop("123") {
		t.Error("der Halt mit Komma im Namen fehlt")
	}
}
