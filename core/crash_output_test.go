package core

import (
	"bytes"
	"os"
	"os/exec"
	"path/filepath"
	"testing"
)

func TestCrashOutputPreservesFatalStack(t *testing.T) {
	if home := os.Getenv("FLCLASH_TEST_CRASH_HOME"); home != "" {
		if err := configureCrashOutput(home); err != nil {
			os.Exit(2)
		}
		go func() { panic("flclash-crash-output-fixture") }()
		select {}
	}
	home := t.TempDir()
	path := filepath.Join(home, "core-crash.log")
	if err := os.WriteFile(path, []byte("prior-report\n"), 0600); err != nil {
		t.Fatal(err)
	}
	command := exec.Command(os.Args[0], "-test.run=^TestCrashOutputPreservesFatalStack$")
	command.Env = append(os.Environ(), "FLCLASH_TEST_CRASH_HOME="+home)
	if err := command.Run(); err == nil {
		t.Fatal("fixture did not crash")
	}
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	for _, text := range []string{"prior-report", "flclash-crash-output-fixture", "crash_output_test.go"} {
		if !bytes.Contains(data, []byte(text)) {
			t.Fatalf("crash report missing %q", text)
		}
	}
}
