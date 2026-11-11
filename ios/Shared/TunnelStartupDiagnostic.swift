import Foundation

public struct TunnelStartupDiagnostic: Codable {
  public let id: String
  public let stage: String
  public let detail: String?
  public let date: Date

  public static func write(directory: URL?, id: String, stage: String, error: Error? = nil) {
    guard let directory else { return }
    let detail = error.map { error -> String in
      let ns = error as NSError
      return String("\(ns.localizedDescription) [\(ns.domain):\(ns.code)]".prefix(2048))
    }
    let record = TunnelStartupDiagnostic(id: id, stage: stage, detail: detail, date: Date())
    guard let data = try? JSONEncoder().encode(record) else { return }
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try? data.write(to: directory.appendingPathComponent("vpn-startup.json"), options: .atomic)
  }

  public static func read(directory: URL?, id: String) -> TunnelStartupDiagnostic? {
    guard let directory,
      let data = try? Data(contentsOf: directory.appendingPathComponent("vpn-startup.json")),
      let record = try? JSONDecoder().decode(Self.self, from: data),
      record.id == id, Date().timeIntervalSince(record.date) < 180 else { return nil }
    return record
  }
}
