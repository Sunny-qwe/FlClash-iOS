package core

import (
	"fmt"
	"os"
	"path/filepath"
	"runtime/debug"
	"time"
)

func configureCrashOutput(home string) error {
	path := filepath.Join(home, "core-crash.log")
	if info, err := os.Stat(path); err == nil && info.Size() >= 1<<20 {
		if err := os.Rename(path, path+".previous"); err != nil {
			return err
		}
	}
	file, err := os.OpenFile(path, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0600)
	if err != nil {
		return err
	}
	defer file.Close()
	if _, err := fmt.Fprintf(file, "\nNECore start: %s\n", time.Now().Format(time.RFC3339)); err != nil {
		return err
	}
	return debug.SetCrashOutput(file, debug.CrashOptions{})
}
