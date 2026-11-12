import ClashCore
import Darwin
import Foundation

final class TunnelMemoryMonitor {
  private let queue = DispatchQueue(label: "TunnelMemoryMonitor", qos: .utility)
  private var timer: DispatchSourceTimer?
  private var stage = "starting"
  private var samples: [[String: Any]] = []
  private var peak: UInt64 = 0
  private var reclaimPolicy = TunnelMemoryReclaimPolicy()

  func start(directory: URL?, id: String) {
    queue.async {
      self.timer?.cancel()
      self.samples = []
      self.peak = 0
      self.reclaimPolicy = TunnelMemoryReclaimPolicy()
      let timer = DispatchSource.makeTimerSource(queue: self.queue)
      timer.schedule(deadline: .now(), repeating: .seconds(1), leeway: .milliseconds(100))
      timer.setEventHandler { [weak self] in
        autoreleasepool { self?.sample(directory: directory, id: id) }
      }
      self.timer = timer
      timer.resume()
    }
  }

  func setStage(_ stage: String) {
    queue.async { self.stage = stage }
  }

  func stop() {
    queue.async {
      self.timer?.cancel()
      self.timer = nil
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
    samples.append([
      "timestamp": now.timeIntervalSince1970, "stage": stage,
      "footprint-bytes": footprint, "reclaim-requested": reclaim,
    ])
    if samples.count > 32 { samples.removeFirst() }
    if let directory, let data = try? JSONSerialization.data(withJSONObject: [
      "id": id, "pid": ProcessInfo.processInfo.processIdentifier,
      "peak-footprint-bytes": peak, "samples": samples,
    ]) {
      try? data.write(to: directory.appendingPathComponent("vpn-memory.json"), options: .atomic)
    }
    if reclaim {
      MobileSetMitmPressure(1)
      MobileForceGC()
    }
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
