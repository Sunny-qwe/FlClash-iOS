package mitm

import (
	"fmt"
	"io"
	"net/http"
	"strings"
)

func (e *Engine) serveUpgrade(w http.ResponseWriter, r *http.Request) {
	response, err := e.transport.RoundTrip(r)
	if err != nil {
		http.Error(w, "upstream upgrade failed", http.StatusBadGateway)
		return
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusSwitchingProtocols {
		for key, values := range response.Header {
			w.Header()[key] = values
		}
		w.WriteHeader(response.StatusCode)
		_, _ = io.Copy(w, response.Body)
		return
	}
	upstream, ok := response.Body.(io.ReadWriteCloser)
	if !ok {
		http.Error(w, "upstream does not support upgrade", http.StatusBadGateway)
		return
	}
	hijacker, ok := w.(http.Hijacker)
	if !ok {
		http.Error(w, "upgrade requires HTTP/1.1", http.StatusBadRequest)
		return
	}
	client, buffer, err := hijacker.Hijack()
	if err != nil {
		return
	}
	defer client.Close()
	if _, err := buffer.WriteString("HTTP/1.1 101 Switching Protocols\r\n"); err != nil {
		return
	}
	if err := response.Header.Write(buffer); err != nil {
		return
	}
	if _, err := buffer.WriteString("\r\n"); err != nil {
		return
	}
	if err := buffer.Flush(); err != nil {
		return
	}
	done := make(chan struct{})
	e.safeGo("upgrade", func() {
		defer close(done)
		defer upstream.Close()
		defer client.Close()
		_, _ = io.Copy(upstream, buffer)
	})
	_, _ = io.Copy(client, upstream)
	_ = client.Close()
	_ = upstream.Close()
	<-done
}

func (e *Engine) safeGo(name string, run func()) {
	go func() {
		defer func() {
			if p := recover(); p != nil {
				e.warn(fmt.Sprintf("MITM %s failed: %v", name, p))
			}
		}()
		run()
	}()
}

func isUpgrade(r *http.Request) bool {
	return r.Header.Get("Upgrade") != "" && strings.Contains(strings.ToLower(r.Header.Get("Connection")), "upgrade")
}
