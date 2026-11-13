package core

import (
	"strings"
	"testing"

	"github.com/metacubex/mihomo/adapter/provider"
	"github.com/metacubex/mihomo/tunnel"
	"go.yaml.in/yaml/v3"
)

func TestPreparedProviderRetainsRealityCompatibility(t *testing.T) {
	source := strings.ReplaceAll(realityCompatProfile, `"0123"`, "001234")
	raw, err := unmarshalRawConfig([]byte(source))
	if err != nil {
		t.Fatal(err)
	}
	data, err := yaml.Marshal(map[string]any{"proxies": raw.Proxy})
	if err != nil {
		t.Fatal(err)
	}
	var document struct {
		Proxies []map[string]any `yaml:"proxies"`
	}
	if err := yaml.Unmarshal(data, &document); err != nil {
		t.Fatal(err)
	}
	loaded, err := provider.ParseProxyProvider("subscription", map[string]any{"type": "inline", "payload": document.Proxies}, tunnel.Tunnel)
	if err != nil {
		t.Fatal(err)
	}
	if loaded.Count() != 1 {
		t.Fatalf("normalized subscription: %v", loaded.Proxies())
	}
	reality := document.Proxies[0]["reality-opts"].(map[string]any)
	if reality["short-id"] != "001234" || document.Proxies[0]["tls"] != true {
		t.Fatal(document)
	}
}
