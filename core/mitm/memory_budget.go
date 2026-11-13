package mitm

import (
	"sync/atomic"

	"github.com/dop251/goja"
	"github.com/metacubex/mihomo/constant/features"
)

var processFootprint atomic.Int64
var activeScript atomic.Pointer[goja.Runtime]
var memorySkippedScripts atomic.Uint64

func ReportMemoryFootprint(bytes int64) {
	processFootprint.Store(bytes)
	if features.WithLowMemory && bytes >= 40<<20 {
		if vm := activeScript.Load(); vm != nil {
			vm.Interrupt("script stopped: VPN memory pressure")
		}
	}
}

func scriptMemoryAvailable() bool {
	return !features.WithLowMemory || processFootprint.Load() < 36<<20
}

func sessionConcurrency() int {
	if features.WithLowMemory {
		return 4
	}
	return 16
}
