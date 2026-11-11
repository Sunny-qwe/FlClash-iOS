package core

import (
	"strings"

	"go.yaml.in/yaml/v3"
)

func normalizeRealityProxies(document *yaml.Node) bool {
	root, err := documentMapping(document)
	if err != nil {
		return false
	}
	proxies := resolveAlias(mappingValue(root, "proxies"))
	if proxies == nil || proxies.Kind != yaml.SequenceNode {
		return false
	}
	changed := false
	for _, node := range proxies.Content {
		proxy := resolveAlias(node)
		if proxy.Kind != yaml.MappingNode {
			continue
		}
		kind := resolveAlias(mappingValue(proxy, "type"))
		if kind == nil || (kind.Value != "vless" && kind.Value != "vmess") {
			continue
		}
		reality := resolveAlias(mappingValue(proxy, "reality-opts"))
		if reality == nil || reality.Kind != yaml.MappingNode {
			continue
		}
		key := resolveAlias(mappingValue(reality, "public-key"))
		if key == nil || key.ShortTag() != "!!str" || strings.TrimSpace(key.Value) == "" {
			continue
		}
		if tls := resolveAlias(mappingValue(proxy, "tls")); tls == nil || isNull(tls) {
			setMappingValue(proxy, "tls", &yaml.Node{Kind: yaml.ScalarNode, Tag: "!!bool", Value: "true"})
			changed = true
		}
		fingerprint := resolveAlias(mappingValue(proxy, "client-fingerprint"))
		if fingerprint == nil || isNull(fingerprint) || (fingerprint.ShortTag() == "!!str" && strings.TrimSpace(fingerprint.Value) == "") {
			setMappingValue(proxy, "client-fingerprint", &yaml.Node{Kind: yaml.ScalarNode, Tag: "!!str", Value: "chrome"})
			changed = true
		}
	}
	return changed
}
