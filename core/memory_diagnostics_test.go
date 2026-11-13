package core

import (
	"encoding/json"
	"testing"
)

func TestMemoryDiagnosticsIncludesRuntimeAndMITM(t *testing.T) {
	var snapshot map[string]any
	if err := json.Unmarshal([]byte(GetMemoryDiagnostics()), &snapshot); err != nil {
		t.Fatal(err)
	}
	if snapshot["heap-allocated-bytes"].(float64) <= 0 || snapshot["goroutines"].(float64) < 1 {
		t.Fatal(snapshot)
	}
	activity := snapshot["mitm"].(map[string]any)
	for _, name := range []string{"active-sessions", "active-scripts", "active-bodies"} {
		if count, ok := activity[name].(float64); !ok || count < 0 {
			t.Fatal(activity)
		}
	}
}
