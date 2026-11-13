package core

import (
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
		"mitm":                     mitm.DiagnosticActivity(),
	})
	return string(data)
}
