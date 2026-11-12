package mitm

import (
	"bufio"
	"context"
	"crypto/tls"
	"crypto/x509"
	"encoding/pem"
	"fmt"
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

func TestModuleEditReusesCompiledRulesAndDropsRemovedRules(t *testing.T) {
	home := t.TempDir()
	const kept = `^https://api\.example/keep reject-dict`
	const removed = `^https://api\.example/remove reject`
	first, err := New(home, Config{Enable: true, Rules: Rules{URLRewrite: []string{kept, removed}}}, nil, nil)
	if err != nil {
		t.Fatal(err)
	}
	defer first.Close()
	next, err := Reconfigure(first, home, Config{Enable: true, Rules: Rules{URLRewrite: []string{kept, `^https://api\.example/new reject`}}}, nil, nil)
	if err != nil {
		t.Fatal(err)
	}
	defer next.Close()
	if next == first || len(next.rules["url-rewrite"]) != 2 {
		t.Fatal("module edit did not create the expected rules")
	}
	if next.rules["url-rewrite"][0].match.plain != first.rules["url-rewrite"][0].match.plain {
		t.Fatal("unchanged rule was compiled twice during replacement")
	}
	first.Close()
	if !next.rules["url-rewrite"][0].match.matches("https://api.example/keep") ||
		next.rules["url-rewrite"][1].match.matches("https://api.example/remove") {
		t.Fatal("new engine lost a kept rule or retained a removed rule")
	}
}

func TestHTTPSRewriteScriptAndCapture(t *testing.T) {
	for _, h2 := range []bool{false, true} {
		t.Run(fmt.Sprintf("http2=%t", h2), func(t *testing.T) { exerciseHTTPSRewrite(t, h2) })
	}
}

func TestURLRewriteHeaderActionUsesUpstreamTarget(t *testing.T) {
	home := t.TempDir()
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Host != "mock.example" || r.URL.Path != "/reven/receipts" {
			t.Fatalf("upstream request = %s %s", r.Host, r.URL)
		}
		io.WriteString(w, "rewritten")
	}))
	defer upstream.Close()
	_, port, _ := net.SplitHostPort(upstream.Listener.Addr().String())
	engine, err := New(home, Config{Enable: true, Rules: Rules{
		Hostname:   []string{"api.example"},
		URLRewrite: []string{`^http://api\.example/(.+) http://mock.example/$1 header`},
	}}, func(ctx context.Context, network, address string) (net.Conn, error) {
		return (&net.Dialer{}).DialContext(ctx, network, net.JoinHostPort("127.0.0.1", port))
	}, nil)
	if err != nil {
		t.Fatal(err)
	}
	defer engine.Close()
	client, server := net.Pipe()
	defer client.Close()
	go func() { defer server.Close(); engine.Serve(server, "api.example", 80, "header-rewrite") }()
	if _, err := fmt.Fprint(client, "GET /reven/receipts HTTP/1.1\r\nHost: api.example\r\n\r\n"); err != nil {
		t.Fatal(err)
	}
	response, err := http.ReadResponse(bufio.NewReader(client), nil)
	if err != nil {
		t.Fatal(err)
	}
	body, err := io.ReadAll(response.Body)
	response.Body.Close()
	if err != nil || string(body) != "rewritten" {
		t.Fatalf("response = %q, %v", body, err)
	}
}

func exerciseHTTPSRewrite(t *testing.T, h2 bool) {
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
	engine, err := New(home, Config{Enable: true, H2: h2, DecryptTLS: true, CAFingerprint: ca.Fingerprint, SkipVerify: true, AutoQUICBlock: true, Rules: Rules{Hostname: []string{"-excluded.example", "*.example"}, URLRewrite: []string{`^https://api\.example/ad reject-dict`}, Script: []string{`test = type=http-response,pattern=^https://api\.example/json,requires-body=true,script-path=rewrite.js`}}}, func(ctx context.Context, network, address string) (net.Conn, error) {
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
	transport := &http.Transport{ForceAttemptHTTP2: h2, TLSClientConfig: &tls.Config{RootCAs: roots}, DialContext: func(ctx context.Context, network, address string) (net.Conn, error) {
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
		if h2 && response.ProtoMajor != 2 {
			t.Fatal("HTTP/2 was not negotiated")
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
