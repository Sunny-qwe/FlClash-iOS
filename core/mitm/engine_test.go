package mitm

import (
	"context"
	"crypto/tls"
	"crypto/x509"
	"encoding/pem"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestCertificateRegenerationSignsRealLeaf(t *testing.T) {
	home := t.TempDir()
	if ca, err := GetCertificate(home); err != nil || ca != nil {
		t.Fatalf("missing CA = %v, %v", ca, err)
	}
	first, err := GenerateCertificate(home)
	if err != nil {
		t.Fatal(err)
	}
	leafPEM, err := IssueCertificate(home, "mitm-check.flclash.invalid")
	if err != nil {
		t.Fatal(err)
	}
	block, _ := pem.Decode([]byte(leafPEM))
	leaf, err := x509.ParseCertificate(block.Bytes)
	if err != nil {
		t.Fatal(err)
	}
	roots := x509.NewCertPool()
	roots.AppendCertsFromPEM([]byte(first.PEM))
	if _, err := leaf.Verify(x509.VerifyOptions{Roots: roots, DNSName: "mitm-check.flclash.invalid"}); err != nil {
		t.Fatal(err)
	}
	loaded, err := GetCertificate(home)
	if err != nil || loaded.Fingerprint != first.Fingerprint {
		t.Fatal("CA did not persist", err)
	}
	second, err := GenerateCertificate(home)
	if err != nil {
		t.Fatal(err)
	}
	if first.PEM == second.PEM || first.Fingerprint == second.Fingerprint {
		t.Fatal("regenerate reused the old keypair")
	}
	newRoots := x509.NewCertPool()
	newRoots.AppendCertsFromPEM([]byte(second.PEM))
	if _, err := leaf.Verify(x509.VerifyOptions{Roots: newRoots, DNSName: "mitm-check.flclash.invalid"}); err == nil {
		t.Fatal("old leaf trusts regenerated CA")
	}
}

func TestHTTPSRewriteScriptAndCapture(t *testing.T) {
	home := t.TempDir()
	ca, err := GenerateCertificate(home)
	if err != nil {
		t.Fatal(err)
	}
	resourceDir := filepath.Join(home, "mitm", "resources")
	if err := os.MkdirAll(resourceDir, 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(resourceDir, "rewrite.js"), []byte(`let body=JSON.parse($response.body); body.fixed=true; $done({body:JSON.stringify(body),headers:{"Content-Type":"application/json","X-Script":"yes"}});`), 0600); err != nil {
		t.Fatal(err)
	}
	upstream := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		io.WriteString(w, `{"original":true}`)
	}))
	defer upstream.Close()
	engine, err := New(home, Config{Enable: true, DecryptTLS: true, CAFingerprint: ca.Fingerprint, SkipVerify: true, AutoQUICBlock: true, Rules: Rules{Hostname: []string{"-excluded.example", "*.example"}, URLRewrite: []string{`^https://api\.example/ad reject-dict`}, Script: []string{`test = type=http-response,pattern=^https://api\.example/json,requires-body=true,script-path=rewrite.js`}}}, func(ctx context.Context, network, address string) (net.Conn, error) {
		return (&net.Dialer{}).DialContext(ctx, network, upstream.Listener.Addr().String())
	}, func(text string) { t.Log(text) })
	if err != nil {
		t.Fatal(err)
	}
	defer engine.CloseIdle()
	engine.SetCapture(true)
	if engine.Matches("excluded.example") || !engine.Matches("api.example") || engine.Matches("other.test") {
		t.Fatal("hostname/exclusion boundary failed")
	}
	if !engine.BlocksQUIC("api.example", 443) || engine.BlocksQUIC("other.test", 443) {
		t.Fatal("QUIC block escaped hostname scope")
	}
	roots := x509.NewCertPool()
	roots.AppendCertsFromPEM([]byte(ca.PEM))
	transport := &http.Transport{TLSClientConfig: &tls.Config{RootCAs: roots}, DialContext: func(ctx context.Context, network, address string) (net.Conn, error) {
		client, server := net.Pipe()
		go func() { defer server.Close(); engine.Serve(server, "api.example", 443, "connection-test") }()
		return client, nil
	}}
	defer transport.CloseIdleConnections()
	client := &http.Client{Transport: transport, Timeout: 5 * time.Second}
	for _, test := range []struct{ path, want string }{{"/ad", "{}"}, {"/json", `"fixed":true`}} {
		response, err := client.Get("https://api.example" + test.path)
		if err != nil {
			t.Fatal(err)
		}
		data, err := io.ReadAll(response.Body)
		response.Body.Close()
		if err != nil || !strings.Contains(string(data), test.want) {
			t.Fatalf("%s = %s, %v", test.path, data, err)
		}
	}
	deadline := time.Now().Add(time.Second)
	for len(engine.Exchanges("connection-test").Exchanges) < 2 && time.Now().Before(deadline) {
		time.Sleep(time.Millisecond)
	}
	exchanges := engine.Exchanges("connection-test")
	if len(exchanges.Exchanges) != 2 {
		t.Fatalf("capture = %+v", exchanges)
	}
	if body := engine.Body(exchanges.Exchanges[1].ID, true); body == nil || !strings.Contains(string(exchanges.Exchanges[1].responseBody), `"fixed":true`) {
		t.Fatal("capture did not retain the scripted response")
	}
	engine.SetCapture(false)
	if len(engine.Exchanges("").Exchanges) != 0 {
		t.Fatal("disable capture retained bodies")
	}
}

func TestBoundedBodyIsNotTruncatedInTransit(t *testing.T) {
	body := io.NopCloser(strings.NewReader("123456789"))
	data, err := readBoundedBody(&body, 4)
	if err != nil || data != nil {
		t.Fatal(data, err)
	}
	all, _ := io.ReadAll(body)
	if string(all) != "123456789" {
		t.Fatalf("lost bytes: %s", all)
	}
}

func TestScriptTimeoutAndInvalidRuleIsolation(t *testing.T) {
	home := t.TempDir()
	if err := os.MkdirAll(filepath.Join(home, "mitm", "resources"), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(home, "mitm", "resources", "loop.js"), []byte(`while(true){}`), 0600); err != nil {
		t.Fatal(err)
	}
	engine, err := New(home, Config{Enable: true, Rules: Rules{URLRewrite: []string{"[ reject", "^http://api.example/ads reject"}, Script: []string{`loop = type=generic,script-path=loop.js,timeout=0.01`}}}, nil, nil)
	if err != nil {
		t.Fatal(err)
	}
	if len(engine.rules["url-rewrite"]) != 1 {
		t.Fatal("bad rule disabled valid rules")
	}
	output, err := engine.RunScript("loop")
	if err != nil || !strings.Contains(output.Error, "time limit") {
		t.Fatalf("timeout: %+v, %v", output, err)
	}
	issues := Validate(Rules{Script: []string{`timer = type=cron,script-path=loop.js`}, URLRewrite: []string{"[ reject"}})
	if len(issues["script"]) != 1 || len(issues["url-rewrite"]) != 1 {
		t.Fatal(issues)
	}
}
