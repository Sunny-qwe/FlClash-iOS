package mitm

import (
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"net/url"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"time"

	"github.com/dlclark/regexp2"
)

type Rules struct {
	Hostname      []string `yaml:"hostname" json:"hostname"`
	URLRewrite    []string `yaml:"url-rewrite" json:"url-rewrite"`
	HeaderRewrite []string `yaml:"header-rewrite" json:"header-rewrite"`
	BodyRewrite   []string `yaml:"body-rewrite" json:"body-rewrite"`
	MapLocal      []string `yaml:"map-local" json:"map-local"`
	Script        []string `yaml:"script" json:"script"`
}

type Config struct {
	Rules         `yaml:",inline"`
	Enable        bool           `yaml:"enable"`
	DecryptTLS    bool           `yaml:"decrypt-tls"`
	CAFingerprint string         `yaml:"ca-fingerprint"`
	SkipVerify    bool           `yaml:"skip-server-cert-verify"`
	AutoQUICBlock bool           `yaml:"auto-quic-block"`
	H2            bool           `yaml:"h2"`
	Limits        map[string]int `yaml:"limits"`
}

type pattern struct {
	plain    *regexp.Regexp
	extended *regexp2.Regexp
}

func compilePattern(text string) (pattern, error) {
	if len(text) > 8192 {
		return pattern{}, errors.New("pattern exceeds 8192 bytes")
	}
	if plain, err := regexp.Compile(text); err == nil {
		return pattern{plain: plain}, nil
	}
	extended, err := regexp2.Compile(text, regexp2.ECMAScript)
	if err != nil {
		return pattern{}, err
	}
	extended.MatchTimeout = 20 * time.Millisecond
	return pattern{extended: extended}, nil
}

func (p pattern) matches(text string) bool {
	if p.plain != nil {
		return p.plain.MatchString(text)
	}
	matched, err := p.extended.MatchString(text)
	return err == nil && matched
}

func (p pattern) replace(text, replacement string) (string, error) {
	if p.plain != nil {
		return p.plain.ReplaceAllString(text, replacement), nil
	}
	return p.extended.Replace(text, replacement, -1, -1)
}

type rule struct {
	match  pattern
	fields []string
	name   string
	params map[string]string
}

// Quotes delimit fields; regex backslashes must survive the module conversion.
func fields(text string, separator byte) ([]string, error) {
	var out []string
	start := 0
	var quote byte
	for i := 0; i < len(text); i++ {
		c := text[i]
		if quote != 0 {
			if c == '\\' && i+1 < len(text) {
				i++
				continue
			}
			if c == quote {
				quote = 0
			}
			continue
		}
		if c == '"' || c == '\'' {
			quote = c
			continue
		}
		if c == separator || separator == ' ' && (c == '\t' || c == '\r') {
			if part := strings.TrimSpace(text[start:i]); part != "" {
				out = append(out, unquote(part))
			}
			start = i + 1
		}
	}
	if quote != 0 {
		return nil, errors.New("unterminated quoted field")
	}
	if part := strings.TrimSpace(text[start:]); part != "" {
		out = append(out, unquote(part))
	}
	return out, nil
}

func unquote(text string) string {
	if len(text) < 2 {
		return text
	}
	if text[0] == '"' && text[len(text)-1] == '"' {
		var value string
		if json.Unmarshal([]byte(text), &value) == nil {
			return value
		}
		return text[1 : len(text)-1]
	}
	if text[0] == '\'' && text[len(text)-1] == '\'' {
		return text[1 : len(text)-1]
	}
	return text
}

func assignments(text string) (map[string]string, error) {
	parts, err := fields(text, ',')
	if err != nil {
		return nil, err
	}
	out := map[string]string{}
	for _, part := range parts {
		key, value, ok := strings.Cut(part, "=")
		if !ok {
			return nil, fmt.Errorf("expected key=value: %s", part)
		}
		out[strings.TrimSpace(key)] = unquote(strings.TrimSpace(value))
	}
	return out, nil
}

func parseRule(kind, line string) (rule, error) {
	var r rule
	if kind == "hostname" {
		host := strings.TrimPrefix(strings.ToLower(strings.TrimSpace(line)), "-")
		if host == "" || strings.ContainsAny(host, " /\\\t\r\n:@") {
			return r, errors.New("expected a hostname or wildcard hostname")
		}
		return r, nil
	}
	if kind == "script" {
		name, rest, ok := strings.Cut(line, "=")
		if !ok {
			return r, errors.New("expected script name = options")
		}
		params, err := assignments(rest)
		if err != nil {
			return r, err
		}
		r.name = strings.TrimSpace(name)
		r.params = params
		switch params["type"] {
		case "http-request", "http-response":
			r.match, err = compilePattern(params["pattern"])
			if err != nil {
				return r, err
			}
		case "generic":
		default:
			return r, errors.New("supported script types: http-request, http-response, generic; scheduled/event scripts are not supported")
		}
		if params["script-path"] == "" {
			return r, errors.New("missing downloaded script-path")
		}
		return r, nil
	}
	parts, err := fields(line, ' ')
	if err != nil {
		return r, err
	}
	minimum := map[string]int{"url-rewrite": 2, "header-rewrite": 4, "body-rewrite": 4, "map-local": 2}[kind]
	if minimum == 0 || len(parts) < minimum {
		return r, errors.New("incomplete or unknown rewrite rule")
	}
	patternIndex := 0
	if kind == "header-rewrite" || kind == "body-rewrite" {
		if parts[0] != "http-request" && parts[0] != "http-response" {
			if kind != "body-rewrite" || len(parts) < 4 {
				return r, errors.New("expected http-request or http-response")
			}
			// Surge/Loon modules commonly use the legacy form:
			//   pattern response-body-replace-regex match replacement
			// Normalize it to the core representation used by rewriteBody.
			phase := ""
			switch parts[1] {
			case "request-body-replace-regex":
				phase = "http-request"
			case "response-body-replace-regex":
				phase = "http-response"
			default:
				return r, errors.New("expected http-request or http-response")
			}
			parts = []string{phase, parts[0], parts[2], strings.Join(parts[3:], " ")}
		}
		patternIndex = 1
	}
	r.match, err = compilePattern(parts[patternIndex])
	if err != nil {
		return r, err
	}
	r.fields = parts
	switch kind {
	case "url-rewrite":
		if len(parts) == 2 {
			switch parts[1] {
			case "reject", "reject-200", "reject-dict", "reject-array", "reject-img", "reject-tinygif":
			default:
				return r, errors.New("unsupported reject action")
			}
		} else if len(parts) == 3 && parts[2] == "header" {
			target, parseErr := url.Parse(parts[1])
			if parseErr != nil || target.Scheme == "" || target.Host == "" || target.Scheme != "http" && target.Scheme != "https" {
				if parseErr == nil {
					parseErr = errors.New("target must be an absolute HTTP URL")
				}
				return r, fmt.Errorf("invalid URL rewrite target: %w", parseErr)
			}
		} else {
			code, e := strconv.Atoi(parts[len(parts)-1])
			if e != nil || code < 300 || code > 399 {
				return r, errors.New("only HTTP redirects (3xx) are supported")
			}
		}
	case "header-rewrite":
		switch parts[2] {
		case "header-del":
		case "header-add", "header-replace":
			if len(parts) < 5 {
				return r, errors.New("missing header value")
			}
		case "header-replace-regex":
			if len(parts) < 6 {
				return r, errors.New("missing header pattern/replacement")
			}
			if _, err = compilePattern(parts[4]); err != nil {
				return r, err
			}
		default:
			return r, errors.New("unsupported header action")
		}
	case "body-rewrite":
		if _, err = compilePattern(parts[2]); err != nil {
			return r, err
		}
	case "map-local":
		r.params = map[string]string{}
		for _, part := range parts[1:] {
			key, value, ok := strings.Cut(part, "=")
			if !ok {
				return r, errors.New("expected map-local key=value")
			}
			r.params[key] = unquote(value)
		}
		switch r.params["data-type"] {
		case "text", "file", "base64", "tiny-gif":
		default:
			return r, errors.New("unsupported map-local data-type")
		}
		if status := r.params["status-code"]; status != "" {
			code, e := strconv.Atoi(status)
			if e != nil || code < 200 || code > 599 {
				return r, errors.New("invalid status-code")
			}
		}
	}
	return r, nil
}

func (r Rules) lists() map[string][]string {
	return map[string][]string{"hostname": r.Hostname, "url-rewrite": r.URLRewrite, "header-rewrite": r.HeaderRewrite, "body-rewrite": r.BodyRewrite, "map-local": r.MapLocal, "script": r.Script}
}

func Validate(rules Rules) map[string]map[int]string {
	issues := map[string]map[int]string{}
	for kind, lines := range rules.lists() {
		for index, line := range lines {
			if _, err := parseRule(kind, line); err != nil {
				if issues[kind] == nil {
					issues[kind] = map[int]string{}
				}
				issues[kind][index] = err.Error()
			}
		}
	}
	return issues
}

func readResource(home, name string, limit int64) ([]byte, error) {
	if name == "" || filepath.Base(name) != name || strings.ContainsAny(name, "/\\:") {
		return nil, errors.New("resource must be a downloaded filename")
	}
	root, err := filepath.EvalSymlinks(filepath.Join(home, "mitm", "resources"))
	if err != nil {
		return nil, err
	}
	path, err := filepath.EvalSymlinks(filepath.Join(root, name))
	if err != nil {
		return nil, err
	}
	rel, err := filepath.Rel(root, path)
	if err != nil || rel == ".." || strings.HasPrefix(rel, ".."+string(filepath.Separator)) {
		return nil, errors.New("resource outside MITM resources directory")
	}
	file, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer file.Close()
	info, err := file.Stat()
	if err != nil {
		return nil, err
	}
	if !info.Mode().IsRegular() || info.Size() > limit {
		return nil, errors.New("resource exceeds size limit")
	}
	return os.ReadFile(path)
}

func (r rule) localBody(home string, max int64) ([]byte, error) {
	switch r.params["data-type"] {
	case "file":
		return readResource(home, r.params["data"], max)
	case "base64":
		if int64(base64.StdEncoding.DecodedLen(len(r.params["data"]))) > max {
			return nil, errors.New("map-local body exceeds limit")
		}
		return base64.StdEncoding.DecodeString(r.params["data"])
	case "tiny-gif":
		return base64.StdEncoding.DecodeString("R0lGODlhAQABAAD/ACwAAAAAAQABAAACADs=")
	default:
		if int64(len(r.params["data"])) > max {
			return nil, errors.New("map-local body exceeds limit")
		}
		return []byte(r.params["data"]), nil
	}
}
