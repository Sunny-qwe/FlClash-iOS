package tunnel

import (
	"net"
	"sync"

	C "github.com/metacubex/mihomo/constant"
	icontext "github.com/metacubex/mihomo/context"
)

var interceptor struct {
	sync.RWMutex
	tcp func(C.ConnContext) bool
	udp func(*C.Metadata) bool
}

// The wrapper owns HTTP processing; the tunnel retains routing and dial ownership.
func SetInterceptors(tcp func(C.ConnContext) bool, udp func(*C.Metadata) bool) {
	interceptor.Lock()
	interceptor.tcp, interceptor.udp = tcp, udp
	interceptor.Unlock()
}

func interceptTCP(conn C.ConnContext) bool {
	interceptor.RLock()
	hook := interceptor.tcp
	interceptor.RUnlock()
	return hook != nil && hook(conn)
}

func interceptUDP(metadata *C.Metadata) bool {
	interceptor.RLock()
	hook := interceptor.udp
	interceptor.RUnlock()
	return hook != nil && hook(metadata)
}

func HandleTCPConnWithoutInterception(conn net.Conn, metadata *C.Metadata) {
	handleTCPConnWithInterception(icontext.NewConnContext(conn, metadata), false)
}
