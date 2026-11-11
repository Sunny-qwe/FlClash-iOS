import ClashCore
import Darwin
import Foundation
import NetworkExtension
import WidgetKit
import os

final class PacketTunnelProvider: NEPacketTunnelProvider {
  private let sharedStateStore = PacketTunnelSharedStateStore()
  private let networkConfiguration = PacketTunnelNetworkConfiguration()
  private lazy var eventQueue = NECoreEventQueue(
    sharedStateStore: sharedStateStore
  )
  private var memoryPressureSource: DispatchSourceMemoryPressure?
  private let logger = Logger(
    subsystem: PacketTunnelEnvironment.extensionBundleIdentifier,
    category: "PacketTunnelProvider"
  )

  override func startTunnel(
    options: [String: NSObject]?,
    completionHandler: @escaping (Error?) -> Void
  ) {
    logger.info("startTunnel begin")
    sharedStateStore.clearRunTime()
    // A Network Extension process can be reused after a failed start. Do not
    // let a previous attempt's in-memory state override the fresh start data.
    PacketTunnelSharedStateStore.inMemorySharedState = nil
    reloadControls()

    if let jsonString = options?["sharedState"] as? String,
       let data = jsonString.data(using: .utf8),
       let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
      logger.info("startTunnel: loaded sharedState from start options")
      PacketTunnelSharedStateStore.inMemorySharedState = dict
      if let url = sharedStateStore.appGroupDirectory()?.appendingPathComponent("shared_state.json") {
        try? data.write(to: url, options: .atomic)
      }
    } else if let protoConfig = (protocolConfiguration as? NETunnelProviderProtocol)?.providerConfiguration,
              let jsonString = protoConfig["sharedState"] as? String,
              let data = jsonString.data(using: .utf8),
              let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
      logger.info("startTunnel: loaded sharedState from providerConfiguration")
      PacketTunnelSharedStateStore.inMemorySharedState = dict
      if let url = sharedStateStore.appGroupDirectory()?.appendingPathComponent("shared_state.json") {
        try? data.write(to: url, options: .atomic)
      }
    }

    guard sharedStateStore.appGroupDirectory() != nil,
      let vpnOptions = sharedStateStore.loadVPNOptions(),
      let setupParams = sharedStateStore.loadSetupParams() else {
      logger.error("startTunnel failed: missing vpnOptions from shared state")
      completionHandler(PacketTunnelProviderError.missingConfiguration)
      return
    }
    logger.info(
      "startTunnel stack=\(vpnOptions.stack, privacy: .public) ipv6=\(vpnOptions.ipv6, privacy: .public) dnsHijacking=\(vpnOptions.dnsHijacking, privacy: .public) systemProxy=\(vpnOptions.systemProxy, privacy: .public)"
    )

    setTunnelNetworkSettings(
      networkConfiguration.makeSettings(for: vpnOptions)
    ) { error in
      if let error {
        self.logger.error(
          "setTunnelNetworkSettings failed: \(error.localizedDescription, privacy: .public)"
        )
        completionHandler(error)
        return
      }
      guard
        let fileDescriptor = self.networkConfiguration.tunnelFileDescriptor()
      else {
        completionHandler(PacketTunnelProviderError.missingFileDescriptor)
        return
      }
      self.eventQueue.start()
      self.watchMemoryPressure()
      MobileQuickSetup(
        self.sharedStateStore.makeInitParams(),
        setupParams,
        CoreResultHandler { result in
          let message = String(data: result, encoding: .utf8) ?? ""
          guard message.isEmpty else {
            self.logger.error(
              "quickSetup failed: \(message, privacy: .public)"
            )
            self.eventQueue.stop()
            self.memoryPressureSource?.cancel()
            self.memoryPressureSource = nil
            MobileStopTun()
            completionHandler(PacketTunnelProviderError.setupFailed(message))
            return
          }
          completionHandler(
            self.startTun(fileDescriptor: fileDescriptor, options: vpnOptions)
          )
        }
      )
    }
  }

  private func startTun(
    fileDescriptor: Int32,
    options: PacketTunnelVPNOptions
  ) -> Error? {
    let tunOptions: [String: Any] = [
      "mtu": options.tunMTU,
      "congestion-controller": options.congestionController,
    ]
    guard
      let tunOptionsData = try? JSONSerialization.data(withJSONObject: tunOptions)
    else {
      return PacketTunnelProviderError.tunRejected
    }
    // Go owns and closes the descriptor it receives; NetworkExtension owns utun.
    let ownedDescriptor = dup(fileDescriptor)
    guard ownedDescriptor >= 0 else {
      return PacketTunnelProviderError.missingFileDescriptor
    }
    let started = MobileStartTun(
      ownedDescriptor,
      CoreTunHandler(),
      options.stack,
      networkConfiguration.tunAddress(for: options),
      networkConfiguration.tunDNS(for: options),
      String(data: tunOptionsData, encoding: .utf8)
    )
    logger.info("startTun result=\(started, privacy: .public)")
    guard started else {
      return PacketTunnelProviderError.tunRejected
    }
    sharedStateStore.saveRunTime()
    reloadControls()
    return nil
  }

  override func stopTunnel(
    with reason: NEProviderStopReason,
    completionHandler: @escaping () -> Void
  ) {
    logger.info("stopTunnel reason=\(reason.rawValue, privacy: .public)")
    sharedStateStore.clearRunTime()
    memoryPressureSource?.cancel()
    memoryPressureSource = nil
    eventQueue.stop()
    MobileStopTun()
    reloadControls()
    completionHandler()
  }

  override func handleAppMessage(
    _ messageData: Data,
    completionHandler: ((Data?) -> Void)?
  ) {
    eventQueue.markCoreResponsive()
    guard let completionHandler else {
      return
    }
    MobileInvokeMethod(
      String(data: messageData, encoding: .utf8),
      CoreResultHandler { response in
        completionHandler(response)
      }
    )
  }

  // jetsam ends the extension outright at its memory limit, with no
  // onTrimMemory to warn it first.
  private func watchMemoryPressure() {
    guard memoryPressureSource == nil else {
      return
    }
    let source = DispatchSource.makeMemoryPressureSource(
      eventMask: [.warning, .critical],
      queue: .global(qos: .utility)
    )
    source.setEventHandler {
      MobileForceGC()
    }
    source.resume()
    memoryPressureSource = source
  }

  private func reloadControls() {
    if #available(iOS 18.0, *) {
      ControlCenter.shared.reloadControls(
        ofKind: PacketTunnelEnvironment.controlKind
      )
    }
  }
}

private enum PacketTunnelProviderError: LocalizedError {
  case missingConfiguration
  case missingFileDescriptor
  case setupFailed(String)
  case tunRejected

  var errorDescription: String? {
    switch self {
    case .missingConfiguration:
      return "No configuration found."
    case .missingFileDescriptor:
      return "Could not find the tunnel file descriptor."
    case .setupFailed(let message):
      return message
    case .tunRejected:
      return "Core rejected the tun file descriptor."
    }
  }
}
