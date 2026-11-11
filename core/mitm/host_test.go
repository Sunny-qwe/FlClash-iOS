package mitm

import (
	"bytes"
	"compress/gzip"
	"context"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestNetworkScriptsTimersAndPersistence(t *testing.T) {
	home := t.TempDir()
	dir := filepath.Join(home, "mitm", "resources")
	if err := os.MkdirAll(dir, 0700); err != nil {
		t.Fatal(err)
	}
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { io.WriteString(w, "network-ok") }))
	defer upstream.Close()
	scripts := map[string]string{
		"callback": `$httpClient.get("http://api.example/test", (err, res, body) => { if(err) throw Error(err); $persistentStore.write(body,"value"); setTimeout(() => $done({body:body,status:res.status}),1); });`,
		"promise":  `$task.fetch({url:"http://api.example/test"}).then(res => $done({body:res.body})).catch(err=>$done({error:err}));`,
		"read":     `$done({body:$persistentStore.read("value")});`,
	}
	for name, script := range scripts {
		if err := os.WriteFile(filepath.Join(dir, name+".js"), []byte(script), 0600); err != nil {
			t.Fatal(err)
		}
	}
	makeEngine := func(file string) *Engine {
		e, err := New(home, Config{Enable: true, Rules: Rules{Script: []string{`same = type=generic,script-path=` + file + `.js`}}}, func(ctx context.Context, network, address string) (net.Conn, error) {
			return (&net.Dialer{}).DialContext(ctx, network, upstream.Listener.Addr().String())
		}, nil)
		if err != nil {
			t.Fatal(err)
		}
		t.Cleanup(e.CloseIdle)
		return e
	}
	for _, name := range []string{"callback", "promise", "read"} {
		output, err := makeEngine(name).RunScript("same")
		if err != nil || output.Error != "" || !strings.Contains(output.Result, "network-ok") {
			t.Fatalf("%s: %+v %v", name, output, err)
		}
	}
}

func TestCompressedBodyRewriteAndOversizePassThrough(t *testing.T) {
	var compressed bytes.Buffer
	writer := gzip.NewWriter(&compressed)
	writer.Write([]byte(`{"value":true}`))
	writer.Close()
	e := &Engine{maxBody: 256}
	response := &http.Response{Header: http.Header{"Content-Encoding": {"gzip"}}, Body: io.NopCloser(bytes.NewReader(compressed.Bytes()))}
	decoded, err := e.responseBody(response)
	if err != nil || string(decoded) != `{"value":true}` || response.Header.Get("Content-Encoding") != "" {
		t.Fatal(string(decoded), err, response.Header)
	}
	e.maxBody = 4
	response = &http.Response{Header: http.Header{"Content-Encoding": {"gzip"}}, Body: io.NopCloser(bytes.NewReader(compressed.Bytes()))}
	decoded, err = e.responseBody(response)
	if err != nil || decoded != nil {
		t.Fatal(decoded, err)
	}
	remaining, _ := io.ReadAll(response.Body)
	if !bytes.Equal(remaining, compressed.Bytes()) {
		t.Fatal("oversize response was modified")
	}
}
