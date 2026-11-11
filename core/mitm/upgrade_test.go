package mitm

import (
	"bufio"
	"context"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

func TestUpgradeKeepsBidirectionalStream(t *testing.T) {
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		conn, buffer, err := w.(http.Hijacker).Hijack()
		if err != nil {
			return
		}
		defer conn.Close()
		_, _ = buffer.WriteString("HTTP/1.1 101 Switching Protocols\r\nConnection: Upgrade\r\nUpgrade: websocket\r\n\r\n")
		_ = buffer.Flush()
		_, _ = io.Copy(conn, buffer)
	}))
	defer upstream.Close()
	engine, err := New(t.TempDir(), Config{Enable: true, Rules: Rules{Hostname: []string{"api.example"}}}, func(ctx context.Context, network, address string) (net.Conn, error) {
		return (&net.Dialer{}).DialContext(ctx, network, upstream.Listener.Addr().String())
	}, nil)
	if err != nil {
		t.Fatal(err)
	}
	defer engine.CloseIdle()
	client, server := net.Pipe()
	defer client.Close()
	_ = client.SetDeadline(time.Now().Add(5 * time.Second))
	done := make(chan struct{})
	go func() {
		defer close(done)
		defer server.Close()
		engine.Serve(server, "api.example", 80, "upgrade-test")
	}()
	_, err = io.WriteString(client, "GET /socket HTTP/1.1\r\nHost: api.example\r\nConnection: Upgrade\r\nUpgrade: websocket\r\n\r\n")
	if err != nil {
		t.Fatal(err)
	}
	reader := bufio.NewReader(client)
	response, err := http.ReadResponse(reader, nil)
	if err != nil || response.StatusCode != http.StatusSwitchingProtocols {
		t.Fatalf("upgrade = %v, %v", response, err)
	}
	if _, err := io.WriteString(client, "stream-data"); err != nil {
		t.Fatal(err)
	}
	data := make([]byte, len("stream-data"))
	if _, err := io.ReadFull(reader, data); err != nil || string(data) != "stream-data" {
		t.Fatalf("echo = %q, %v", data, err)
	}
	_ = client.Close()
	select {
	case <-done:
	case <-time.After(time.Second):
		t.Fatal("upgraded session did not close")
	}
}
