import Darwin
import Foundation

private enum CoreMailbox {
  static func root(_ directory: URL) -> URL {
    directory.appendingPathComponent("core-rpc", isDirectory: true)
  }

  static func session(_ root: URL) throws -> URL {
    let data = try Data(contentsOf: root.appendingPathComponent("ready"))
    guard let name = String(data: data, encoding: .utf8), UUID(uuidString: name) != nil else {
      throw CoreMailboxError.unavailable
    }
    return root.appendingPathComponent(name, isDirectory: true)
  }

  static func files(_ directory: URL, extension suffix: String) -> [URL] {
    ((try? FileManager.default.contentsOfDirectory(
      at: directory, includingPropertiesForKeys: nil
    )) ?? []).filter { $0.pathExtension == suffix }.sorted {
      $0.lastPathComponent < $1.lastPathComponent
    }
  }
}

public enum CoreMailboxError: LocalizedError, Equatable {
  case unavailable
  case stopped
  case timedOut

  public var errorDescription: String? {
    switch self {
    case .unavailable: return "VPN 扩展的控制通道尚未就绪，请重新连接 VPN。"
    case .stopped: return "VPN 已断开，控制请求已取消。"
    case .timedOut: return "VPN 扩展未在限定时间内回复控制请求。"
    }
  }
}

private final class CoreMailboxDirectoryWatch {
  private let source: DispatchSourceFileSystemObject

  init(directory: URL, queue: DispatchQueue, changed: @escaping () -> Void) throws {
    let descriptor = open(directory.path, O_EVTONLY)
    guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
    source = DispatchSource.makeFileSystemObjectSource(
      fileDescriptor: descriptor, eventMask: .write, queue: queue
    )
    source.setEventHandler(handler: changed)
    source.setCancelHandler { close(descriptor) }
    source.resume()
  }

  deinit { source.cancel() }
}

public final class CoreMailboxServer {
  public typealias Handler = (Data, @escaping (Data) -> Void) -> Void

  private let queue = DispatchQueue(label: "FlClash.CoreMailbox.server")
  private let root: URL
  private let session: URL
  private let handler: Handler
  private var watch: CoreMailboxDirectoryWatch?
  private var active = false

  public init(directory: URL, handler: @escaping Handler) {
    root = CoreMailbox.root(directory)
    session = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
    self.handler = handler
  }

  public func start() throws {
    try queue.sync {
      guard !active else { return }
      try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
      watch = try CoreMailboxDirectoryWatch(directory: session, queue: queue) { [weak self] in
        self?.drain()
      }
      active = true
      do {
        try Data(session.lastPathComponent.utf8).write(to: root.appendingPathComponent("ready"), options: .atomic)
      } catch {
        active = false
        watch = nil
        throw error
      }
      for old in (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
      where old.lastPathComponent != session.lastPathComponent && UUID(uuidString: old.lastPathComponent) != nil {
        try? FileManager.default.removeItem(at: old)
      }
    }
  }

  public func stop() {
    queue.sync {
      active = false
      watch = nil
      if (try? CoreMailbox.session(root).lastPathComponent) == session.lastPathComponent {
        try? FileManager.default.removeItem(at: root.appendingPathComponent("ready"))
      }
      try? FileManager.default.removeItem(at: session)
    }
  }

  private func drain() {
    guard active else { return }
    for file in CoreMailbox.files(session, extension: "request") {
      guard let data = try? Data(contentsOf: file) else { continue }
      do { try FileManager.default.removeItem(at: file) } catch { continue }
      guard !data.isEmpty else { continue }
      handler(data) { [weak self] response in
        guard let self else { return }
        self.queue.async {
          guard self.active else { return }
          try? response.write(to: file.deletingPathExtension().appendingPathExtension("reply"), options: .atomic)
        }
      }
    }
  }
}

public final class CoreMailboxClient {
  private struct Pending {
    let file: URL
    let deadline: DispatchWorkItem
    let reply: (Result<Data, Error>) -> Void
  }

  private let queue = DispatchQueue(label: "FlClash.CoreMailbox.client")
  private let directory: () -> URL?
  private let timeout: TimeInterval
  private var session: URL?
  private var watch: CoreMailboxDirectoryWatch?
  private var sequence: UInt64 = 0
  private var pending: [String: Pending] = [:]

  public init(directory: @escaping () -> URL?, timeout: TimeInterval = 180) {
    self.directory = directory
    self.timeout = timeout
  }

  public func send(_ data: Data, reply: @escaping (Result<Data, Error>) -> Void) {
    queue.async {
      do {
        guard let directory = self.directory() else { throw CoreMailboxError.unavailable }
        let session = try CoreMailbox.session(CoreMailbox.root(directory))
        if session != self.session {
          self.cancelPending()
          self.watch = try CoreMailboxDirectoryWatch(directory: session, queue: self.queue) { [weak self] in
            self?.drain()
          }
          self.session = session
        }
        self.sequence &+= 1
        let name = String(format: "%020llu", self.sequence) + "-" + UUID().uuidString
        let file = session.appendingPathComponent(name).appendingPathExtension("request")
        let deadline = DispatchWorkItem { [weak self] in
          self?.finish(name, result: .failure(CoreMailboxError.timedOut))
        }
        self.pending[name] = Pending(file: file, deadline: deadline, reply: reply)
        do {
          try data.write(to: file, options: .atomic)
          self.queue.asyncAfter(deadline: .now() + self.timeout, execute: deadline)
        } catch {
          self.finish(name, result: .failure(error))
        }
      } catch { reply(.failure(error)) }
    }
  }

  public func cancel() {
    queue.async {
      self.cancelPending()
      self.watch = nil
      self.session = nil
    }
  }

  private func drain() {
    guard let session else { return }
    for file in CoreMailbox.files(session, extension: "reply") {
      let name = file.deletingPathExtension().lastPathComponent
      guard let data = try? Data(contentsOf: file) else { continue }
      try? FileManager.default.removeItem(at: file)
      guard !data.isEmpty else {
        finish(name, result: .failure(CoreMailboxError.unavailable))
        continue
      }
      finish(name, result: .success(data))
    }
  }

  private func finish(_ name: String, result: Result<Data, Error>) {
    guard let request = pending.removeValue(forKey: name) else { return }
    request.deadline.cancel()
    try? FileManager.default.removeItem(at: request.file)
    try? FileManager.default.removeItem(at: request.file.deletingPathExtension().appendingPathExtension("reply"))
    request.reply(result)
  }

  private func cancelPending() {
    for name in Array(pending.keys) { finish(name, result: .failure(CoreMailboxError.stopped)) }
  }
}
