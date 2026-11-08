//go:build ios || (darwin && !android)

package platform

import "net"

func ShouldBlockConnection() bool {
	return false
}

func RequiresProtectCallback() bool {
	return false
}

func CloseRejectedTunDescriptor(fd int) {
}

func QuerySocketUidFromProcFs(source, target net.Addr) int {
	return -1
}
