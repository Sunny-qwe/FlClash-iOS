//go:build ios && with_low_memory

package mobile

import "runtime/debug"

func init() {
	// The extension's jetsam budget also includes Swift, stacks and native pages.
	debug.SetMemoryLimit(16 << 20)
	debug.SetGCPercent(20)
}
