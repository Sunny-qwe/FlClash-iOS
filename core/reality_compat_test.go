package core

import (
	"errors"
	"os"
	"path/filepath"
	"testing"

	"github.com/metacubex/mihomo/config"
	"github.com/metacubex/mihomo/constant"
)

const realityCompatProfile = `proxies:
  - name: reality
    type: vless
    server: 127.0.0.1
    port: 443
    uuid: 2a70e3a9-b4ce-4f20-908d-e99950a0a611
    servername: example.com
    reality-opts:
      public-key: SbVKOEMjK0sIlbwg4akyBg5mL5KZwwB-ed4eEE7YnRc
      short-id: "0123"
proxy-groups:
  - {name: Proxy, type: select, proxies: [reality]}
rules: ["MATCH,Proxy"]
`

func TestRealityCompatibilityFillsOnlyMissingFields(t *testing.T) {
	raw, err := unmarshalRawConfig([]byte(`defaults: &defaults
  type: vless
  reality-opts: {public-key: key}
proxies:
  - {<<: *defaults, name: missing}
  - {<<: *defaults, name: explicit, tls: false, client-fingerprint: firefox}
  - {<<: *defaults, name: nulls, tls: null, client-fingerprint: ""}
  - {name: plain, type: vless}
  - {name: empty-reality, type: vless, reality-opts: {}}
  - {name: other, type: socks5, reality-opts: {public-key: key}}
`))
	if err != nil {
		t.Fatal(err)
	}
	for _, index := range []int{0, 2} {
		if raw.Proxy[index]["tls"] != true || raw.Proxy[index]["client-fingerprint"] != "chrome" {
			t.Errorf("proxy %d did not receive the missing REALITY fields", index)
		}
	}
	if raw.Proxy[1]["tls"] != false || raw.Proxy[1]["client-fingerprint"] != "firefox" {
		t.Error("explicit settings were overwritten")
	}
	for _, index := range []int{3, 4, 5} {
		if _, exists := raw.Proxy[index]["tls"]; exists {
			t.Errorf("proxy %d without supported REALITY was changed", index)
		}
	}
}

func TestRealityCompatibilityLoadsDirectAndMergedProfiles(t *testing.T) {
	dir := t.TempDir()
	profilePath := filepath.Join(dir, "subscription.yaml")
	if err := os.WriteFile(profilePath, []byte(realityCompatProfile), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := loadConfig(profilePath); err != nil {
		t.Fatalf("direct subscription: %v", err)
	}
	runningPath := filepath.Join(dir, "config.yaml")
	base := &SetupBase{Path: profilePath, Overlay: "mixed-port: 0\nrules: []\n"}
	if _, err := loadConfigWithBase(base, runningPath); err != nil {
		t.Fatalf("merged subscription: %v", err)
	}
	data, err := os.ReadFile(runningPath)
	if err != nil {
		t.Fatal(err)
	}
	raw, err := config.UnmarshalRawConfig(data)
	if err != nil {
		t.Fatal(err)
	}
	if raw.Proxy[0]["tls"] != true || raw.Proxy[0]["client-fingerprint"] != "chrome" {
		t.Fatal("persisted VPN configuration lost REALITY compatibility fields")
	}
	if _, err := config.Parse(data); err != nil {
		t.Fatalf("persisted config cannot be reloaded by the upstream parser: %v", err)
	}
}

func TestRejectedSwitchPreservesRunningConfigAndFile(t *testing.T) {
	home := t.TempDir()
	previousHome := constant.Path.HomeDir()
	constant.SetHomeDir(home)
	t.Cleanup(func() { constant.SetHomeDir(previousHome) })
	previous := &config.Config{}
	withCurrentConfig(t, previous)
	path := filepath.Join(home, "config.yaml")
	const previousContents = "mixed-port: 7890\n"
	if err := os.WriteFile(path, []byte(previousContents), 0o600); err != nil {
		t.Fatal(err)
	}
	profilePath := filepath.Join(home, "invalid.yaml")
	if err := os.WriteFile(profilePath, []byte("proxies: [{name: invalid, type: unknown}]\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	err := applyConfig(&SetupParams{Base: &SetupBase{Path: profilePath, Overlay: "rules: []\n"}})
	var methodErr *MethodError
	if !errors.As(err, &methodErr) || methodErr.Code != "config_preserved" {
		t.Fatalf("rejected switch returned %v", err)
	}
	if currentConfig != previous {
		t.Fatal("a rejected switch replaced the active configuration")
	}
	data, err := os.ReadFile(path)
	if err != nil || string(data) != previousContents {
		t.Fatalf("rejected switch replaced the startup configuration: %v", err)
	}
}
