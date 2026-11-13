package mitm

import (
	"strings"
	"testing"
	"time"

	"github.com/dop251/goja"
	"github.com/metacubex/mihomo/constant/features"
)

func TestMemoryPressureInterruptsOnlyTheActiveScript(t *testing.T) {
	if !features.WithLowMemory {
		t.Skip("iOS low memory policy")
	}
	defer ReportMemoryFootprint(0)
	ReportMemoryFootprint(35 << 20)
	if !scriptMemoryAvailable() {
		t.Fatal("script blocked with available headroom")
	}
	ReportMemoryFootprint(36 << 20)
	if scriptMemoryAvailable() {
		t.Fatal("new script allowed above memory threshold")
	}
	vm := goja.New()
	activeScript.Store(vm)
	defer activeScript.CompareAndSwap(vm, nil)
	done := make(chan error, 1)
	go func() { _, err := vm.RunString("for (;;) {}"); done <- err }()
	ReportMemoryFootprint(40 << 20)
	select {
	case err := <-done:
		if err == nil || !strings.Contains(err.Error(), "memory pressure") {
			t.Fatal(err)
		}
	case <-time.After(time.Second):
		vm.Interrupt("test cleanup")
		<-done
		t.Fatal("script did not yield on memory pressure")
	}
	ReportMemoryFootprint(30 << 20)
	if !scriptMemoryAvailable() || sessionConcurrency() != 4 {
		t.Fatal("memory recovery or session limit incorrect")
	}
}
