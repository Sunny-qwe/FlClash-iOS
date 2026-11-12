import Foundation

@main
struct TunnelMemoryTests {
  static func main() throws {
    var policy = TunnelMemoryReclaimPolicy()
    let start = Date(timeIntervalSince1970: 100)
    precondition(!policy.shouldReclaim(footprint: 35 * 1024 * 1024, now: start))
    precondition(policy.shouldReclaim(footprint: 36 * 1024 * 1024, now: start))
    precondition(!policy.shouldReclaim(footprint: 48 * 1024 * 1024, now: start.addingTimeInterval(4.9)))
    precondition(policy.shouldReclaim(footprint: 40 * 1024 * 1024, now: start.addingTimeInterval(5)))
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let monitor = TunnelMemoryMonitor()
    monitor.start(directory: directory, id: "test")
    monitor.setStage("running")
    let file = directory.appendingPathComponent("vpn-memory.json")
    let deadline = Date().addingTimeInterval(5)
    while !FileManager.default.fileExists(atPath: file.path) && Date() < deadline {
      Thread.sleep(forTimeInterval: 0.01)
    }
    monitor.stop()
    let payload = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
    precondition(payload["id"] as? String == "test")
    let samples = payload["samples"] as! [[String: Any]]
    precondition(!samples.isEmpty && samples.count <= 32)
    precondition((samples[0]["footprint-bytes"] as? UInt64 ?? 0) > 0)
    print("Tunnel memory policy and diagnostic passed")
  }
}
