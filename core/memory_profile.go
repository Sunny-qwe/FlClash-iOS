package core

import (
	"core/diagnostics"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"runtime"
	"runtime/pprof"
	"sync/atomic"
	"time"
)

var memoryProfileBusy atomic.Bool

func RequestMemoryProfile(directory, runID, kind string) bool {
	if directory == "" || kind != "baseline" && kind != "pressure" || !memoryProfileBusy.CompareAndSwap(false, true) {
		return false
	}
	go func() {
		defer memoryProfileBusy.Store(false)
		err := writeMemoryProfile(directory, runID, kind)
		diagnostics.Record("memory.profile", map[string]any{"kind": kind, "failed": err != nil, "error": fmt.Sprint(err)})
	}()
	return true
}

type profileWriter struct {
	writer    io.Writer
	remaining int64
}

func (w *profileWriter) Write(data []byte) (int, error) {
	if int64(len(data)) > w.remaining {
		return 0, errors.New("memory profile exceeds size limit")
	}
	n, err := w.writer.Write(data)
	w.remaining -= int64(n)
	return n, err
}

func writeMemoryProfile(directory, runID, kind string) error {
	file, err := os.CreateTemp(directory, ".core-heap-*")
	if err != nil {
		return err
	}
	defer os.Remove(file.Name())
	// A forced collection here would erase the allocation spike being diagnosed.
	err = pprof.Lookup("heap").WriteTo(&profileWriter{writer: file, remaining: 2 << 20}, 0)
	closeErr := file.Close()
	if err != nil {
		return err
	}
	if closeErr != nil {
		return closeErr
	}
	target := filepath.Join(directory, "core-heap-"+kind+".pprof")
	_ = os.Remove(target + ".previous")
	if err = os.Rename(target, target+".previous"); err != nil && !os.IsNotExist(err) {
		return err
	}
	if err = os.Rename(file.Name(), target); err != nil {
		return err
	}
	metadata, err := json.Marshal(map[string]any{
		"id": runID, "kind": kind, "timestamp-ms": time.Now().UnixMilli(),
		"sampling-rate-bytes": runtime.MemProfileRate, "forced-gc": false,
	})
	if err != nil {
		return err
	}
	_ = os.Remove(target + ".json.previous")
	_ = os.Rename(target+".json", target+".json.previous")
	return os.WriteFile(target+".json", metadata, 0600)
}
