package core

import (
	"core/mitm"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/metacubex/mihomo/config"
	C "github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/tunnel"
)

func TestMITMUpstreamUsesAppliedRoutingRules(t *testing.T) {
	home := t.TempDir()
	previousHome := C.Path.HomeDir()
	previousConfig := currentConfig
	previousEngine := mitmEngine.Load()
	previousStatus := tunnel.Status()
	previousMode := tunnel.Mode()
	previousProxies := tunnel.Proxies()
	previousRules := tunnel.Rules()
	t.Cleanup(func() {
		if e := mitmEngine.Swap(previousEngine); e != nil {
			e.CloseIdle()
		}
		currentConfig = previousConfig
		C.SetHomeDir(previousHome)
		tunnel.SetMode(previousMode)
		tunnel.UpdateProxies(previousProxies, nil)
		tunnel.UpdateRules(previousRules, nil, nil)
		if previousStatus == tunnel.Running {
			tunnel.OnRunning()
		} else {
			tunnel.OnSuspend()
		}
	})
	C.SetHomeDir(home)
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { io.WriteString(w, "routed-through-core") }))
	defer upstream.Close()
	_, port, _ := net.SplitHostPort(upstream.Listener.Addr().String())
	yamlText := "mode: rule\nproxies: []\nproxy-groups: []\nrules:\n  - DOMAIN,blocked.example,REJECT\n  - MATCH,DIRECT\n"
	if err := os.WriteFile(filepath.Join(home, "config.yaml"), []byte(yamlText), 0600); err != nil {
		t.Fatal(err)
	}
	cfg, err := loadConfig(filepath.Join(home, "config.yaml"))
	if err != nil {
		t.Fatal(err)
	}
	tunnel.SetMode(tunnel.Rule)
	tunnel.UpdateProxies(cfg.Proxies, nil)
	tunnel.UpdateRules(cfg.Rules, nil, nil)
	tunnel.OnRunning()
	transport := &http.Transport{DialContext: dialMitm}
	defer transport.CloseIdleConnections()
	client := &http.Client{Transport: transport, Timeout: time.Second}
	response, err := client.Get(upstream.URL)
	if err != nil {
		t.Fatal(err)
	}
	data, _ := io.ReadAll(response.Body)
	response.Body.Close()
	if string(data) != "routed-through-core" {
		t.Fatal(string(data))
	}
	if response, err := client.Get("http://blocked.example:" + port); err == nil {
		response.Body.Close()
		t.Fatal("MITM upstream bypassed REJECT rule")
	}
}

func TestMITMPreparationFailurePreservesAppliedEngine(t *testing.T) {
	home := t.TempDir()
	previousHome := C.Path.HomeDir()
	previousConfig := currentConfig
	previousEngine := mitmEngine.Load()
	t.Cleanup(func() { C.SetHomeDir(previousHome); currentConfig = previousConfig; mitmEngine.Store(previousEngine) })
	C.SetHomeDir(home)
	existing, _ := mitm.New(home, mitm.Config{}, nil, nil)
	mitmEngine.Store(existing)
	currentConfig = &config.Config{}
	if err := os.WriteFile(filepath.Join(home, "config.yaml"), []byte("mode: rule\nrules: ['MATCH,DIRECT']\nmitm:\n  enable: true\n  decrypt-tls: true\n"), 0600); err != nil {
		t.Fatal(err)
	}
	err := applyConfig(&SetupParams{})
	if err == nil || asMethodError(err).Code != "config_preserved" {
		t.Fatalf("error = %v", err)
	}
	if mitmEngine.Load() != existing {
		t.Fatal("rejected MITM config replaced working engine")
	}
}
