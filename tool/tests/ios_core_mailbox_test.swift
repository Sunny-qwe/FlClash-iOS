import Foundation

@main
struct CoreMailboxTests {
  static func wait(_ signal: DispatchSemaphore) {
    precondition(signal.wait(timeout: .now() + 10) == .success, "Mailbox test timed out")
  }

  static func receive(_ client: CoreMailboxClient, _ data: Data) throws -> Data {
    let signal = DispatchSemaphore(value: 0)
    var answer: Result<Data, Error>?
    client.send(data) { result in answer = result; signal.signal() }
    wait(signal)
    return try answer!.get()
  }

  static func main() throws {
    if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "serve" {
      let server = CoreMailboxServer(directory: URL(fileURLWithPath: CommandLine.arguments[2])) { data, reply in
        reply(data)
      }
      try server.start()
      RunLoop.current.run()
      withExtendedLifetime(server) {}
      return
    }

    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let client = CoreMailboxClient(directory: { directory })
    let server = CoreMailboxServer(directory: directory) { data, reply in reply(data) }
    try server.start()
    let large = Data(repeating: 65, count: 262144)
    let largeReply = try receive(client, large)
    precondition(largeReply == large)

    let completed = DispatchSemaphore(value: 0)
    var count = 0
    for index in 0..<64 {
      let input = Data("request-\(index)".utf8)
      client.send(input) { response in
        precondition((try? response.get()) == input)
        count += 1
        if count == 64 { completed.signal() }
      }
    }
    wait(completed)
    client.cancel()
    server.stop()

    let held = DispatchSemaphore(value: 0)
    let expired = DispatchSemaphore(value: 0)
    let silent = CoreMailboxServer(directory: directory) { _, _ in held.signal() }
    try silent.start()
    let impatient = CoreMailboxClient(directory: { directory }, timeout: 0.1)
    impatient.send(Data("timeout".utf8)) { response in
      guard case .failure(let error) = response,
        (error as? CoreMailboxError) == .timedOut else { preconditionFailure("Expected timeout") }
      expired.signal()
    }
    wait(held)
    wait(expired)
    let cancelled = DispatchSemaphore(value: 0)
    client.send(Data("cancel".utf8)) { response in
      guard case .failure(let error) = response,
        (error as? CoreMailboxError) == .stopped else { preconditionFailure("Expected stop") }
      cancelled.signal()
    }
    wait(held)
    client.cancel()
    wait(cancelled)
    silent.stop()

    let absent = CoreMailboxClient(directory: { nil })
    do {
      _ = try receive(absent, Data("unavailable".utf8))
      preconditionFailure("Missing shared directory must fail")
    } catch CoreMailboxError.unavailable {}

    let process = Process()
    process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
    process.arguments = ["serve", directory.path]
    try process.run()
    defer { process.terminate(); process.waitUntilExit() }
    let ready = directory.appendingPathComponent("core-rpc/ready")
    let readyDeadline = Date().addingTimeInterval(10)
    while !FileManager.default.fileExists(atPath: ready.path) && Date() < readyDeadline {
      Thread.sleep(forTimeInterval: 0.01)
    }
    precondition(FileManager.default.fileExists(atPath: ready.path))
    let crossProcessReply = try receive(client, large)
    precondition(crossProcessReply == large)
    client.cancel()
    print("Verified cross-process VPN RPC, large replies, concurrent correlation, timeout, disconnect and absent shared directory")
  }
}
