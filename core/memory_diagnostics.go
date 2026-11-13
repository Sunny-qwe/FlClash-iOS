package core

import (
	"core/diagnostics"
	"core/mitm"
	"encoding/json"
	"runtime"
)

func GetMemoryDiagnostics() string {
	var stats runtime.MemStats
	runtime.ReadMemStats(&stats)
	data, _ := json.Marshal(map[string]any{
		"heap-allocated-bytes":     stats.HeapAlloc,
		"heap-inuse-bytes":         stats.HeapInuse,
		"heap-idle-retained-bytes": stats.HeapIdle - stats.HeapReleased,
		"heap-released-bytes":      stats.HeapReleased,
		"stack-inuse-bytes":        stats.StackInuse,
		"runtime-other-bytes":      stats.MSpanInuse + stats.MCacheInuse + stats.BuckHashSys + stats.GCSys + stats.OtherSys,
		"gc-cycles":                stats.NumGC,
		"goroutines":               runtime.NumGoroutine(),
		"active-node-probes":       len(backgroundProbeSlots),
		"mitm":                     mitm.DiagnosticActivity(),
		"events":                   diagnostics.Snapshot(),
	})
	return string(data)
}
