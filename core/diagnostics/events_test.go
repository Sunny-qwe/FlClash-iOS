package diagnostics

import (
	"strings"
	"testing"
)

func TestJournalKeepsLatestBoundedEvents(t *testing.T) {
	fields := map[string]any{"name": strings.Repeat("x", 1000)}
	for index := 0; index < 200; index++ {
		Record("script", fields)
	}
	fields["name"] = "changed after recording"
	events := Snapshot()
	if len(events) != 128 {
		t.Fatal(len(events))
	}
	for index, event := range events {
		if len(event.Details["name"].(string)) != 160 {
			t.Fatal(event)
		}
		if index > 0 && event.Sequence != events[index-1].Sequence+1 {
			t.Fatal(events)
		}
	}
}
