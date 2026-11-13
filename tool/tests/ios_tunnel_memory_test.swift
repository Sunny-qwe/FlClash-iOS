import Foundation

@main
struct TunnelMemoryTests {
  static func main() throws {
    var policy = TunnelMemoryReclaimPolicy()
    let start = Date(timeIntervalSince1970: 100)
    precondition(!policy.shouldReclaim(footprint: 31 * 1024 * 1024, now: start))
    precondition(policy.shouldReclaim(footprint: 32 * 1024 * 1024, now: start))
    precondition(!policy.shouldReclaim(footprint: 38 * 1024 * 1024, now: start.addingTimeInterval(4.9)))
    precondition(policy.shouldReclaim(footprint: 40 * 1024 * 1024, now: start.addingTimeInterval(4.9)))
    precondition(!policy.shouldReclaim(footprint: 44 * 1024 * 1024, now: start.addingTimeInterval(5)))
    precondition(policy.shouldReclaim(footprint: 44 * 1024 * 1024, now: start.addingTimeInterval(6)))
    var profiles = TunnelMemoryProfilePolicy()
    precondition(profiles.next(footprint: 48 * 1024 * 1024, stage: "running") == nil)
    precondition(profiles.next(footprint: 25 * 1024 * 1024, stage: "core-setup") == nil)
    precondition(profiles.next(footprint: 28 * 1024 * 1024, stage: "running") == "baseline")
    profiles.accept("baseline")
    precondition(profiles.next(footprint: 28 * 1024 * 1024, stage: "running") == nil)
    precondition(profiles.next(footprint: 34 * 1024 * 1024, stage: "running") == "pressure")
    profiles.accept("pressure")
    precondition(profiles.next(footprint: 38 * 1024 * 1024, stage: "running") == nil)
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let monitor = TunnelMemoryMonitor()
    let prior = directory.appendingPathComponent("vpn-memory.json")
    try Data("previous run".utf8).write(to: prior)
    monitor.start(directory: directory, id: "test")
    monitor.setStage("running")
    let file = directory.appendingPathComponent("vpn-memory.json")
    let deadline = Date().addingTimeInterval(5)
    var captured: [String: Any]?
    while Date() < deadline {
      if let data = try? Data(contentsOf: file),
         let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
         payload["id"] as? String == "test" {
        captured = payload
        break
      }
      Thread.sleep(forTimeInterval: 0.01)
    }
    monitor.stop()
    guard let payload = captured else { preconditionFailure("new run did not persist diagnostics") }
    precondition(payload["id"] as? String == "test")
    let samples = payload["samples"] as! [[String: Any]]
    precondition(!samples.isEmpty && samples.count <= 60)
    precondition((samples[0]["footprint-bytes"] as? UInt64 ?? 0) > 0)
    let core = samples[0]["core"] as! [String: Any]
    precondition(core["heap-allocated-bytes"] as? Int == 1234)
    precondition((core["mitm"] as? [String: Int])?["active-scripts"] == 1)
    precondition(core["events"] == nil)
    precondition((payload["core-events"] as? [[String: String]])?.first?["kind"] == "script.start")
    let previous = try String(contentsOf: directory.appendingPathComponent("vpn-memory.json.previous"), encoding: .utf8)
    precondition(previous == "previous run")
    print("Tunnel memory policy and diagnostic passed")
  }
}
