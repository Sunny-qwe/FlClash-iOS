package mitm

import (
	"encoding/base64"
	"net/http"
	"sync"
	"sync/atomic"
	"time"
)

type action struct {
	Kind   string `json:"kind"`
	Phase  string `json:"phase"`
	Detail string `json:"detail"`
}
type Exchange struct {
	ID                        int64       `json:"id"`
	Start                     time.Time   `json:"start"`
	Duration                  int64       `json:"duration"`
	Method                    string      `json:"method"`
	URL                       string      `json:"url"`
	OriginalURL               string      `json:"original-url"`
	Proto                     string      `json:"proto"`
	Status                    int         `json:"status"`
	Connection                string      `json:"connection"`
	RequestHeader             http.Header `json:"request-header"`
	ResponseHeader            http.Header `json:"response-header"`
	RequestSize               int         `json:"request-size"`
	ResponseSize              int         `json:"response-size"`
	Actions                   []action    `json:"actions"`
	Error                     string      `json:"error"`
	requestBody, responseBody []byte
}
type Body struct {
	Data      string `json:"data"`
	Truncated bool   `json:"truncated"`
	Encoding  string `json:"encoding"`
}
type ExchangeList struct {
	Capturing bool        `json:"capturing"`
	Since     time.Time   `json:"since"`
	Exchanges []*Exchange `json:"exchanges"`
	Closed    bool        `json:"closed"`
}
type captureStore struct {
	sync.Mutex
	since time.Time
	bytes int
	limit int
	items []*Exchange
}

var exchangeID atomic.Int64

func init() { exchangeID.Store(time.Now().UnixMicro()) }

func (s *captureStore) init() { s.since = time.Now().UTC(); s.items = []*Exchange{}; s.limit = 64 }
func (s *captureStore) add(connection string, start time.Time, request *http.Request, response *http.Response, original string, reqBody, respBody []byte, actions []action, err error) {
	s.Lock()
	defer s.Unlock()
	if actions == nil {
		actions = []action{}
	}
	item := &Exchange{ID: exchangeID.Add(1), Start: start, Duration: time.Since(start).Milliseconds(), Method: request.Method, URL: request.URL.String(), OriginalURL: original, Proto: request.Proto, Status: response.StatusCode, Connection: connection, RequestHeader: request.Header.Clone(), ResponseHeader: response.Header.Clone(), RequestSize: len(reqBody), ResponseSize: len(respBody), Actions: actions, requestBody: append([]byte(nil), reqBody...), responseBody: append([]byte(nil), respBody...)}
	if err != nil {
		item.Error = err.Error()
	}
	size := exchangeSize(item)
	s.items = append(s.items, item)
	s.bytes += size
	for len(s.items) > s.limit || s.bytes > 1<<20 {
		first := s.items[0]
		s.bytes -= exchangeSize(first)
		s.since = first.Start.Add(time.Millisecond)
		s.items[0] = nil
		s.items = s.items[1:]
	}
}

func exchangeSize(item *Exchange) int {
	size := len(item.requestBody) + len(item.responseBody) + len(item.URL) + len(item.OriginalURL) + len(item.Error)
	for _, headers := range []http.Header{item.RequestHeader, item.ResponseHeader} {
		for key, values := range headers {
			size += len(key)
			for _, value := range values {
				size += len(value)
			}
		}
	}
	for _, action := range item.Actions {
		size += len(action.Kind) + len(action.Phase) + len(action.Detail)
	}
	return size
}
func (e *Engine) SetCapture(enabled bool) {
	e.capture.Store(enabled)
	if !enabled {
		e.TrimCapture()
	}
}
func (e *Engine) TrimCapture() {
	e.store.Lock()
	defer e.store.Unlock()
	e.store.items = []*Exchange{}
	e.store.bytes = 0
	e.store.since = time.Now().UTC()
}
func (e *Engine) Exchanges(connection string) ExchangeList {
	e.store.Lock()
	defer e.store.Unlock()
	out := ExchangeList{Capturing: e.capture.Load(), Since: e.store.since, Exchanges: []*Exchange{}}
	for _, item := range e.store.items {
		if connection == "" || item.Connection == connection {
			out.Exchanges = append(out.Exchanges, item)
		}
	}
	return out
}
func (e *Engine) Exchange(id int64) *Exchange {
	e.store.Lock()
	defer e.store.Unlock()
	for _, item := range e.store.items {
		if item.ID == id {
			return item
		}
	}
	return nil
}
func (e *Engine) Body(id int64, response bool) *Body {
	item := e.Exchange(id)
	if item == nil {
		return nil
	}
	data := item.requestBody
	encoding := item.RequestHeader.Get("Content-Encoding")
	if response {
		data = item.responseBody
		encoding = item.ResponseHeader.Get("Content-Encoding")
	}
	return &Body{Data: base64.StdEncoding.EncodeToString(data), Encoding: encoding, Truncated: data == nil}
}
