package mitm

import (
	"bytes"
	"compress/flate"
	"compress/gzip"
	"compress/zlib"
	"io"
	"net/http"
	"strings"

	"github.com/andybalholm/brotli"
)

func (e *Engine) responseBody(response *http.Response) ([]byte, error) {
	raw, err := readBoundedBody(&response.Body, e.maxBody)
	if err != nil || raw == nil {
		return nil, err
	}
	encoding := strings.ToLower(strings.TrimSpace(response.Header.Get("Content-Encoding")))
	if encoding == "" || encoding == "identity" {
		return raw, nil
	}
	var reader io.Reader
	var closer io.Closer
	switch encoding {
	case "gzip":
		decoded, e := gzip.NewReader(bytes.NewReader(raw))
		if e != nil {
			return nil, e
		}
		reader, closer = decoded, decoded
	case "deflate":
		decoded, e := zlib.NewReader(bytes.NewReader(raw))
		if e == nil {
			reader, closer = decoded, decoded
		} else {
			decoded := flate.NewReader(bytes.NewReader(raw))
			reader, closer = decoded, decoded
		}
	case "br":
		reader = brotli.NewReader(bytes.NewReader(raw))
	default:
		return nil, nil
	}
	if closer != nil {
		defer closer.Close()
	}
	data, err := io.ReadAll(io.LimitReader(reader, e.maxBody+1))
	if err != nil || int64(len(data)) > e.maxBody {
		return nil, err
	}
	setResponseBody(response, data)
	return data, nil
}
