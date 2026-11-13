package adapter

import "context"

// timedOut follows hub/route's getProxyDelay, which answers 504 rather than 503
// once the test's context is done.
type UrlTestCheck func(url string, name string, delay uint16, timedOut bool)

var UrlTestHook UrlTestCheck

var UrlTestAcquireHook func(context.Context) (func(), error)

type urlTestSlotKey struct{}

func AcquireURLTestSlot(ctx context.Context) (context.Context, func(), error) {
	if UrlTestAcquireHook == nil || ctx.Value(urlTestSlotKey{}) != nil {
		return ctx, func() {}, nil
	}
	release, err := UrlTestAcquireHook(ctx)
	if err != nil {
		return ctx, nil, err
	}
	return context.WithValue(ctx, urlTestSlotKey{}, true), release, nil
}
