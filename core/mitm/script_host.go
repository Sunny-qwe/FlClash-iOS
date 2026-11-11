package mitm

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/dop251/goja"
)

var scriptStoreMu sync.Mutex

func (e *Engine) scriptState(name, key string, write *string) any {
	if len(key) > 256 || write != nil && len(*write) > 8192 {
		return false
	}
	scriptStoreMu.Lock()
	defer scriptStoreMu.Unlock()
	file := filepath.Join(e.home, "mitm", "script-state.json")
	state := map[string]string{}
	if info, err := os.Stat(file); err == nil && info.Size() <= 1<<20 {
		if data, err := os.ReadFile(file); err == nil {
			_ = json.Unmarshal(data, &state)
		}
	}
	entry := name + "\x00" + key
	if state == nil {
		state = map[string]string{}
	}
	if write == nil {
		if value, ok := state[entry]; ok {
			return value
		}
		return nil
	}
	if _, ok := state[entry]; !ok && len(state) >= 128 {
		return false
	}
	state[entry] = *write
	data, err := json.Marshal(state)
	if err != nil {
		return false
	}
	if err := os.MkdirAll(filepath.Dir(file), 0700); err != nil {
		return false
	}
	temp, err := os.CreateTemp(filepath.Dir(file), ".state-*")
	if err != nil {
		return false
	}
	defer os.Remove(temp.Name())
	if err = temp.Chmod(0600); err == nil {
		_, err = temp.Write(data)
	}
	if closeErr := temp.Close(); err == nil {
		err = closeErr
	}
	if err != nil {
		return false
	}
	return os.Rename(temp.Name(), file) == nil
}

func (e *Engine) scriptFetch(ctx context.Context, options goja.Value, method string) (map[string]any, error) {
	var values map[string]any
	if text, ok := options.Export().(string); ok {
		values = map[string]any{"url": text}
	} else {
		var ok bool
		values, ok = options.Export().(map[string]any)
		if !ok {
			return nil, errors.New("expected URL or request options")
		}
	}
	raw, _ := values["url"].(string)
	target, err := scriptURL(raw)
	if err != nil {
		return nil, err
	}
	if value, ok := values["method"].(string); ok {
		method = value
	}
	if method == "" {
		method = "GET"
	}
	body, _ := values["body"].(string)
	if int64(len(body)) > e.maxBody {
		return nil, errors.New("script request body exceeds limit")
	}
	request, err := http.NewRequestWithContext(ctx, method, target.String(), strings.NewReader(body))
	if err != nil {
		return nil, err
	}
	if headers, ok := values["headers"].(map[string]any); ok {
		request.Header = exportHeaders(headers)
	}
	stripHopHeaders(request.Header)
	client := &http.Client{Transport: e.transport, Timeout: 2 * time.Second}
	if redirect, ok := values["redir"].(bool); ok && !redirect {
		client.CheckRedirect = func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }
	}
	response, err := client.Do(request)
	if err != nil {
		return nil, err
	}
	defer response.Body.Close()
	data, err := io.ReadAll(io.LimitReader(response.Body, e.maxBody+1))
	if err != nil {
		return nil, err
	}
	if int64(len(data)) > e.maxBody {
		return nil, errors.New("script response body exceeds limit")
	}
	return map[string]any{"status": response.StatusCode, "statusCode": response.StatusCode, "headers": scriptHeaders(response.Header), "body": string(data)}, nil
}

type scriptTimer struct {
	id        int
	due       time.Time
	callback  goja.Callable
	arguments []goja.Value
}

func (e *Engine) installScriptHost(vm *goja.Runtime, ctx context.Context, name string) *[]scriptTimer {
	requests := 0
	fetch := func(options goja.Value, method string) (map[string]any, error) {
		requests++
		if requests > 4 {
			return nil, errors.New("script network request limit reached")
		}
		return e.scriptFetch(ctx, options, method)
	}
	client := map[string]any{}
	for _, method := range []string{"GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS"} {
		client[strings.ToLower(method)] = func(call goja.FunctionCall) goja.Value {
			callback, ok := goja.AssertFunction(call.Argument(1))
			if !ok {
				panic(vm.NewTypeError("HTTP callback is required"))
			}
			result, err := fetch(call.Argument(0), method)
			if err != nil {
				_, err = callback(goja.Undefined(), vm.ToValue(err.Error()), goja.Undefined(), goja.Undefined())
			} else {
				_, err = callback(goja.Undefined(), goja.Null(), vm.ToValue(result), vm.ToValue(result["body"]))
			}
			if err != nil {
				panic(vm.NewGoError(err))
			}
			return goja.Undefined()
		}
	}
	_ = vm.Set("$httpClient", client)
	_ = vm.Set("$task", map[string]any{"fetch": func(options goja.Value) *goja.Promise {
		promise, resolve, reject := vm.NewPromise()
		result, err := fetch(options, "")
		if err != nil {
			_ = reject(err.Error())
		} else {
			_ = resolve(result)
		}
		return promise
	}})
	read := func(key string) any { return e.scriptState(name, key, nil) }
	write := func(value, key string) bool {
		written, ok := e.scriptState(name, key, &value).(bool)
		return ok && written
	}
	_ = vm.Set("$persistentStore", map[string]any{"read": read, "write": write})
	_ = vm.Set("$prefs", map[string]any{"valueForKey": read, "setValueForKey": write})
	timers := []scriptTimer{}
	next := 0
	_ = vm.Set("setTimeout", func(call goja.FunctionCall) goja.Value {
		callback, ok := goja.AssertFunction(call.Argument(0))
		if !ok {
			panic(vm.NewTypeError("timer callback is required"))
		}
		if len(timers) >= 16 {
			panic(vm.NewGoError(errors.New("script timer limit reached")))
		}
		delay := call.Argument(1).ToInteger()
		if delay < 0 {
			delay = 0
		}
		if delay > 2000 {
			delay = 2000
		}
		next++
		var arguments []goja.Value
		if len(call.Arguments) > 2 {
			arguments = append(arguments, call.Arguments[2:]...)
		}
		timers = append(timers, scriptTimer{id: next, due: time.Now().Add(time.Duration(delay) * time.Millisecond), callback: callback, arguments: arguments})
		return vm.ToValue(next)
	})
	_ = vm.Set("clearTimeout", func(id int) {
		for i, timer := range timers {
			if timer.id == id {
				timers = append(timers[:i], timers[i+1:]...)
				return
			}
		}
	})
	return &timers
}

func runScriptTimers(ctx context.Context, timers *[]scriptTimer, done *bool) error {
	for runs := 0; !*done && len(*timers) > 0; runs++ {
		if runs >= 32 {
			return errors.New("script timer run limit reached")
		}
		index := 0
		for i, item := range *timers {
			if item.due.Before((*timers)[index].due) {
				index = i
			}
		}
		item := (*timers)[index]
		*timers = append((*timers)[:index], (*timers)[index+1:]...)
		wait := time.NewTimer(time.Until(item.due))
		select {
		case <-ctx.Done():
			wait.Stop()
			return fmt.Errorf("script time limit exceeded")
		case <-wait.C:
		}
		if _, err := item.callback(goja.Undefined(), item.arguments...); err != nil {
			return err
		}
	}
	return nil
}
