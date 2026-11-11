package core

import (
	"net"
	"time"

	"github.com/metacubex/mihomo/common/atomic"
	C "github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/tunnel/statistic"
)

type mitmTracker struct {
	net.Conn `json:"-"`
	*statistic.TrackerInfo
}

func newMitmTracker(conn C.ConnContext) *mitmTracker {
	return &mitmTracker{Conn: conn.Conn(), TrackerInfo: &statistic.TrackerInfo{UUID: conn.ID(), Metadata: conn.Metadata().Clone(), Start: time.Now(), Chain: C.Chain{"MITM"}, ProviderChain: C.Chain{}, UploadTotal: atomic.NewInt64(0), DownloadTotal: atomic.NewInt64(0)}}
}
func (t *mitmTracker) ID() string                    { return t.UUID.String() }
func (t *mitmTracker) Info() *statistic.TrackerInfo  { return t.TrackerInfo }
func (t *mitmTracker) Chains() C.Chain               { return t.Chain }
func (t *mitmTracker) ProviderChains() C.Chain       { return t.ProviderChain }
func (t *mitmTracker) AppendToChains(C.ProxyAdapter) {}
func (t *mitmTracker) RemoteDestination() string     { return t.Metadata.RemoteAddress() }
func (t *mitmTracker) Close() error                  { statistic.DefaultManager.Leave(t); return t.Conn.Close() }
func (t *mitmTracker) Read(data []byte) (int, error) {
	n, err := t.Conn.Read(data)
	t.UploadTotal.Add(int64(n))
	return n, err
}
func (t *mitmTracker) Write(data []byte) (int, error) {
	n, err := t.Conn.Write(data)
	t.DownloadTotal.Add(int64(n))
	return n, err
}
