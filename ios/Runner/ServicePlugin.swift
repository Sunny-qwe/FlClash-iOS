import Flutter
import Foundation
import NetworkExtension
import Security
import Shared
import os

/// The iOS side of the channels Android's ServicePlugin and TilePlugin serve.
/// Start and stop are optimistic: the tunnel coordinator owns the intent and
/// serializes the work, and only the revision-stamped `stopped` flows back.
@MainActor
final class ServicePlugin {
  private static let packageName = "com.follow.clash"
  private static var instance: ServicePlugin?
  private static var pendingAction: VPNAction?

  private let channel: FlutterMethodChannel
  private let coreChannel: FlutterMethodChannel
  private let tileChannel: FlutterMethodChannel
  private let sharedStateStore = SharedStateStore()
  private let certificateInstaller = CertificateProfileServer()
  private let router = CoreMessageRouter()
  private let eventRelay: CoreEventRelay
  private var tunnelController: TunnelController!
  private var commandRevision = 0
  private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "",
    category: "ServicePlugin"
  )

  static func register(with messenger: FlutterBinaryMessenger) {
    let plugin = ServicePlugin(messenger: messenger)
    instance = plugin
    NEHelper.actionHandler = { action in
      ServicePlugin.request(action)
      return true
    }
    if let action = pendingAction {
      pendingAction = nil
      plugin.perform(action)
    }
  }

  /// Before the engine is up only the latest intent survives: a toggle flips a
  /// pending start or stop, and two toggles cancel out.
  static func request(_ action: VPNAction) {
    guard let instance else {
      switch (action, pendingAction) {
      case (.toggle, .start?):
        pendingAction = .stop
      case (.toggle, .stop?):
        pendingAction = .start
      case (.toggle, .toggle?):
        pendingAction = nil
      default:
        pendingAction = action
      }
      return
    }
    instance.perform(action)
  }

  private init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: "\(Self.packageName)/service",
      binaryMessenger: messenger
    )
    // Serial: route.watch keeps the latest intent by the order calls reach the Core.
    coreChannel = FlutterMethodChannel(
      name: "\(Self.packageName)/core",
      binaryMessenger: messenger,
      codec: FlutterStandardMethodCodec.sharedInstance(),
      taskQueue: messenger.makeBackgroundTaskQueue?()
    )
    tileChannel = FlutterMethodChannel(
      name: "\(Self.packageName)/tile",
      binaryMessenger: messenger
    )
    eventRelay = CoreEventRelay(sharedStateStore: sharedStateStore)
    let router = router
    let eventRelay = eventRelay
    router.onEvent = { event in
      DispatchQueue.main.async {
        MainActor.assumeIsolated {
          eventRelay.deliver(event)
        }
      }
    }
    tunnelController = TunnelController(
      sharedStateStore: sharedStateStore,
      onSessionChanged: { session in
        router.useNetworkExtension(session)
      },
      onExternalStart: { [weak self] in
        self?.tileChannel.invokeMethod("start", arguments: nil)
      },
      onStopped: { [weak self] in
        self?.notifyStopped()
      },
      onFailure: { [weak self] error in
        guard let self else { return }
        let error = error as NSError
        self.channel.invokeMethod("startFailed", arguments: [
          "revision": self.commandRevision,
          "message": "\(error.localizedDescription) [\(error.domain):\(error.code)]",
        ])
      }
    )
    channel.setMethodCallHandler { [weak self] call, result in
      MainActor.assumeIsolated {
        guard let self else {
          result(FlutterMethodNotImplemented)
          return
        }
        self.handle(call, result: result)
      }
    }
    coreChannel.setMethodCallHandler { call, result in
      guard call.method == "invokeMethod" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let data = (call.arguments as? String)?.data(using: .utf8) else {
        result(
          FlutterError(
            code: "INVALID_ARGUMENT",
            message: "Method call payload must be a string",
            details: nil
          )
        )
        return
      }
      router.invoke(data) { response in
        result(FlutterStandardTypedData(bytes: response))
      }
    }
    tunnelController.startObserving()
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "installMitmProfile":
      guard let profile = call.arguments as? String,
        let data = profile.data(using: .utf8), data.count <= 65536,
        let document = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
        let payloads = document["PayloadContent"] as? [[String: Any]],
        payloads.count == 1, payloads[0]["PayloadType"] as? String == "com.apple.security.root",
        payloads[0]["PayloadContent"] is Data else {
        result(FlutterError(code: "INVALID_PROFILE", message: "Expected a public CA profile", details: nil))
        return
      }
      certificateInstaller.install(data) { error in
        if let error {
          result(FlutterError(code: "CERTIFICATE_DOWNLOAD", message: error.localizedDescription, details: nil))
        } else {
          result(nil)
        }
      }
    case "checkMitmTrust":
      guard let pem = call.arguments as? String else {
        result(false)
        return
      }
      let encoded = pem.split(separator: "\n")
        .filter { !$0.hasPrefix("-----") }
        .joined()
      guard let data = Data(base64Encoded: encoded, options: .ignoreUnknownCharacters),
        let certificate = SecCertificateCreateWithData(nil, data as CFData)
      else {
        result(false)
        return
      }
      DispatchQueue.global(qos: .userInitiated).async {
        let policy = SecPolicyCreateSSL(true, "mitm-check.flclash.invalid" as CFString)
        var trust: SecTrust?
        let created = SecTrustCreateWithCertificates(certificate, policy, &trust) == errSecSuccess
        let trusted = created && trust.map { SecTrustEvaluateWithError($0, nil) } == true
        DispatchQueue.main.async { result(trusted) }
      }
    case "init":
      eventRelay.start { [weak self] event, delivered in
        self?.channel.invokeMethod(
          "event",
          arguments: FlutterStandardTypedData(bytes: event)
        ) { reply in
          delivered(!(reply is FlutterError) && (reply as AnyObject?) !== FlutterMethodNotImplemented)
        }
      }
      result("")
    case "shutdown":
      eventRelay.stop()
      result(true)
    case "getRunTime":
      Task {
        result(await tunnelController.getRunTime())
      }
    case "syncState":
      guard let data = (call.arguments as? String)?.data(using: .utf8),
        sharedStateStore.saveSharedState(data)
      else {
        result(FlutterError(code: "SHARED_STATE_ERROR", message: "无法保存 VPN 配置，请检查应用与 VPN 扩展的 App Group 签名权限。", details: nil))
        return
      }
      result("")
    case "getAppGroupDirectory":
      result(NEHelper.appGroupDirectory?.path)
    case "start":
      guard NEHelper.appGroupDirectory != nil else {
        result(FlutterError(
          code: "APP_GROUP_UNAVAILABLE",
          message: "签名后没有可访问的共享目录。请在签名时保留主应用与 VPN 扩展相同的 App Groups 权限。",
          details: nil
        ))
        return
      }
      commandRevision = call.arguments as? Int ?? commandRevision
      tunnelController.start()
      result(true)
    case "stop":
      commandRevision = call.arguments as? Int ?? commandRevision
      tunnelController.stop()
      result(true)
    case "supportsAlternateIcons":
      result(UIApplication.shared.supportsAlternateIcons)
    case "getAlternateIconName":
      result(UIApplication.shared.alternateIconName)
    case "setAlternateIconName":
      let iconName = call.arguments as? String
      let nameToSet = (iconName == nil || iconName?.isEmpty == true || iconName == "default" || iconName == "AppIcon-Classic") ? nil : iconName
      if UIApplication.shared.alternateIconName == nameToSet {
        result(true)
        return
      }
      guard UIApplication.shared.supportsAlternateIcons else {
        result(FlutterError(code: "ICONS_UNAVAILABLE", message: "当前安装包没有可用的备用图标声明，请安装包含完整图标资源的版本。", details: nil))
        return
      }
      DispatchQueue.main.async {
        UIApplication.shared.setAlternateIconName(nameToSet) { error in
          if let error = error {
            let error = error as NSError
            DispatchQueue.main.async {
              result(FlutterError(code: "SET_ICON_ERROR", message: "\(error.localizedDescription) [\(error.domain):\(error.code)]", details: ["domain": error.domain, "code": error.code]))
            }
          } else {
            DispatchQueue.main.async { result(true) }
          }
        }
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // Flutter drives a start itself, so its Core is set up before the tunnel
  // comes up. Until Flutter listens, the extension sets up its own Core from
  // the shared state, as Android does from its preferences.
  private func perform(_ action: VPNAction) {
    switch action {
    case .start:
      tileChannel.invokeMethod("start", arguments: nil) { [weak self] reply in
        if (reply as AnyObject?) === FlutterMethodNotImplemented {
          self?.tunnelController.start()
        }
      }
    case .stop:
      tunnelController.stop()
    case .toggle:
      perform(tunnelController.isRunRequested ? .stop : .start)
    }
  }

  private func notifyStopped() {
    guard !tunnelController.isRunRequested else {
      return
    }
    log("stopped revision=\(commandRevision)")
    channel.invokeMethod("stopped", arguments: commandRevision)
  }

  private func log(_ message: String) {
    logger.debug("\(message, privacy: .public)")
  }
}
