package mitm

import (
	"bufio"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"
	"time"
)

func TestReconfigureKeepsLiveModuleConnections(t *testing.T) {
	home := t.TempDir()
	cfg := Config{Enable: true, Rules: Rules{Hostname: []string{"api.example"}, URLRewrite: []string{`^http://api\.example/ reject-dict`}}}
	for i := range 1000 {
		cfg.URLRewrite = append(cfg.URLRewrite, fmt.Sprintf(`^https://other%d\.example/ad reject`, i))
	}
	engine, err := New(home, cfg, nil, nil)
	if err != nil {
		t.Fatal(err)
	}
	defer engine.Close()
	engine.SetCapture(true)
	client, server := net.Pipe()
	defer client.Close()
	finished := make(chan struct{})
	go func() { defer close(finished); defer server.Close(); engine.Serve(server, "api.example", 80, "reload") }()
	_ = client.SetDeadline(time.Now().Add(5 * time.Second))
	reader := bufio.NewReader(client)
	request := func(want string) {
		t.Helper()
		if _, err := fmt.Fprint(client, "GET /ad HTTP/1.1\r\nHost: api.example\r\n\r\n"); err != nil {
			t.Fatal(err)
		}
		response, err := http.ReadResponse(reader, nil)
		if err != nil {
			t.Fatal(err)
		}
		body, err := io.ReadAll(response.Body)
		response.Body.Close()
		if err != nil || string(body) != want {
			t.Fatalf("body = %q, %v", body, err)
		}
	}
	request("{}")
	for range 50 {
		reloaded, err := Reconfigure(engine, home, cfg, nil, nil)
		if err != nil || reloaded != engine {
			t.Fatalf("unchanged module rebuilt: %v", err)
		}
		request("{}")
	}
	if !engine.Exchanges("").Capturing {
		t.Fatal("configuration reload disabled capture")
	}
	changed := cfg
	changed.URLRewrite = []string{`^http://api\.example/ reject-array`}
	replacement, err := Reconfigure(engine, home, changed, nil, nil)
	if err != nil || replacement == engine {
		t.Fatalf("changed module was not applied: %v", err)
	}
	defer replacement.Close()
	recorder := httptest.NewRecorder()
	replacement.serveHTTP(recorder, httptest.NewRequest("GET", "http://api.example/ad", nil), "api.example", 80, "changed")
	if recorder.Body.String() != "[]" {
		t.Fatalf("changed rule response = %q", recorder.Body.String())
	}
	engine.Close()
	select {
	case <-finished:
	case <-time.After(time.Second):
		t.Fatal("retired module retained its connection and rules")
	}
	if _, err := client.Read(make([]byte, 1)); err == nil {
		t.Fatal("retired module connection remained open")
	}
}

func TestReconfigureRevalidatesCertificate(t *testing.T) {
	home := t.TempDir()
	ca, err := GenerateCertificate(home)
	if err != nil {
		t.Fatal(err)
	}
	cfg := Config{Enable: true, DecryptTLS: true, CAFingerprint: ca.Fingerprint}
	engine, err := New(home, cfg, nil, nil)
	if err != nil {
		t.Fatal(err)
	}
	defer engine.Close()
	if next, err := Reconfigure(engine, home, cfg, nil, nil); err != nil || next != engine {
		t.Fatalf("valid certificate reload = %v", err)
	}
	if err := os.Remove(certificatePath(home)); err != nil {
		t.Fatal(err)
	}
	if _, err := Reconfigure(engine, home, cfg, nil, nil); err == nil {
		t.Fatal("removed certificate reused old authority")
	}
	newCA, err := GenerateCertificate(home)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := Reconfigure(engine, home, cfg, nil, nil); err == nil {
		t.Fatal("changed certificate bypassed trust validation")
	}
	cfg.CAFingerprint = newCA.Fingerprint
	next, err := Reconfigure(engine, home, cfg, nil, nil)
	if err != nil {
		t.Fatal(err)
	}
	defer next.Close()
	if next == engine || describeAuthority(next.ca).Fingerprint != newCA.Fingerprint {
		t.Fatal("new trusted authority was not applied")
	}
}
