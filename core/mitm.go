package core

import (
	"context"
	"core/mitm"
	"encoding/binary"
	"errors"
	"net"
	"net/netip"
	"os"
	"strconv"
	"sync/atomic"
	"time"

	"github.com/metacubex/mihomo/component/sniffer"
	C "github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/log"
	"github.com/metacubex/mihomo/tunnel"
	"github.com/metacubex/mihomo/tunnel/statistic"
	"go.yaml.in/yaml/v3"
)

var mitmEngine atomic.Pointer[mitm.Engine]
var mitmCapture atomic.Bool

func init() {
	tunnel.SetInterceptors(func(conn C.ConnContext) bool {
		engine := mitmEngine.Load()
		if engine == nil {
			return false
		}
		metadata := conn.Metadata()
		if metadata.Host == "" && metadata.DstPort == 443 && engine.NeedsHostname() {
			connection := conn.Conn()
			_ = connection.SetReadDeadline(time.Now().Add(time.Second))
			if header, err := connection.Peek(5); err == nil && header[0] == 22 {
				length := int(binary.BigEndian.Uint16(header[3:5])) + 5
				if length <= connection.Reader().Size() {
					if hello, err := connection.Peek(length); err == nil {
						if hostname, err := sniffer.SniffTLS(hello); err == nil && hostname != nil && engine.Matches(*hostname) {
							metadata.Host = *hostname
						}
					}
				}
			}
			_ = connection.SetReadDeadline(time.Time{})
		}
		if !engine.MatchesEndpoint(metadata.Host, metadata.DstPort) || metadata.DstPort != 80 && metadata.DstPort != 443 {
			return false
		}
		tracker := newMitmTracker(conn)
		statistic.DefaultManager.Join(tracker)
		defer statistic.DefaultManager.Leave(tracker)
		return engine.Serve(tracker, metadata.Host, metadata.DstPort, conn.ID().String())
	}, func(metadata *C.Metadata) bool {
		engine := mitmEngine.Load()
		return engine != nil && engine.BlocksQUIC(metadata.Host, metadata.DstPort)
	})
}

func dialMitm(ctx context.Context, network, address string) (net.Conn, error) {
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	host, portText, err := net.SplitHostPort(address)
	if err != nil {
		return nil, err
	}
	port, err := strconv.ParseUint(portText, 10, 16)
	if err != nil {
		return nil, err
	}
	metadata := &C.Metadata{NetWork: C.TCP, Type: C.INNER, Host: host, DstPort: uint16(port)}
	if ip, err := netip.ParseAddr(host); err == nil {
		metadata.DstIP = ip
		metadata.Host = ""
	}
	client, server := net.Pipe()
	safeGo("mitm upstream", func() { tunnel.HandleTCPConnWithoutInterception(server, metadata) })
	return client, nil
}

func prepareMitm(base *SetupBase) (*mitm.Engine, error) {
	var data []byte
	if base != nil {
		data = []byte(base.Overlay)
	} else {
		var err error
		data, err = os.ReadFile(runningConfigPath())
		if err != nil {
			return nil, err
		}
	}
	var document struct {
		MITM mitm.Config `yaml:"mitm"`
	}
	if err := yaml.Unmarshal(data, &document); err != nil {
		return nil, err
	}
	return mitm.Reconfigure(mitmEngine.Load(), C.Path.HomeDir(), document.MITM, dialMitm, func(message string) { log.Warnln("%s", message) })
}

func activateMitm(engine *mitm.Engine) {
	engine.SetCapture(mitmCapture.Load())
	old := mitmEngine.Swap(engine)
	if old != nil && old != engine {
		old.Close()
	}
}
func activeMitm() (*mitm.Engine, error) {
	engine := mitmEngine.Load()
	if engine == nil {
		return nil, errors.New("MITM configuration is not active")
	}
	return engine, nil
}
func handleMitmCertificate() (*mitm.Certificate, error) { return mitm.GetCertificate(C.Path.HomeDir()) }
func handleMitmGenerateCertificate() (*mitm.Certificate, error) {
	return mitm.GenerateCertificate(C.Path.HomeDir())
}

type mitmHostParams struct {
	Host string `json:"host"`
}

func handleMitmIssueCertificate(params mitmHostParams) (string, error) {
	return mitm.IssueCertificate(C.Path.HomeDir(), params.Host)
}
func handleMitmRunScript(params NameParams) (mitm.ScriptOutput, error) {
	engine, err := activeMitm()
	if err != nil {
		return mitm.ScriptOutput{}, err
	}
	return engine.RunScript(params.Name)
}

type mitmConnectionParams struct {
	ID string `json:"id"`
}

func handleMitmExchanges(params mitmConnectionParams) mitm.ExchangeList {
	if engine := mitmEngine.Load(); engine != nil {
		return engine.Exchanges(params.ID)
	}
	return mitm.ExchangeList{Exchanges: []*mitm.Exchange{}}
}

type mitmExchangeParams struct {
	ID       int64 `json:"id"`
	Response bool  `json:"response"`
}

func handleMitmExchange(params mitmExchangeParams) *mitm.Exchange {
	if engine := mitmEngine.Load(); engine != nil {
		return engine.Exchange(params.ID)
	}
	return nil
}
func handleMitmBody(params mitmExchangeParams) *mitm.Body {
	if engine := mitmEngine.Load(); engine != nil {
		return engine.Body(params.ID, params.Response)
	}
	return nil
}
