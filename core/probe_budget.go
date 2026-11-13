package core

import (
	"context"

	"github.com/metacubex/mihomo/adapter"
	"github.com/metacubex/mihomo/constant/features"
)

var backgroundProbeSlots = make(slots, 2)

func init() {
	if features.WithLowMemory {
		adapter.UrlTestAcquireHook = acquireProbeSlot
	}
}

func acquireProbeSlot(ctx context.Context) (func(), error) {
	select {
	case backgroundProbeSlots <- struct{}{}:
		if err := ctx.Err(); err != nil {
			backgroundProbeSlots.release()
			return nil, err
		}
		return backgroundProbeSlots.release, nil
	case <-ctx.Done():
		return nil, ctx.Err()
	}
}
