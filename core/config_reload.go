package core

import (
	"crypto/sha256"
	"encoding/json"
	"errors"
	"io"
	"os"
	"runtime"

	"github.com/metacubex/mihomo/log"
	"go.yaml.in/yaml/v3"
)

var reuseModuleConfiguration = runtime.GOOS == "ios"
var appliedRoutingDigest [sha256.Size]byte
var appliedRoutingDigestValid bool

// The profile bytes and every overlay field except MITM must be unchanged before
// reusing live providers. Rules contributed by modules remain part of the digest.
func routingDigest(base *SetupBase) ([sha256.Size]byte, bool) {
	var zero [sha256.Size]byte
	if base == nil {
		return zero, false
	}
	var overlay map[string]any
	if err := yaml.Unmarshal([]byte(base.Overlay), &overlay); err != nil {
		return zero, false
	}
	delete(overlay, "mitm")
	encoded, err := json.Marshal(overlay)
	if err != nil {
		return zero, false
	}
	file, err := os.Open(base.Path)
	if err != nil {
		return zero, false
	}
	defer file.Close()
	hash := sha256.New()
	if _, err := io.Copy(hash, file); err != nil {
		return zero, false
	}
	hash.Write([]byte{0})
	hash.Write(encoded)
	var digest [sha256.Size]byte
	copy(digest[:], hash.Sum(nil))
	return digest, true
}

func applyModuleConfiguration(params *SetupParams) error {
	engine, err := prepareMitm(params.Base)
	if err != nil {
		return &MethodError{Code: "config_preserved", Message: err.Error()}
	}
	document, err := mergeProfileBase(params.Base)
	if err == nil {
		if digest, ok := routingDigest(params.Base); !ok || digest != appliedRoutingDigest {
			err = errors.New("profile changed during module update; retry applying the profile")
		}
	}
	if err == nil {
		err = writeConfigDocument(runningConfigPath(), document)
	}
	if err != nil {
		if engine != mitmEngine.Load() {
			engine.Close()
		}
		return &MethodError{Code: "config_preserved", Message: err.Error()}
	}
	applyOptions(params.Options)
	activateMitm(engine)
	patchSelectGroup(params.SelectedMap)
	bumpRouteEpoch()
	releaseLoadMemory()
	log.Infoln("MITM configuration updated without reloading routing")
	scheduleLoadMemoryRelease()
	return nil
}
