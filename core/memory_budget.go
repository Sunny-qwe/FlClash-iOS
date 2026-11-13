package core

import (
	"core/mitm"
	"runtime"
	"runtime/debug"

	"github.com/metacubex/mihomo/constant/features"
)

func ReportMemoryFootprint(bytes int64) {
	if !features.WithLowMemory || bytes <= 0 {
		return
	}
	mitm.ReportMemoryFootprint(bytes)
	var stats runtime.MemStats
	runtime.ReadMemStats(&stats)
	managed := int64(stats.Sys - stats.HeapReleased)
	native := max(bytes-managed, 0)
	debug.SetMemoryLimit(max(8<<20, min(16<<20, (36<<20)-native)))
}
