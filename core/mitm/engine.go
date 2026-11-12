package mitm

import (
	"bytes"
	"context"
	"crypto/tls"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"path"
	"reflect"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"golang.org/x/net/http2"
)

type DialFunc func(context.Context, string, string) (net.Conn, error)

var sessionBudget = make(chan struct{}, 16)
var scriptBudget = make(chan struct{}, 1)

type Engine struct {
	config    Config
	home      string
	ca        *authority
	rules     map[string][]rule
	transport *http.Transport
	maxBody   int64
	capture   atomic.Bool
	store     captureStore
	log       func(string)
	certMu    sync.Mutex
	certs     map[string]*tls.Certificate
	connMu    sync.Mutex
	closed    bool
	conns     map[net.Conn]struct{}
}

func Reconfigure(current *Engine, home string, cfg Config, dial DialFunc, logger func(string)) (*Engine, error) {
	if current == nil || current.home != home || !reflect.DeepEqual(current.config, cfg) {
		return New(home, cfg, dial, logger)
	}
	if cfg.Enable && cfg.DecryptTLS {
		certificateMu.Lock()
		ca, err := loadAuthority(home)
		certificateMu.Unlock()
		if err != nil {
			return nil, fmt.Errorf("MITM CA: %w", err)
		}
		if current.ca == nil || !bytes.Equal(current.ca.cert.Raw, ca.cert.Raw) {
			return New(home, cfg, dial, logger)
		}
	}
	return current, nil
}

func New(home string, cfg Config, dial DialFunc, logger func(string)) (*Engine, error) {
	e := &Engine{home: home, config: cfg, rules: map[string][]rule{}, maxBody: 256 << 10, certs: map[string]*tls.Certificate{}, log: logger}
	e.store.init()
	if limit := cfg.Limits["capture-entries"]; limit > 0 && limit < e.store.limit {
		e.store.limit = limit
	}
	if !cfg.Enable {
		return e, nil
	}
	if cfg.DecryptTLS {
		certificateMu.Lock()
		ca, err := loadAuthority(home)
		certificateMu.Unlock()
		if err != nil {
			return nil, fmt.Errorf("MITM CA: %w; generate and trust the certificate first", err)
		}
		if cfg.CAFingerprint != "" && describeAuthority(ca).Fingerprint != cfg.CAFingerprint {
			return nil, errors.New("MITM trusted certificate changed; install and trust the new certificate")
		}
		e.ca = ca
	}
	for kind, lines := range cfg.Rules.lists() {
		if kind == "hostname" {
			continue
		}
		for index, line := range lines {
			r, err := parseRule(kind, line)
			if err != nil {
				e.warn(fmt.Sprintf("MITM %s line %d skipped: %v", kind, index+1, err))
				continue
			}
			e.rules[kind] = append(e.rules[kind], r)
		}
	}
	e.transport = &http.Transport{DialContext: dial, Proxy: nil, TLSClientConfig: &tls.Config{MinVersion: tls.VersionTLS12, InsecureSkipVerify: cfg.SkipVerify}, DisableCompression: false, MaxIdleConns: 8, MaxIdleConnsPerHost: 2, MaxConnsPerHost: 8, IdleConnTimeout: 30 * time.Second, TLSHandshakeTimeout: 10 * time.Second, ResponseHeaderTimeout: 20 * time.Second, MaxResponseHeaderBytes: 128 << 10, ForceAttemptHTTP2: cfg.H2}
	if cfg.H2 {
		if err := http2.ConfigureTransport(e.transport); err != nil {
			return nil, err
		}
	}
	return e, nil
}

func (e *Engine) warn(message string) {
	if e.log != nil {
		e.log(message)
	}
}

func (e *Engine) Matches(host string) bool {
	return e.MatchesEndpoint(host, 443)
}

func (e *Engine) MatchesEndpoint(host string, port uint16) bool {
	if !e.config.Enable {
		return false
	}
	host = strings.ToLower(strings.TrimSuffix(host, "."))
	for _, line := range e.config.Hostname {
		line = strings.ToLower(strings.TrimSpace(line))
		excluded := strings.HasPrefix(line, "-")
		line = strings.TrimPrefix(line, "-")
		if before, after, ok := strings.Cut(line, ":"); ok {
			if after != strconv.Itoa(int(port)) {
				continue
			}
			line = before
		}
		matched, _ := path.Match(line, host)
		if matched || line == host {
			return !excluded
		}
	}
	return false
}

func (e *Engine) NeedsHostname() bool { return e.config.Enable && len(e.config.Hostname) > 0 }

func (e *Engine) BlocksQUIC(host string, port uint16) bool {
	return e.ca != nil && e.config.AutoQUICBlock && port == 443 && e.Matches(host)
}

func (e *Engine) certificate(host string) (*tls.Certificate, error) {
	e.certMu.Lock()
	defer e.certMu.Unlock()
	if cert := e.certs[host]; cert != nil {
		return cert, nil
	}
	cert, err := e.ca.issue(host)
	if err != nil {
		return nil, err
	}
	if len(e.certs) >= 32 {
		clear(e.certs)
	}
	e.certs[host] = cert
	return cert, nil
}

func (e *Engine) Serve(conn net.Conn, host string, port uint16, id string) (handled bool) {
	if !e.MatchesEndpoint(host, port) || port != 80 && port != 443 || port == 443 && e.ca == nil {
		return false
	}
	select {
	case sessionBudget <- struct{}{}:
		defer func() { <-sessionBudget }()
	default:
		e.warn("MITM session limit reached; connection passed through")
		return false
	}
	e.connMu.Lock()
	if e.closed {
		e.connMu.Unlock()
		_ = conn.Close()
		return true
	}
	if e.conns == nil {
		e.conns = make(map[net.Conn]struct{})
	}
	e.conns[conn] = struct{}{}
	e.connMu.Unlock()
	originalConn := conn
	defer func() {
		e.connMu.Lock()
		delete(e.conns, originalConn)
		e.connMu.Unlock()
	}()
	defer func() {
		if p := recover(); p != nil {
			e.warn(fmt.Sprintf("MITM connection failed: %v", p))
		}
	}()
	handled = true
	if port == 443 {
		protocols := []string{"http/1.1"}
		if e.config.H2 {
			protocols = []string{"h2", "http/1.1"}
		}
		tlsConn := tls.Server(conn, &tls.Config{MinVersion: tls.VersionTLS12, GetCertificate: func(hello *tls.ClientHelloInfo) (*tls.Certificate, error) {
			if hello.ServerName != "" && !strings.EqualFold(strings.TrimSuffix(hello.ServerName, "."), strings.TrimSuffix(host, ".")) {
				return nil, errors.New("TLS server name differs from routed hostname")
			}
			return e.certificate(host)
		}, NextProtos: protocols})
		if err := tlsConn.SetDeadline(time.Now().Add(10 * time.Second)); err != nil {
			return true
		}
		if err := tlsConn.Handshake(); err != nil {
			e.warn("MITM TLS handshake failed; check certificate trust: " + err.Error())
			return true
		}
		_ = tlsConn.SetDeadline(time.Time{})
		conn = tlsConn
		if tlsConn.ConnectionState().NegotiatedProtocol == "h2" {
			server := &http2.Server{MaxConcurrentStreams: 4, IdleTimeout: 30 * time.Second, MaxReadFrameSize: 16 << 10}
			server.ServeConn(conn, &http2.ServeConnOpts{Handler: http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { e.serveHTTP(w, r, host, port, id) })})
			return true
		}
	}
	handler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { e.serveHTTP(w, r, host, port, id) })
	server := &http.Server{Handler: handler, ReadHeaderTimeout: 10 * time.Second, IdleTimeout: 30 * time.Second, MaxHeaderBytes: 128 << 10}
	listener := newSingleListener(conn)
	_ = server.Serve(listener)
	<-listener.done
	return true
}

type singleListener struct {
	conn     net.Conn
	accepted bool
	done     chan struct{}
	once     sync.Once
}
type trackedConn struct {
	net.Conn
	close func()
}

func (c *trackedConn) Close() error { err := c.Conn.Close(); c.close(); return err }
func newSingleListener(conn net.Conn) *singleListener {
	return &singleListener{conn: conn, done: make(chan struct{})}
}
func (l *singleListener) Accept() (net.Conn, error) {
	if l.accepted {
		<-l.done
		return nil, net.ErrClosed
	}
	l.accepted = true
	return &trackedConn{Conn: l.conn, close: func() { l.once.Do(func() { close(l.done) }) }}, nil
}
func (l *singleListener) Close() error   { l.once.Do(func() { close(l.done) }); return l.conn.Close() }
func (l *singleListener) Addr() net.Addr { return l.conn.LocalAddr() }

func (e *Engine) CloseIdle() {
	if e != nil && e.transport != nil {
		e.transport.CloseIdleConnections()
	}
}

func (e *Engine) Close() {
	e.connMu.Lock()
	e.closed = true
	conns := e.conns
	e.conns = nil
	e.connMu.Unlock()
	for conn := range conns {
		_ = conn.Close()
	}
	e.SetCapture(false)
	e.CloseIdle()
}

func (e *Engine) serveHTTP(w http.ResponseWriter, incoming *http.Request, host string, port uint16, id string) {
	r := incoming.Clone(incoming.Context())
	r.RequestURI = ""
	r.URL.Scheme = "http"
	if port == 443 {
		r.URL.Scheme = "https"
	}
	r.URL.Host = net.JoinHostPort(host, strconv.Itoa(int(port)))
	if port == 80 || port == 443 {
		r.URL.Host = host
	}
	r.Host = host
	if isUpgrade(r) {
		e.serveUpgrade(w, r)
		return
	}
	original := r.URL.String()
	started := time.Now().UTC()
	stripHopHeaders(r.Header)
	var actions []action
	var reqBody, respBody []byte
	var response *http.Response
	var err error
	for _, rule := range e.rules["url-rewrite"] {
		if !rule.match.matches(original) {
			continue
		}
		parts := rule.fields
		if len(parts) == 2 {
			response = rejectResponse(parts[1], r)
		} else if len(parts) == 3 && parts[2] == "header" {
			var location string
			location, err = rule.match.replace(original, parts[1])
			if err == nil {
				target, parseErr := url.Parse(location)
				if parseErr != nil || target.Scheme == "" || target.Host == "" || target.Scheme != "http" && target.Scheme != "https" {
					if parseErr == nil {
						parseErr = errors.New("target must be an absolute HTTP URL")
					}
					err = fmt.Errorf("invalid URL rewrite target: %w", parseErr)
				} else {
					r.URL = target
					r.RequestURI = ""
					r.Host = target.Host
				}
			}
		} else {
			var location string
			location, err = rule.match.replace(original, parts[1])
			if err == nil {
				code, _ := strconv.Atoi(parts[len(parts)-1])
				response = localResponse(code, nil, http.Header{"Location": {location}}, r)
			}
		}
		actions = append(actions, action{Kind: "url-rewrite", Detail: parts[len(parts)-1]})
		break
	}
	if err == nil && response == nil {
		for _, rule := range e.rules["map-local"] {
			if !rule.match.matches(original) {
				continue
			}
			var data []byte
			data, err = rule.localBody(e.home, e.maxBody)
			if err != nil {
				break
			}
			code := 200
			if value := rule.params["status-code"]; value != "" {
				code, _ = strconv.Atoi(value)
			}
			headers := http.Header{}
			for _, item := range strings.Split(rule.params["header"], "|") {
				key, value, ok := strings.Cut(item, ":")
				if ok {
					headers.Add(strings.TrimSpace(key), strings.TrimSpace(value))
				}
			}
			response = localResponse(code, data, headers, r)
			actions = append(actions, action{Kind: "map-local"})
			break
		}
	}
	if err == nil && response == nil {
		e.rewriteHeaders("http-request", original, r.Header, &actions)
		requestNeedsBody := e.needsBody("http-request", original) || e.capture.Load()
		if requestNeedsBody {
			encoded := r.Header.Get("Content-Encoding") != ""
			wrapper := &http.Response{Header: r.Header, Body: r.Body}
			reqBody, _ = e.responseBody(wrapper)
			r.Body = wrapper.Body
			if encoded && reqBody != nil {
				setRequestBody(r, reqBody)
			}
		}
		if reqBody != nil {
			rewritten := e.rewriteBody("http-request", original, reqBody, &actions)
			if !bytes.Equal(reqBody, rewritten) {
				reqBody = rewritten
				setRequestBody(r, reqBody)
			}
		}
		response = e.applyScripts("http-request", r, nil, reqBody, &actions)
		if e.capture.Load() && r.Header.Get("Content-Encoding") == "" {
			reqBody, _ = readBoundedBody(&r.Body, e.maxBody)
		}
		if response == nil {
			response, err = e.transport.RoundTrip(r)
		}
	}
	if err != nil {
		e.warn("MITM upstream request failed: " + err.Error())
		http.Error(w, "MITM upstream request failed", http.StatusBadGateway)
		return
	}
	defer response.Body.Close()
	e.rewriteHeaders("http-response", original, response.Header, &actions)
	needsBody := e.needsBody("http-response", original) || e.capture.Load()
	if needsBody {
		respBody, _ = e.responseBody(response)
	}
	if respBody != nil {
		rewritten := e.rewriteBody("http-response", original, respBody, &actions)
		if !bytes.Equal(respBody, rewritten) {
			respBody = rewritten
			setResponseBody(response, respBody)
		}
	}
	if replacement := e.applyScripts("http-response", r, response, respBody, &actions); replacement != nil {
		response.Body.Close()
		response = replacement
		defer response.Body.Close()
	}
	if e.capture.Load() {
		respBody, _ = e.responseBody(response)
	}
	stripHopHeaders(response.Header)
	for key, values := range response.Header {
		w.Header()[key] = values
	}
	w.WriteHeader(response.StatusCode)
	_, copyErr := io.Copy(w, response.Body)
	if e.capture.Load() {
		e.store.add(id, started, r, response, original, reqBody, respBody, actions, copyErr)
	}
}

func stripHopHeaders(header http.Header) {
	for _, name := range strings.Split(header.Get("Connection"), ",") {
		header.Del(strings.TrimSpace(name))
	}
	for _, key := range []string{"Connection", "Proxy-Connection", "Proxy-Authenticate", "Proxy-Authorization", "Keep-Alive", "TE", "Trailer", "Transfer-Encoding", "Upgrade"} {
		header.Del(key)
	}
}

func readBoundedBody(body *io.ReadCloser, max int64) ([]byte, error) {
	if *body == nil {
		return []byte{}, nil
	}
	data, err := io.ReadAll(io.LimitReader(*body, max+1))
	if err != nil {
		*body = &joinedBody{Reader: io.MultiReader(bytes.NewReader(data), *body), Closer: *body}
		return nil, err
	}
	if int64(len(data)) > max {
		*body = &joinedBody{Reader: io.MultiReader(bytes.NewReader(data), *body), Closer: *body}
		return nil, nil
	}
	(*body).Close()
	*body = io.NopCloser(bytes.NewReader(data))
	return data, nil
}

type joinedBody struct {
	io.Reader
	io.Closer
}

func setRequestBody(r *http.Request, data []byte) {
	if r.Body != nil {
		r.Body.Close()
	}
	r.Body = io.NopCloser(bytes.NewReader(data))
	r.ContentLength = int64(len(data))
	r.TransferEncoding = nil
	r.Header.Del("Content-Length")
	r.Header.Del("Content-Encoding")
}
func setResponseBody(r *http.Response, data []byte) {
	if r.Body != nil {
		r.Body.Close()
	}
	r.Body = io.NopCloser(bytes.NewReader(data))
	r.ContentLength = int64(len(data))
	r.TransferEncoding = nil
	r.Header.Set("Content-Length", strconv.Itoa(len(data)))
	r.Header.Del("Content-Encoding")
	r.Header.Del("ETag")
}
func localResponse(code int, data []byte, header http.Header, r *http.Request) *http.Response {
	return &http.Response{StatusCode: code, Status: fmt.Sprintf("%d %s", code, http.StatusText(code)), Proto: "HTTP/1.1", ProtoMajor: 1, ProtoMinor: 1, Header: header, Body: io.NopCloser(bytes.NewReader(data)), ContentLength: int64(len(data)), Request: r}
}
func rejectResponse(kind string, r *http.Request) *http.Response {
	code := 200
	data := []byte{}
	header := http.Header{}
	switch kind {
	case "reject":
		code = 404
	case "reject-dict":
		data = []byte("{}")
		header.Set("Content-Type", "application/json")
	case "reject-array":
		data = []byte("[]")
		header.Set("Content-Type", "application/json")
	case "reject-img", "reject-tinygif":
		data, _ = (rule{params: map[string]string{"data-type": "tiny-gif"}}).localBody("", 1024)
		header.Set("Content-Type", "image/gif")
	}
	return localResponse(code, data, header, r)
}

func (e *Engine) rewriteHeaders(phase, rawURL string, header http.Header, actions *[]action) {
	for _, rule := range e.rules["header-rewrite"] {
		parts := rule.fields
		if parts[0] != phase || !rule.match.matches(rawURL) {
			continue
		}
		key := parts[3]
		switch parts[2] {
		case "header-del":
			header.Del(key)
		case "header-add":
			header.Add(key, parts[4])
		case "header-replace":
			header.Set(key, parts[4])
		case "header-replace-regex":
			p, err := compilePattern(parts[4])
			if err != nil {
				continue
			}
			value, err := p.replace(header.Get(key), parts[5])
			if err != nil {
				continue
			}
			header.Set(key, value)
		}
		*actions = append(*actions, action{Kind: "header-rewrite", Phase: phase, Detail: key})
	}
}

func (e *Engine) rewriteBody(phase, rawURL string, data []byte, actions *[]action) []byte {
	for _, rule := range e.rules["body-rewrite"] {
		parts := rule.fields
		if parts[0] != phase || !rule.match.matches(rawURL) {
			continue
		}
		if rule.jq != nil {
			rewritten, err := e.rewriteJSON(rule, data)
			if err != nil {
				e.warn("MITM jq rewrite failed; original body preserved: " + err.Error())
				*actions = append(*actions, action{Kind: "body-rewrite-error", Phase: phase, Detail: err.Error()})
				continue
			}
			data = rewritten
			*actions = append(*actions, action{Kind: "body-rewrite", Phase: phase})
			continue
		}
		p, err := compilePattern(parts[2])
		if err != nil {
			continue
		}
		text, err := p.replace(string(data), parts[3])
		if err != nil || int64(len(text)) > e.maxBody {
			continue
		}
		data = []byte(text)
		*actions = append(*actions, action{Kind: "body-rewrite", Phase: phase})
	}
	return data
}

func (e *Engine) needsBody(phase, rawURL string) bool {
	for _, r := range e.rules["body-rewrite"] {
		if r.fields[0] == phase && r.match.matches(rawURL) {
			return true
		}
	}
	for _, r := range e.rules["script"] {
		if r.params["type"] == phase && r.params["requires-body"] == "true" && r.match.matches(rawURL) {
			return true
		}
	}
	return false
}

func scriptURL(raw string) (*url.URL, error) {
	u, err := url.Parse(raw)
	if err != nil {
		return nil, err
	}
	if u.Scheme != "http" && u.Scheme != "https" || u.Hostname() == "" {
		return nil, errors.New("script URL must use HTTP or HTTPS")
	}
	return u, nil
}
