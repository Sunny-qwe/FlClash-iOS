package core

import (
	"bytes"
	"compress/gzip"
	"encoding/json"
	"io"
	"os"
	"path/filepath"
	"testing"
)

func TestMemoryProfileIsBoundedAndPreservesPreviousRun(t *testing.T) {
	directory := t.TempDir()
	path := filepath.Join(directory, "core-heap-baseline.pprof")
	if err := writeMemoryProfile(directory, "first", "baseline"); err != nil {
		t.Fatal(err)
	}
	file, err := os.Open(path)
	if err != nil {
		t.Fatal(err)
	}
	reader, err := gzip.NewReader(file)
	if err != nil {
		t.Fatal(err)
	}
	size, err := io.Copy(io.Discard, reader)
	reader.Close()
	file.Close()
	if err != nil || size == 0 {
		t.Fatal(size, err)
	}
	if err := writeMemoryProfile(directory, "second", "baseline"); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(path + ".previous"); err != nil {
		t.Fatal(err)
	}
	data, err := os.ReadFile(path + ".json.previous")
	if err != nil {
		t.Fatal(err)
	}
	var metadata map[string]any
	if err := json.Unmarshal(data, &metadata); err != nil {
		t.Fatal(err)
	}
	if metadata["id"] != "first" || metadata["forced-gc"] != false {
		t.Fatal(metadata)
	}
	var output bytes.Buffer
	writer := profileWriter{writer: &output, remaining: 2}
	if _, err := writer.Write([]byte("oversized")); err == nil || output.Len() != 0 {
		t.Fatal("profile size bound was ignored")
	}
	if RequestMemoryProfile(directory, "test", "../../untrusted") {
		t.Fatal("accepted an unknown profile kind")
	}
}
