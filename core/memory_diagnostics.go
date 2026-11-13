package core

import (
	"core/diagnostics"
	"core/mitm"
	"encoding/json"
	"runtime"
	"runtime/debug"

	"github.com/metacubex/mihomo/tunnel/statistic"
)

func GetMemoryDiagnostics() string {
	var stats runtime.MemStats
	runtime.ReadMemStats(&stats)
	connections := 0
	statistic.DefaultManager.Range(func(statistic.Tracker) bool { connections++; return true })
	data, _ := json.Marshal(map[string]any{
		"heap-allocated-bytes":     stats.HeapAlloc,
		"heap-inuse-bytes":         stats.HeapInuse,
		"heap-idle-retained-bytes": stats.HeapIdle - stats.HeapReleased,
		"heap-released-bytes":      stats.HeapReleased,
		"stack-inuse-bytes":        stats.StackInuse,
		"runtime-other-bytes":      stats.MSpanInuse + stats.MCacheInuse + stats.BuckHashSys + stats.GCSys + stats.OtherSys,
		"gc-cycles":                stats.NumGC,
		"total-allocated-bytes":    stats.TotalAlloc,
		"next-gc-bytes":            stats.NextGC,
		"runtime-managed-bytes":    stats.Sys - stats.HeapReleased,
		"go-memory-limit-bytes":    debug.SetMemoryLimit(-1),
		"active-connections":       connections,
		"goroutines":               runtime.NumGoroutine(),
		"active-node-probes":       len(backgroundProbeSlots),
		"mitm":                     mitm.DiagnosticActivity(),
		"events":                   diagnostics.Snapshot(),
	})
	return string(data)
}
