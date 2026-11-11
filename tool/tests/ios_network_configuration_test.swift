import Foundation
import NetworkExtension

@main
struct NetworkConfigurationTests {
  static func main() throws {
    let configuration = PacketTunnelNetworkConfiguration()
    for hijack in [false, true] {
      let payload: [String: Any] = [
        "port": 7890,
        "dnsHijacking": hijack,
        "systemProxy": true,
        "bypassDomain": ["localhost", "127.*", "10.7.*"],
        "routeAddress": ["0.0.0.0/1", "128.0.0.0/1"],
        "ipv6": true,
      ]
      let data = try JSONSerialization.data(withJSONObject: payload)
      let options = try JSONDecoder().decode(PacketTunnelVPNOptions.self, from: data)
      let settings = configuration.makeSettings(for: options)
      precondition(settings.dnsSettings?.matchDomains == [""])
      precondition(settings.dnsSettings?.matchDomainsNoSearch == true)
      precondition(settings.dnsSettings?.servers == ["198.18.0.2", "fdfe:dcba:9876::2"])
      precondition(settings.ipv4Settings?.includedRoutes?.count == 2)
      precondition(settings.ipv6Settings?.includedRoutes?.count == 1)
      precondition(settings.proxySettings?.matchDomains == [""])
      precondition(settings.proxySettings?.httpServer?.port == 7890)
      precondition(settings.proxySettings?.exceptionList?.contains("10.7.*") == true)
      precondition(configuration.tunDNS(for: options) == (hijack ? "0.0.0.0" : "198.18.0.2,fdfe:dcba:9876::2"))
    }
    let options = try JSONDecoder().decode(PacketTunnelVPNOptions.self, from: Data("{}".utf8))
    let settings = configuration.makeSettings(for: options)
    precondition(settings.proxySettings == nil)
    precondition(settings.ipv6Settings == nil)
    precondition(settings.ipv4Settings?.includedRoutes?.first?.destinationAddress == "0.0.0.0")
    precondition(settings.dnsSettings?.servers == ["198.18.0.2"])
    print("Verified full DNS/proxy scope, route transport and IPv4/IPv6 settings")
  }
}
