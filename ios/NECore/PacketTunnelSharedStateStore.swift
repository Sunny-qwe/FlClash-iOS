import Foundation

enum PacketTunnelEnvironment {
  static let extensionBundleIdentifier = Bundle.main.bundleIdentifier!
  static let baseBundleIdentifier = String(
    extensionBundleIdentifier.dropLast(".NECore".count)
  )
  static let appGroupIdentifier = "group.\(baseBundleIdentifier)"
  static let controlKind = "\(baseBundleIdentifier).Widget"
  static let eventNotificationName =
    "\(extensionBundleIdentifier).event"
}

final class PacketTunnelSharedStateStore {
  static var inMemorySharedState: [String: Any]?

  private let sharedStateFile = "shared_state.json"
  private let runTimeFile = "run_time"

  func loadVPNOptions() -> PacketTunnelVPNOptions? {
    if let rawOptions = sharedState()?["vpnOptions"] as? [String: Any],
       let data = try? JSONSerialization.data(withJSONObject: rawOptions),
       let opts = try? JSONDecoder().decode(PacketTunnelVPNOptions.self, from: data) {
      return opts
    }
    // Sideload/fallback defaults when shared state file is not reachable across sandboxes
    let fallbackDict: [String: Any] = [
      "port": 7890,
      "ipv6": false,
      "dnsHijacking": true,
      "systemProxy": false,
      "bypassDomain": [] as [String],
      "stack": "gvisor",
      "routeAddress": ["0.0.0.0/1", "128.0.0.0/1"],
      "mtu": 9000,
      "congestionController": ""
    ]
    if let data = try? JSONSerialization.data(withJSONObject: fallbackDict) {
      return try? JSONDecoder().decode(PacketTunnelVPNOptions.self, from: data)
    }
    return nil
  }

  func loadSetupParams() -> String? {
    if let setupParams = sharedState()?["setupParams"] as? [String: Any],
       let data = try? JSONSerialization.data(withJSONObject: setupParams),
       let str = String(data: data, encoding: .utf8), !str.isEmpty {
      return str
    }
    return "{}"
  }

  // The key spelling is a contract with the Go wrapper's InitParams.
  func makeInitParams() -> String {
    let payload: [String: Any] = [
      "home-dir": appGroupDirectory()?.path ?? "",
      "version": 0,
    ]
    let data = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
    return String(data: data, encoding: .utf8) ?? "{}"
  }

  func appGroupDirectory() -> URL? {
    FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier:
        PacketTunnelEnvironment.appGroupIdentifier
    ) ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
  }

  func saveRunTime() {
    guard let url = appGroupDirectory()?.appendingPathComponent(runTimeFile)
    else {
      return
    }
    try? String(Int(Date().timeIntervalSince1970 * 1000))
      .write(to: url, atomically: true, encoding: .utf8)
  }

  func clearRunTime() {
    guard let url = appGroupDirectory()?.appendingPathComponent(runTimeFile)
    else {
      return
    }
    try? FileManager.default.removeItem(at: url)
  }

  private func sharedState() -> [String: Any]? {
    if let memory = Self.inMemorySharedState {
      return memory
    }
    guard
      let url = appGroupDirectory()?.appendingPathComponent(sharedStateFile),
      let data = try? Data(contentsOf: url)
    else {
      return nil
    }
    return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
  }
}

struct PacketTunnelVPNOptions: Decodable {
  private static let defaultMTU = 9000
  // Below 1280 the system drops the IPv6 address.
  private static let mtuRange = 1280...65535

  let port: Int
  let ipv6: Bool
  let dnsHijacking: Bool
  let systemProxy: Bool
  let bypassDomain: [String]
  let stack: String
  let routeAddress: [String]
  let mtu: Int
  let congestionController: String

  var tunMTU: Int {
    mtu > 0
      ? min(max(mtu, Self.mtuRange.lowerBound), Self.mtuRange.upperBound)
      : Self.defaultMTU
  }

  private enum CodingKeys: String, CodingKey {
    case port
    case ipv6
    case dnsHijacking
    case systemProxy
    case bypassDomain
    case stack
    case routeAddress
    case mtu
    case congestionController
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    port = try container.decodeIfPresent(Int.self, forKey: .port) ?? 0
    ipv6 = try container.decodeIfPresent(Bool.self, forKey: .ipv6) ?? false
    dnsHijacking =
      try container.decodeIfPresent(Bool.self, forKey: .dnsHijacking) ?? false
    systemProxy =
      try container.decodeIfPresent(Bool.self, forKey: .systemProxy) ?? false
    bypassDomain =
      try container.decodeIfPresent([String].self, forKey: .bypassDomain) ?? []
    stack = try container.decodeIfPresent(String.self, forKey: .stack) ?? ""
    routeAddress =
      try container.decodeIfPresent([String].self, forKey: .routeAddress) ?? []
    mtu = try container.decodeIfPresent(Int.self, forKey: .mtu) ?? 0
    congestionController =
      try container.decodeIfPresent(
        String.self,
        forKey: .congestionController
      ) ?? ""
  }
}
