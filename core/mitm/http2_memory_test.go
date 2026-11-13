package mitm

import (
	"context"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/metacubex/mihomo/constant/features"
	"golang.org/x/net/http2"
)

func TestHTTP2AdvertisesBoundedReceiveWindow(t *testing.T) {
	if !features.WithLowMemory {
		t.Skip("extension memory policy")
	}
	server, client := net.Pipe()
	defer client.Close()
	defer server.Close()
	_ = client.SetDeadline(time.Now().Add(5 * time.Second))
	done := make(chan struct{})
	go func() {
		defer close(done)
		newHTTP2Server().ServeConn(server, &http2.ServeConnOpts{Handler: http.NotFoundHandler()})
	}()
	read := http2.NewFramer(nil, client)
	settings, err := read.ReadFrame()
	if err != nil {
		t.Fatal(err)
	}
	frame, ok := settings.(*http2.SettingsFrame)
	if !ok {
		t.Fatalf("first frame = %T", settings)
	}
	window, ok := frame.Value(http2.SettingInitialWindowSize)
	if !ok || window != 64<<10 {
		t.Fatalf("stream receive window = %d, present=%v", window, ok)
	}
	_ = client.Close()
	select {
	case <-done:
	case <-time.After(5 * time.Second):
		t.Fatal("HTTP/2 connection did not close")
	}
}

func TestHTTP2BoundedTransportStreamsLargeResponse(t *testing.T) {
	payload := strings.Repeat("streamed", 256<<10)
	upstream := httptest.NewUnstartedServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.ProtoMajor != 2 {
			t.Errorf("upstream protocol = %s", r.Proto)
		}
		_, _ = io.WriteString(w, payload)
	}))
	upstream.EnableHTTP2 = true
	upstream.StartTLS()
	defer upstream.Close()
	e, err := New(t.TempDir(), Config{Enable: true, H2: true, SkipVerify: true}, (&net.Dialer{}).DialContext, nil)
	if err != nil {
		t.Fatal(err)
	}
	defer e.Close()
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	req, _ := http.NewRequestWithContext(ctx, "GET", upstream.URL, nil)
	response, err := e.transport.RoundTrip(req)
	if err != nil {
		t.Fatal(err)
	}
	defer response.Body.Close()
	body, err := io.ReadAll(response.Body)
	if err != nil || string(body) != payload {
		t.Fatalf("stream truncated: got %d bytes, err=%v", len(body), err)
	}
	if features.WithLowMemory {
		if cfg := e.transport.HTTP2; cfg == nil || cfg.MaxReceiveBufferPerConnection > 256<<10 || cfg.MaxReceiveBufferPerStream > 64<<10 {
			t.Fatalf("unbounded extension receive buffers: %+v", cfg)
		}
	}
}
