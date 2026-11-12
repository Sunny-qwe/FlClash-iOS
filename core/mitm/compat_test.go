package mitm

import (
	"bytes"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"reflect"
	"testing"
)

func TestJQBodyRewrites(t *testing.T) {
	tests := []struct{ query, input, want string }{
		{`.data.showShopEntry=false | .data.idolTabShow=true | .`, `{"data":{}}`, `{"data":{"idolTabShow":true,"showShopEntry":false}}`},
		{`.data.moduleList |= (if type=="array" then map(select(.type != 8 and .type != 5 and .type != 1 and .type != 9 and .type != 6 and .type != 4)) else . end)`, `{"data":{"moduleList":[{"type":8},{"type":2},{"type":5}]}}`, `{"data":{"moduleList":[{"type":2}]}}`},
		{`if .data.resourceList then .data.resourceList |= map(del(.resource)) else . end`, `{"data":{"resourceList":[{"resource":"ad","title":"keep"}]}}`, `{"data":{"resourceList":[{"title":"keep"}]}}`},
		{`if .data then del(.data.putao) else . end`, `{"data":{"putao":{},"keep":true}}`, `{"data":{"keep":true}}`},
		{`.data = {}`, `{"data":{"banner":1}}`, `{"data":{}}`},
	}
	for _, tt := range tests {
		t.Run(tt.query, func(t *testing.T) {
			r, err := parseRule("body-rewrite", `http-response-jq ^https://example.com/api '`+tt.query+`'`)
			if err != nil {
				t.Fatal(err)
			}
			e := &Engine{maxBody: 4096, rules: map[string][]rule{"body-rewrite": {r}}}
			var actions []action
			got := e.rewriteBody("http-response", "https://example.com/api", []byte(tt.input), &actions)
			if string(got) != tt.want || len(actions) != 1 || actions[0].Kind != "body-rewrite" {
				t.Fatalf("body=%s actions=%+v", got, actions)
			}
			if e.needsBody("http-request", "https://example.com/api") || !e.needsBody("http-response", "https://example.com/api") {
				t.Fatal("incorrect body phase")
			}
		})
	}
}

func TestJQFailurePreservesBody(t *testing.T) {
	for _, query := range []string{`error("failure")`, `empty`, `., .`, `def loop: loop; loop`, `"x" * 4096`} {
		r, err := parseRule("body-rewrite", `http-response-jq ^https://example.com '`+query+`'`)
		if err != nil {
			t.Fatal(err)
		}
		e := &Engine{maxBody: 128, rules: map[string][]rule{"body-rewrite": {r}}}
		var actions []action
		original := []byte(`{"keep":true}`)
		if got := e.rewriteBody("http-response", "https://example.com", original, &actions); !bytes.Equal(got, original) {
			t.Fatalf("%s changed body: %s", query, got)
		}
		if len(actions) != 1 || actions[0].Kind != "body-rewrite-error" {
			t.Fatalf("failure not reported: %+v", actions)
		}
	}
	if _, err := parseRule("body-rewrite", `http-response-jq ^https://example.com '.data = '`); err == nil {
		t.Fatal("invalid query accepted")
	}
}

func TestBinaryScriptAndFullHeadersRoundTrip(t *testing.T) {
	home := t.TempDir()
	dir := filepath.Join(home, "mitm", "resources")
	if err := os.MkdirAll(dir, 0700); err != nil {
		t.Fatal(err)
	}
	source := `
if (!($response.body instanceof Uint8Array)) throw Error("not Uint8Array");
if ($response.body[0] !== 0 || $response.body[1] !== 255) throw Error("wrong input");
if (!Array.isArray($response.headers["Set-Cookie"])) throw Error("not a header array");
$response.headers["Set-Cookie"].push("c=3");
const result = new Uint8Array([99, 0, 128, 255, 99]).subarray(1, 4);
$done({body:result, headers:$response.headers});`
	if err := os.WriteFile(filepath.Join(dir, "binary.js"), []byte(source), 0600); err != nil {
		t.Fatal(err)
	}
	r, err := parseRule("script", `test = type=http-response,pattern=^https://example.com,requires-body=true,binary-body-mode=true,full-header-mode=true,script-path=binary.js`)
	if err != nil {
		t.Fatal(err)
	}
	e := &Engine{home: home, maxBody: 4096, rules: map[string][]rule{"script": {r}}}
	request := httptest.NewRequest("GET", "https://example.com/api", nil)
	response := &http.Response{StatusCode: 200, Header: http.Header{"Set-Cookie": {"a=1", "b=2"}}, Body: io.NopCloser(bytes.NewReader([]byte{0, 255}))}
	var actions []action
	e.applyScripts("http-response", request, response, []byte{0, 255}, &actions)
	got, _ := io.ReadAll(response.Body)
	if !bytes.Equal(got, []byte{0, 128, 255}) || !reflect.DeepEqual(response.Header.Values("Set-Cookie"), []string{"a=1", "b=2", "c=3"}) {
		t.Fatalf("body=%v headers=%v actions=%+v", got, response.Header, actions)
	}
	if len(actions) != 1 || actions[0].Kind != "script" {
		t.Fatalf("script failed: %+v", actions)
	}
}

func TestHostnamePortPatterns(t *testing.T) {
	e := &Engine{config: Config{Enable: true, Rules: Rules{Hostname: []string{"-private.example:443", "*.example:443", "39.156.12*.*:443", "plain.test:80"}}}}
	for _, host := range e.config.Hostname {
		if _, err := parseRule("hostname", host); err != nil {
			t.Fatal(host, err)
		}
	}
	if !e.MatchesEndpoint("api.example", 443) || e.MatchesEndpoint("api.example", 80) || e.MatchesEndpoint("private.example", 443) || !e.MatchesEndpoint("39.156.121.21", 443) || !e.MatchesEndpoint("plain.test", 80) || e.Matches("plain.test") {
		t.Fatal("incorrect hostname or port selection")
	}
}
