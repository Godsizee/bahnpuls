package health

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestFeedAge(t *testing.T) {
	now := time.Date(2026, 8, 10, 12, 0, 30, 0, time.UTC)

	tests := []struct {
		name          string
		feedTimestamp uint64
		want          time.Duration
	}{
		{
			name:          "30 seconds old",
			feedTimestamp: uint64(time.Date(2026, 8, 10, 12, 0, 0, 0, time.UTC).Unix()),
			want:          30 * time.Second,
		},
		{
			name:          "zero timestamp reports zero, not epoch age",
			feedTimestamp: 0,
			want:          0,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := FeedAge(tt.feedTimestamp, now); got != tt.want {
				t.Errorf("FeedAge() = %v, want %v", got, tt.want)
			}
		})
	}
}

func TestWriter_Write(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "heartbeat.json")
	w := NewWriter(path)

	hb := Heartbeat{
		PolledAt:      time.Date(2026, 8, 10, 12, 0, 30, 0, time.UTC),
		FeedTimestamp: 1786348520,
		FeedAgeSec:    30,
		EntityCount:   171147,
		InScopeCount:  412,
		ChangedCount:  57,
	}
	if err := w.Write(hb); err != nil {
		t.Fatalf("Write: %v", err)
	}

	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("ReadFile: %v", err)
	}
	var got Heartbeat
	if err := json.Unmarshal(raw, &got); err != nil {
		t.Fatalf("Unmarshal: %v", err)
	}
	if got.EntityCount != 171147 || got.InScopeCount != 412 || got.ChangedCount != 57 {
		t.Errorf("round-tripped heartbeat = %+v, unexpected", got)
	}
	if !got.PolledAt.Equal(hb.PolledAt) {
		t.Errorf("PolledAt = %v, want %v", got.PolledAt, hb.PolledAt)
	}

	// No leftover temp files after a successful write.
	entries, err := os.ReadDir(dir)
	if err != nil {
		t.Fatalf("ReadDir: %v", err)
	}
	if len(entries) != 1 || entries[0].Name() != "heartbeat.json" {
		t.Errorf("dir entries = %v, want exactly [heartbeat.json]", entries)
	}
}

func TestWriter_WriteCreatesMissingDir(t *testing.T) {
	path := filepath.Join(t.TempDir(), "nested", "heartbeat.json")
	w := NewWriter(path)

	if err := w.Write(Heartbeat{}); err != nil {
		t.Fatalf("Write: %v", err)
	}
	if _, err := os.Stat(path); err != nil {
		t.Errorf("heartbeat file not created: %v", err)
	}
}

func TestWriter_SecondWriteOverwrites(t *testing.T) {
	path := filepath.Join(t.TempDir(), "heartbeat.json")
	w := NewWriter(path)

	if err := w.Write(Heartbeat{EntityCount: 1}); err != nil {
		t.Fatalf("Write: %v", err)
	}
	if err := w.Write(Heartbeat{EntityCount: 2}); err != nil {
		t.Fatalf("Write: %v", err)
	}

	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("ReadFile: %v", err)
	}
	var got Heartbeat
	if err := json.Unmarshal(raw, &got); err != nil {
		t.Fatalf("Unmarshal: %v", err)
	}
	if got.EntityCount != 2 {
		t.Errorf("EntityCount = %d, want 2 (second write must overwrite)", got.EntityCount)
	}
}

func TestWriter_ErrorFieldOmittedWhenEmpty(t *testing.T) {
	path := filepath.Join(t.TempDir(), "heartbeat.json")
	w := NewWriter(path)
	if err := w.Write(Heartbeat{EntityCount: 1}); err != nil {
		t.Fatalf("Write: %v", err)
	}

	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("ReadFile: %v", err)
	}
	var m map[string]any
	if err := json.Unmarshal(raw, &m); err != nil {
		t.Fatalf("Unmarshal: %v", err)
	}
	if _, ok := m["error"]; ok {
		t.Error(`"error" key present in JSON despite empty Err field, want omitted`)
	}
}
