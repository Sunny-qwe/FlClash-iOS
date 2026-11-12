package core

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/metacubex/mihomo/config"
	"github.com/metacubex/mihomo/constant"
)

func TestRoutingDigestIncludesEveryNonMitmInput(t *testing.T) {
	path := filepath.Join(t.TempDir(), "profile.yaml")
	if err := os.WriteFile(path, []byte("rules: [MATCH,DIRECT]\n"), 0600); err != nil {
		t.Fatal(err)
	}
	base := &SetupBase{Path: path, Overlay: "dns: {enable: true}\nrules: []\nmitm: {enable: false}\n"}
	want, ok := routingDigest(base)
	if !ok {
		t.Fatal("missing digest")
	}
	for _, overlay := range []string{
		"mitm: {enable: true, hostname: [example.com]}\nrules: []\ndns: {enable: true}\n",
		"dns: {enable: true}\nrules: []\n",
	} {
		got, ok := routingDigest(&SetupBase{Path: path, Overlay: overlay})
		if !ok || got != want {
			t.Fatal("MITM-only edit or mapping order invalidated routing")
		}
	}
	for _, overlay := range []string{
		"dns: {enable: false}\nrules: []\n",
		"dns: {enable: true}\nrules: ['DOMAIN,ads.example,REJECT']\n",
		"dns: {enable: true}\nrules: []\nproxy-providers: {new: {type: http, url: 'https://example.com/sub'}}\n",
	} {
		got, ok := routingDigest(&SetupBase{Path: path, Overlay: overlay})
		if !ok || got == want {
			t.Fatal("changed routing input was ignored")
		}
	}
	if err := os.WriteFile(path, []byte("rules: [MATCH,REJECT]\n"), 0600); err != nil {
		t.Fatal(err)
	}
	if got, ok := routingDigest(base); !ok || got == want {
		t.Fatal("profile content update was ignored")
	}
	if _, ok := routingDigest(nil); ok {
		t.Fatal("profile without base reused routing")
	}
}

func TestModuleOnlyApplyPreservesLiveConfiguration(t *testing.T) {
	home := t.TempDir()
	oldHome, oldReuse := constant.Path.HomeDir(), reuseModuleConfiguration
	oldDigest, oldValid := appliedRoutingDigest, appliedRoutingDigestValid
	oldEngine := mitmEngine.Load()
	constant.SetHomeDir(home)
	reuseModuleConfiguration = true
	t.Cleanup(func() {
		if engine := mitmEngine.Swap(oldEngine); engine != nil && engine != oldEngine {
			engine.Close()
		}
		constant.SetHomeDir(oldHome)
		reuseModuleConfiguration = oldReuse
		appliedRoutingDigest, appliedRoutingDigestValid = oldDigest, oldValid
	})
	live := &config.Config{}
	withCurrentConfig(t, live)
	path := filepath.Join(home, "profile.yaml")
	if err := os.WriteFile(path, []byte("rules: ['MATCH,DIRECT']\n"), 0600); err != nil {
		t.Fatal(err)
	}
	base := &SetupBase{Path: path, Overlay: "mitm: {enable: false}\n"}
	appliedRoutingDigest, appliedRoutingDigestValid = routingDigest(base)
	base.Overlay = "mitm: {enable: true, hostname: [example.com], url-rewrite: ['^https://example.com/ad reject']}\n"
	if err := applyConfig(&SetupParams{Base: base}); err != nil {
		t.Fatal(err)
	}
	if currentConfig != live || !mitmEngine.Load().Matches("example.com") {
		t.Fatal("module edit rebuilt live routing or did not activate")
	}
	data, err := os.ReadFile(runningConfigPath())
	if err != nil || len(data) == 0 {
		t.Fatal("module configuration was not persisted")
	}
	active := mitmEngine.Load()
	base.Overlay = "mitm: {enable: true, decrypt-tls: true, ca-fingerprint: missing}\n"
	if err := applyConfig(&SetupParams{Base: base}); err == nil {
		t.Fatal("invalid MITM certificate was accepted")
	}
	if currentConfig != live || mitmEngine.Load() != active {
		t.Fatal("rejected module edit replaced the live configuration")
	}
	after, _ := os.ReadFile(runningConfigPath())
	if string(after) != string(data) {
		t.Fatal("rejected module edit changed persisted configuration")
	}
}

func TestIOSConfigKeepsInProcessDNSWithoutBindingAPort(t *testing.T) {
	cfg := &config.Config{DNS: &config.DNS{Enable: true, Listen: "0.0.0.0:1053"}}
	applyIOSConfigLimits(cfg)
	if !cfg.DNS.Enable || cfg.DNS.Listen != "" {
		t.Fatal("iOS DNS should resolve in-process without an external listener")
	}
}
