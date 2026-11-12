import Foundation
import NetworkExtension

@MainActor
final class TunnelManagerStore {
  var manager = NETunnelProviderManager()
  func loadManager(createIfNeeded: Bool = true) async throws -> NETunnelProviderManager? { manager }
  func isManagedConnection(_ connection: NEVPNConnection) -> Bool { true }
  func isCachedConnection(_ connection: NEVPNConnection) -> Bool { manager.connection === connection }
  func invalidateCachedManager(forPreferenceError error: Error) -> Bool { false }
}

@main
struct TunnelLifecycleTests {
  @MainActor
  static func settle() async {
    for _ in 0..<100 { await Task.yield() }
  }

  @MainActor
  static func main() async {
    let store = TunnelManagerStore()
    store.manager.connection.status = .connected
    var starts = 0
    var stops = 0
    var reports: [TunnelTarget] = []
    var diagnostics: [String] = []
    let coordinator = TunnelCoordinator(
      managerStore: store,
      onTunnelStateChanged: { reports.append($0) },
      onExternalStart: { starts += 1 },
      onExternalStop: { stops += 1 },
      onFailure: { preconditionFailure("Unexpected failure: \($0)") },
      onDiagnostic: { diagnostics.append($0) }
    )
    coordinator.requestStatusRefresh(notifyExternal: false)
    await settle()
    for _ in 0..<10 {
      coordinator.requestStatusRefresh(notifyExternal: true)
      await settle()
    }
    precondition(starts == 0 && stops == 0)
    precondition(reports == [.running])
    precondition(store.manager.connection.startCount == 0 && store.manager.connection.stopCount == 0)

    let old = NETunnelProviderManager()
    old.connection.status = .disconnected
    let ignored = coordinator.handleTunnelStatusNotification(Notification(name: Notification.Name("status"), object: old.connection))
    precondition(!ignored && reports == [.running] && coordinator.isRunRequested)

    store.manager.connection.status = .reasserting
    precondition(coordinator.handleTunnelStatusNotification(Notification(name: Notification.Name("status"), object: store.manager.connection)))
    coordinator.requestStatusRefresh(notifyExternal: true)
    await settle()
    precondition(starts == 0 && stops == 0 && coordinator.isRunRequested)

    store.manager.connection.status = .disconnecting
    coordinator.handleTunnelStatusNotification(Notification(name: Notification.Name("status"), object: store.manager.connection))
    await settle()
    precondition(stops == 0 && reports == [.running])
    precondition(!diagnostics.contains { $0.contains("unexpected disconnect:") })
    store.manager.connection.status = .disconnected
    coordinator.requestStatusRefresh(notifyExternal: true)
    await settle()
    precondition(stops == 1 && reports == [.running, .stopped])
    precondition(diagnostics.contains { $0.contains("unexpected disconnect:") })
    coordinator.requestStatusRefresh(notifyExternal: true)
    await settle()
    precondition(stops == 1)
    precondition(diagnostics.filter { $0.contains("unexpected disconnect:") }.count == 1)

    coordinator.submitTunnelRequest(target: .running)
    await settle()
    precondition(starts == 1 && coordinator.isRunRequested)
    precondition(store.manager.connection.startCount == 1)
    precondition((store.manager.protocolConfiguration as? NETunnelProviderProtocol)?.disconnectOnSleep == false)
    coordinator.submitTunnelRequest(target: .stopped)
    await settle()
    precondition(stops == 2 && !coordinator.isRunRequested)
    precondition(store.manager.connection.stopCount == 1)
    precondition(diagnostics.filter { $0.contains("unexpected disconnect:") }.count == 1)

    coordinator.submitTunnelRequest(target: .running)
    await settle()
    precondition(coordinator.requestedTarget == nil && store.manager.connection.status == .connected)
    store.manager.connection.deferDisconnectError = true
    store.manager.connection.status = .disconnected
    coordinator.handleTunnelStatusNotification(Notification(name: Notification.Name("status"), object: store.manager.connection))
    await settle()
    precondition(store.manager.connection.disconnectReply != nil)
    coordinator.submitTunnelRequest(target: .stopped)
    await settle()
    store.manager.connection.disconnectReply?(NSError(domain: "BackgroundDisconnect", code: 12))
    await settle()
    precondition(diagnostics.contains { $0.contains("unexpected disconnect:") && $0.contains("BackgroundDisconnect") })
    print("Passed foreground deduplication, stale session rejection, reasserting, real disconnect diagnostics and explicit start/stop")
  }
}
