import Foundation

public enum NEVPNStatus: Int {
  case invalid, disconnected, connecting, connected, reasserting, disconnecting
}

public final class NETunnelProviderProtocol {
  public var providerConfiguration: [String: Any]?
  public var disconnectOnSleep = true
  public init() {}
}

public class NEVPNConnection {
  public var status: NEVPNStatus = .disconnected
  public var startCount = 0
  public var stopCount = 0
  public var deferDisconnectError = false
  public var disconnectReply: ((Error?) -> Void)?
  public init() {}
  public func startVPNTunnel(options: [String: NSObject]?) throws {
    startCount += 1
    status = .connected
  }
  public func stopVPNTunnel() { stopCount += 1; status = .disconnected }
  public func fetchLastDisconnectError(completionHandler: @escaping (Error?) -> Void) {
    if deferDisconnectError { disconnectReply = completionHandler }
    else { completionHandler(NSError(domain: "TestDisconnect", code: 9)) }
  }
}

public final class NETunnelProviderSession: NEVPNConnection {}

public final class NETunnelProviderManager {
  public let connection = NETunnelProviderSession()
  public var protocolConfiguration: Any? = NETunnelProviderProtocol()
  public var isEnabled = false
  public var isOnDemandEnabled = false
  public init() {}
  public func saveToPreferences(completionHandler: @escaping @Sendable (Error?) -> Void) {
    completionHandler(nil)
  }
  public func loadFromPreferences(completionHandler: @escaping @Sendable (Error?) -> Void) {
    completionHandler(nil)
  }
}
