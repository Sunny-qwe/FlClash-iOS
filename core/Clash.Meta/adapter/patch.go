package adapter

import "context"

// timedOut follows hub/route's getProxyDelay, which answers 504 rather than 503
// once the test's context is done.
type UrlTestCheck func(url string, name string, delay uint16, timedOut bool)

var UrlTestHook UrlTestCheck

var UrlTestAcquireHook func(context.Context) (func(), error)
