package mitm

import (
	"context"
	"encoding/json"
	"errors"
	"time"
)

func (e *Engine) rewriteJSON(r rule, body []byte) ([]byte, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 100*time.Millisecond)
	defer cancel()
	select {
	case scriptBudget <- struct{}{}:
		defer func() { <-scriptBudget }()
	case <-ctx.Done():
		return nil, ctx.Err()
	}
	var input any
	if err := json.Unmarshal(body, &input); err != nil {
		return nil, err
	}
	iter := r.jq.RunWithContext(ctx, input)
	value, ok := iter.Next()
	if !ok {
		return nil, errors.New("jq produced no JSON value")
	}
	if err, ok := value.(error); ok {
		return nil, err
	}
	if extra, ok := iter.Next(); ok {
		if err, ok := extra.(error); ok {
			return nil, err
		}
		return nil, errors.New("jq must produce exactly one JSON value")
	}
	result, err := json.Marshal(value)
	if err != nil {
		return nil, err
	}
	if int64(len(result)) > e.maxBody {
		return nil, errors.New("jq output exceeds body limit")
	}
	return result, nil
}
