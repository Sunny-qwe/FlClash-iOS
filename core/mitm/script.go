package mitm

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/dop251/goja"
)

type ScriptOutput struct {
	Logs   []string `json:"logs"`
	Result string   `json:"result"`
	Error  string   `json:"error"`
}

func scriptHeaders(header http.Header) map[string]string {
	out := map[string]string{}
	for key, values := range header {
		out[key] = strings.Join(values, ", ")
	}
	return out
}

func scriptBinaryBody(params map[string]string) bool {
	return strings.EqualFold(strings.TrimSpace(params["binary-body-mode"]), "true")
}

func scriptBodyValue(vm *goja.Runtime, body []byte, binary bool) any {
	if binary {
		constructor, _ := goja.AssertConstructor(vm.Get("Uint8Array"))
		value, err := constructor(nil, vm.ToValue(vm.NewArrayBuffer(append([]byte{}, body...))))
		if err != nil {
			panic(err)
		}
		return value
	}
	return string(body)
}

func scriptBodyBytes(value any) ([]byte, error) {
	switch value := value.(type) {
	case string:
		return []byte(value), nil
	case []byte:
		return append([]byte{}, value...), nil
	case goja.ArrayBuffer:
		return append([]byte{}, value.Bytes()...), nil
	}
	return nil, errors.New("body must be a string, Uint8Array or ArrayBuffer")
}

func scriptHeaderValue(vm *goja.Runtime, header http.Header, full bool) any {
	if full {
		out := vm.NewObject()
		for key, values := range header {
			items := make([]any, len(values))
			for i, value := range values {
				items[i] = value
			}
			_ = out.Set(key, vm.NewArray(items...))
		}
		return out
	}
	return scriptHeaders(header)
}

func (e *Engine) runScript(r rule, request *http.Request, response *http.Response, body []byte) (result map[string]any, output ScriptOutput) {
	output.Logs = []string{}
	timeout := 500 * time.Millisecond
	if seconds, err := strconv.ParseFloat(r.params["timeout"], 64); err == nil && seconds > 0 {
		timeout = time.Duration(seconds * float64(time.Second))
		if timeout > 2*time.Second {
			timeout = 2 * time.Second
		}
	}
	parent := context.Background()
	if request != nil {
		parent = request.Context()
	}
	ctx, cancel := context.WithTimeout(parent, timeout)
	defer cancel()
	select {
	case scriptBudget <- struct{}{}:
		defer func() { <-scriptBudget }()
	case <-ctx.Done():
		output.Error = "script wait time limit exceeded"
		return
	}
	source, err := readResource(e.home, r.params["script-path"], 256<<10)
	if err != nil {
		output.Error = err.Error()
		return
	}
	vm := goja.New()
	vm.SetMaxCallStackSize(256)
	stopInterrupt := context.AfterFunc(ctx, func() { vm.Interrupt("script time limit exceeded") })
	defer stopInterrupt()
	defer func() {
		if p := recover(); p != nil {
			output.Error = fmt.Sprint(p)
			result = nil
		}
	}()
	log := func(call goja.FunctionCall) goja.Value {
		if len(output.Logs) < 64 {
			parts := []string{}
			for _, arg := range call.Arguments {
				value := arg.String()
				if len(value) > 2048 {
					value = value[:2048]
				}
				parts = append(parts, value)
			}
			output.Logs = append(output.Logs, strings.Join(parts, " "))
		}
		return goja.Undefined()
	}
	_ = vm.Set("console", map[string]any{"log": log, "info": log, "warn": log, "error": log})
	done := false
	_ = vm.Set("$done", func(call goja.FunctionCall) goja.Value {
		if done {
			return goja.Undefined()
		}
		done = true
		if !goja.IsUndefined(call.Argument(0)) && !goja.IsNull(call.Argument(0)) {
			if err := vm.ExportTo(call.Argument(0), &result); err != nil {
				output.Error = err.Error()
			}
		}
		return goja.Undefined()
	})
	_ = vm.Set("$argument", r.params["argument"])
	if text := r.params["argument-json"]; text != "" {
		var argument any
		if err := json.Unmarshal([]byte(text), &argument); err != nil {
			output.Error = "invalid argument-json"
			return
		}
		_ = vm.Set("$argument", argument)
	}
	_ = vm.Set("$environment", map[string]any{"flclash-version": "0.9.3", "supported-script-types": []string{"http-request", "http-response", "generic"}})
	_ = vm.Set("$notification", map[string]any{"post": log})
	_ = vm.Set("$notify", log)
	_ = vm.Set("atob", func(value string) (string, error) {
		decoded, err := base64.StdEncoding.DecodeString(value)
		return string(decoded), err
	})
	_ = vm.Set("btoa", func(value string) string { return base64.StdEncoding.EncodeToString([]byte(value)) })
	timers := e.installScriptHost(vm, ctx, r.name)
	if request != nil {
		object := map[string]any{"url": request.URL.String(), "method": request.Method, "headers": scriptHeaderValue(vm, request.Header, r.params["full-header-mode"] == "true")}
		if r.params["requires-body"] == "true" && response == nil && body != nil {
			object["body"] = scriptBodyValue(vm, body, scriptBinaryBody(r.params))
			if scriptBinaryBody(r.params) {
				object["bodyBytes"] = object["body"]
			}
		}
		_ = vm.Set("$request", object)
	}
	if response != nil {
		object := map[string]any{"status": response.StatusCode, "statusCode": response.StatusCode, "headers": scriptHeaderValue(vm, response.Header, r.params["full-header-mode"] == "true")}
		if body != nil {
			object["body"] = scriptBodyValue(vm, body, scriptBinaryBody(r.params))
			if scriptBinaryBody(r.params) {
				object["bodyBytes"] = object["body"]
			}
		}
		_ = vm.Set("$response", object)
	}
	_, err = vm.RunScript(r.params["script-path"], string(source))
	if err == nil {
		err = runScriptTimers(ctx, timers, &done)
	}
	if err != nil {
		output.Error = err.Error()
		result = nil
		return
	}
	if !done {
		output.Error = "script did not call $done"
		result = nil
		return
	}
	if result != nil {
		bodies := []map[string]any{result}
		if nested, ok := result["response"].(map[string]any); ok {
			bodies = append(bodies, nested)
		}
		for _, object := range bodies {
			if value, ok := scriptResultBody(object); ok {
				data, err := scriptBodyBytes(value)
				if err != nil || int64(len(data)) > e.maxBody {
					output.Error = "script returned invalid or oversized body"
					result = nil
					return
				}
			}
		}
		data, err := json.Marshal(result)
		if err != nil || int64(len(data)) > e.maxBody {
			output.Error = "script output exceeds size limit"
			result = nil
			return
		}
		output.Result = string(data)
	}
	return
}

func (e *Engine) applyScripts(phase string, request *http.Request, response *http.Response, body []byte, actions *[]action) *http.Response {
	for _, r := range e.rules["script"] {
		if r.params["type"] != phase || !r.match.matches(request.URL.String()) {
			continue
		}
		if r.params["requires-body"] == "true" && body == nil {
			e.warn("MITM script " + r.name + " skipped: body is encoded or exceeds limit")
			continue
		}
		result, output := e.runScript(r, request, response, body)
		for _, line := range output.Logs {
			e.warn("MITM script " + r.name + ": " + line)
		}
		if output.Error != "" {
			e.warn("MITM script " + r.name + " failed; original request preserved: " + output.Error)
			*actions = append(*actions, action{Kind: "script-error", Phase: phase, Detail: r.name + ": " + output.Error})
			continue
		}
		if result == nil {
			continue
		}
		if nested, ok := result["response"].(map[string]any); ok && response == nil {
			return scriptResponse(nested, request)
		}
		if response == nil {
			if raw, ok := result["url"].(string); ok {
				u, err := scriptURL(raw)
				if err != nil {
					continue
				}
				request.URL = u
				request.Host = u.Host
			}
			if method, ok := result["method"].(string); ok && method != "" {
				request.Method = method
			}
			if headers, ok := result["headers"].(map[string]any); ok {
				request.Header = exportHeaders(headers)
			}
			if value, ok := scriptResultBody(result); ok {
				decoded, decodeErr := scriptBodyBytes(value)
				if decodeErr != nil {
					e.warn("MITM script " + r.name + " returned invalid binary body")
					continue
				}
				body = decoded
				setRequestBody(request, body)
			}
		} else {
			if headers, ok := result["headers"].(map[string]any); ok {
				response.Header = exportHeaders(headers)
			}
			if value, ok := scriptResultBody(result); ok {
				decoded, decodeErr := scriptBodyBytes(value)
				if decodeErr != nil {
					e.warn("MITM script " + r.name + " returned invalid binary body")
					continue
				}
				body = decoded
				setResponseBody(response, body)
			}
			if code := scriptStatus(result); code != 0 {
				response.StatusCode = code
			}
		}
		*actions = append(*actions, action{Kind: "script", Phase: phase, Detail: r.name})
	}
	return nil
}

func scriptResultBody(result map[string]any) (any, bool) {
	if body, ok := result["bodyBytes"]; ok {
		return body, true
	}
	body, ok := result["body"]
	return body, ok
}

func exportHeaders(values map[string]any) http.Header {
	out := http.Header{}
	for key, value := range values {
		switch value := value.(type) {
		case []any:
			for _, item := range value {
				out.Add(key, fmt.Sprint(item))
			}
		case []string:
			out[key] = append([]string{}, value...)
		default:
			out.Set(key, fmt.Sprint(value))
		}
	}
	return out
}
func scriptStatus(values map[string]any) int {
	for _, key := range []string{"status", "statusCode"} {
		if value, ok := values[key]; ok {
			text := fmt.Sprint(value)
			parts := strings.Fields(text)
			for _, part := range parts {
				if code, err := strconv.Atoi(part); err == nil && code >= 200 && code <= 599 {
					return code
				}
			}
		}
	}
	return 0
}
func scriptResponse(result map[string]any, request *http.Request) *http.Response {
	code := scriptStatus(result)
	if code == 0 {
		code = 200
	}
	headers := http.Header{}
	if h, ok := result["headers"].(map[string]any); ok {
		headers = exportHeaders(h)
	}
	value, _ := scriptResultBody(result)
	body, _ := scriptBodyBytes(value)
	return localResponse(code, body, headers, request)
}
func (e *Engine) RunScript(name string) (ScriptOutput, error) {
	for _, r := range e.rules["script"] {
		if r.name == name {
			if r.params["type"] != "generic" {
				return ScriptOutput{}, errors.New("HTTP scripts run only for matching requests")
			}
			_, output := e.runScript(r, nil, nil, nil)
			return output, nil
		}
	}
	return ScriptOutput{}, errors.New("script is not enabled or was rejected by validation")
}
