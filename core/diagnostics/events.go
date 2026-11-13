package diagnostics

import (
	"strings"
	"sync"
	"time"
)

type Event struct {
	Sequence  uint64         `json:"sequence"`
	Timestamp int64          `json:"timestamp-ms"`
	Kind      string         `json:"kind"`
	Details   map[string]any `json:"details,omitempty"`
}

var journal struct {
	sync.Mutex
	events   [128]Event
	sequence uint64
	count    int
}

func Record(kind string, details map[string]any) {
	bounded := make(map[string]any, min(len(details), 8))
	for key, value := range details {
		if len(bounded) == 8 {
			break
		}
		if text, ok := value.(string); ok {
			if len(text) > 160 {
				text = text[:160]
			}
			value = strings.Clone(text)
		}
		bounded[key] = value
	}
	journal.Lock()
	defer journal.Unlock()
	journal.events[journal.sequence%uint64(len(journal.events))] = Event{
		Sequence: journal.sequence + 1, Timestamp: time.Now().UnixMilli(),
		Kind: kind, Details: bounded,
	}
	journal.sequence++
	journal.count = min(journal.count+1, len(journal.events))
}

func Snapshot() []Event {
	journal.Lock()
	defer journal.Unlock()
	result := make([]Event, journal.count)
	start := journal.sequence - uint64(journal.count)
	for index := range result {
		result[index] = journal.events[(start+uint64(index))%uint64(len(journal.events))]
	}
	return result
}
