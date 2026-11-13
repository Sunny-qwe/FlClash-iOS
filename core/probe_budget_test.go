package core

import (
	"context"
	"errors"
	"testing"

	"github.com/metacubex/mihomo/adapter"
)

func TestProbeBudgetCancellationDoesNotConsumeSlot(t *testing.T) {
	releases := []func(){}
	for i := 0; i < cap(backgroundProbeSlots); i++ {
		release, err := acquireProbeSlot(context.Background())
		if err != nil {
			t.Fatal(err)
		}
		releases = append(releases, release)
	}
	defer func() {
		for _, release := range releases {
			release()
		}
	}()
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	release, err := acquireProbeSlot(ctx)
	if release != nil || !errors.Is(err, context.Canceled) {
		t.Fatalf("queued probe: release=%v error=%v", release != nil, err)
	}
	if len(backgroundProbeSlots) != cap(backgroundProbeSlots) {
		t.Fatal("cancelled probe changed slot ownership")
	}
}

func TestQueuedProbeDoesNotOverwriteNodeHistory(t *testing.T) {
	previous := adapter.UrlTestAcquireHook
	adapter.UrlTestAcquireHook = func(ctx context.Context) (func(), error) { return nil, context.Canceled }
	defer func() { adapter.UrlTestAcquireHook = previous }()
	proxy, err := adapter.ParseProxy(map[string]any{"name": "queued", "type": "direct"})
	if err != nil {
		t.Fatal(err)
	}
	_, err = proxy.URLTest(context.Background(), "https://example.com", nil)
	if !errors.Is(err, context.Canceled) {
		t.Fatal(err)
	}
	if len(proxy.DelayHistory()) != 0 {
		t.Fatal("waiting for a slot published a false unreachable measurement")
	}
}

func TestProbeBudgetReusesSlotBeforeStartingTimeout(t *testing.T) {
	previous := adapter.UrlTestAcquireHook
	adapter.UrlTestAcquireHook = acquireProbeSlot
	defer func() { adapter.UrlTestAcquireHook = previous }()
	ctx, release, err := adapter.AcquireURLTestSlot(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	defer release()
	probeCtx, cancel := context.WithCancel(ctx)
	defer cancel()
	_, nestedRelease, err := adapter.AcquireURLTestSlot(probeCtx)
	if err != nil {
		t.Fatal(err)
	}
	nestedRelease()
	if len(backgroundProbeSlots) != 1 {
		t.Fatalf("a queued health check acquired more than one slot: %d", len(backgroundProbeSlots))
	}
}
