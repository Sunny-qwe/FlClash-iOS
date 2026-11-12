package mitm

import (
	"context"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

type observedBody struct {
	io.Reader
	reads *atomic.Int32
}

func (b observedBody) Read(p []byte) (int, error) {
	b.reads.Add(1)
	return b.Reader.Read(p)
}

func (b observedBody) Close() error { return nil }

func TestBodyBudgetWaitsBeforeReadingAndCancelsWithoutBypass(t *testing.T) {
	previous := bodyBudget
	bodyBudget = make(chan struct{}, 1)
	bodyBudget <- struct{}{}
	t.Cleanup(func() { bodyBudget = previous })
	e, err := New(t.TempDir(), Config{Enable: true, Rules: Rules{
		URLRewrite:  []string{`^http://example.com/ad reject-dict`},
		BodyRewrite: []string{`http-request ^http://example.com/ad x y`},
	}}, nil, nil)
	if err != nil {
		t.Fatal(err)
	}
	defer e.Close()
	var reads atomic.Int32
	ctx, cancel := context.WithCancel(context.Background())
	request := httptest.NewRequest("POST", "http://example.com/ad", nil).WithContext(ctx)
	request.Body = observedBody{Reader: strings.NewReader("x"), reads: &reads}
	done := make(chan struct{})
	go func() {
		defer close(done)
		e.serveHTTP(httptest.NewRecorder(), request, "example.com", 80, "queued")
	}()
	cancel()
	select {
	case <-done:
	case <-time.After(time.Second):
		t.Fatal("cancelled request remained queued")
	}
	if reads.Load() != 0 || len(bodyBudget) != 1 {
		t.Fatal("queued request read a body or released another request's permit")
	}
	<-bodyBudget
	response := httptest.NewRecorder()
	e.serveHTTP(response, httptest.NewRequest("GET", "http://example.com/ad", nil), "example.com", 80, "next")
	if response.Code != http.StatusOK || response.Body.String() != "{}" || len(bodyBudget) != 0 {
		t.Fatalf("rule did not run after the slot became available: %d %q", response.Code, response.Body.String())
	}
}
