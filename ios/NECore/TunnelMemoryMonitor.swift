import ClashCore
import Darwin
import Foundation

final class TunnelMemoryMonitor {
  private let queue = DispatchQueue(label: "TunnelMemoryMonitor", qos: .utility)
  private var timer: DispatchSourceTimer?
  private var stage = "starting"
  private var samples: [[String: Any]] = []
  private var lifecycleEvents: [[String: Any]] = []
  private var directory: URL?
  private var runID = ""
  private var profilePolicy = TunnelMemoryProfilePolicy()
  private var peak: UInt64 = 0
  private var reclaimPolicy = TunnelMemoryReclaimPolicy()

  func start(directory: URL?, id: String) {
    queue.async {
      self.timer?.cancel()
      self.directory = directory
      self.runID = id
      if let directory {
        let current = directory.appendingPathComponent("vpn-memory.json")
        let previous = directory.appendingPathComponent("vpn-memory.json.previous")
        if FileManager.default.fileExists(atPath: current.path) {
          try? FileManager.default.removeItem(at: previous)
          try? FileManager.default.moveItem(at: current, to: previous)
        }
      }
      self.samples = []
      self.lifecycleEvents = []
      self.peak = 0
      self.reclaimPolicy = TunnelMemoryReclaimPolicy()
      self.profilePolicy = TunnelMemoryProfilePolicy()
      let timer = DispatchSource.makeTimerSource(queue: self.queue)
      timer.schedule(deadline: .now(), repeating: .seconds(1), leeway: .milliseconds(100))
      timer.setEventHandler { [weak self] in
        autoreleasepool { self?.sample(directory: directory, id: id) }
      }
      self.timer = timer
      timer.resume()
    }
  }

  func setStage(_ stage: String, error: Error? = nil) {
    queue.async {
      self.stage = stage
      var event: [String: Any] = ["timestamp": Date().timeIntervalSince1970, "stage": stage]
      if let error {
        event["error-domain"] = (error as NSError).domain
        event["error-code"] = (error as NSError).code
      }
      self.lifecycleEvents.append(event)
      if self.lifecycleEvents.count > 64 { self.lifecycleEvents.removeFirst() }
      if let directory = self.directory { self.sample(directory: directory, id: self.runID) }
    }
  }

  func stop() {
    queue.async {
      self.timer?.cancel()
      self.timer = nil
      self.directory = nil
    }
  }

  private func sample(directory: URL?, id: String) {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let result = withUnsafeMutablePointer(to: &info) {
      $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
        task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
      }
    }
    guard result == KERN_SUCCESS else { return }
    let now = Date()
    let footprint = info.phys_footprint
    peak = max(peak, footprint)
    let reclaim = reclaimPolicy.shouldReclaim(footprint: footprint, now: now)
    var core = MobileGetMemoryDiagnostics()
      .data(using: .utf8)
      .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
    let events = core.removeValue(forKey: "events") ?? []
    samples.append([
      "timestamp": now.timeIntervalSince1970, "stage": stage,
      "footprint-bytes": footprint, "reclaim-requested": reclaim,
      "core": core,
    ])
    if samples.count > 60 { samples.removeFirst() }
    if let directory, let data = try? JSONSerialization.data(withJSONObject: [
      "id": id, "pid": ProcessInfo.processInfo.processIdentifier,
      "peak-footprint-bytes": peak, "samples": samples,
      "core-events": events, "lifecycle-events": lifecycleEvents,
      "os-version": ProcessInfo.processInfo.operatingSystemVersionString,
      "bundle-version": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
    ]) {
      try? data.write(to: directory.appendingPathComponent("vpn-memory.json"), options: .atomic)
    }
    if let directory, let kind = profilePolicy.next(footprint: footprint, stage: stage),
       MobileRequestMemoryProfile(directory.path, id, kind) {
      profilePolicy.accept(kind)
    }
    if reclaim {
      MobileSetMitmPressure(1)
      MobileForceGC()
    }
  }
}

struct TunnelMemoryProfilePolicy {
  private var baseline = false
  private var pressure = false

  func next(footprint: UInt64, stage: String) -> String? {
    guard footprint < 40 * 1024 * 1024 else { return nil }
    if !baseline && stage == "running" { return "baseline" }
    if !pressure && footprint >= 32 * 1024 * 1024 { return "pressure" }
    return nil
  }

  mutating func accept(_ kind: String) {
    if kind == "baseline" { baseline = true }
    if kind == "pressure" { pressure = true }
  }
}

struct TunnelMemoryReclaimPolicy {
  private var lastReclaim = Date.distantPast

  mutating func shouldReclaim(footprint: UInt64, now: Date) -> Bool {
    guard footprint >= 36 * 1024 * 1024, now.timeIntervalSince(lastReclaim) >= 5 else { return false }
    lastReclaim = now
    return true
  }
}
