package core

import (
	"os"
	"path/filepath"
	"runtime/debug"
)

func configureCrashOutput(home string) error {
	path := filepath.Join(home, "core-crash.log")
	if info, err := os.Stat(path); err == nil && info.Size() > 0 {
		if err := os.Rename(path, path+".previous"); err != nil {
			return err
		}
	}
	file, err := os.OpenFile(path, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0600)
	if err != nil {
		return err
	}
	defer file.Close()
	return debug.SetCrashOutput(file, debug.CrashOptions{})
}
