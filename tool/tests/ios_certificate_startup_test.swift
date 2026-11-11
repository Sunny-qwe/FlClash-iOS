import Foundation

@main
enum CertificateStartupTests {
  static func main() throws {
    let body = Data("<plist>public certificate only</plist>".utf8)
    let endpoint = CertificateProfileResponse(path: "/random/CA.mobileconfig", profile: body)
    let request = Data("GET /random/CA.mobileconfig HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n".utf8)
    let response = endpoint.response(to: request)!
    let text = String(decoding: response, as: UTF8.self)
    precondition(text.contains("200 OK\r\n"))
    precondition(text.contains("Content-Type: application/x-apple-aspen-config\r\n"))
    precondition(text.contains("Content-Length: \(body.count)\r\n"))
    precondition(response.suffix(body.count) == body)
    for line in ["GET / HTTP/1.1", "POST /random/CA.mobileconfig HTTP/1.1", "GET /wrong/CA.mobileconfig HTTP/1.1"] {
      let rejected = endpoint.response(to: Data("\(line)\r\n\r\n".utf8))!
      precondition(String(decoding: rejected, as: UTF8.self).contains("404 Not Found"))
      precondition(!String(decoding: rejected, as: UTF8.self).contains("<plist>"))
    }
    precondition(endpoint.response(to: Data("GET /random/CA.mobileconfig".utf8)) == nil)
    precondition(endpoint.response(to: Data(repeating: 65, count: 8193)) == nil)
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    TunnelStartupDiagnostic.write(directory: directory, id: "first", stage: "core-setup")
    precondition(TunnelStartupDiagnostic.read(directory: directory, id: "other") == nil)
    precondition(TunnelStartupDiagnostic.read(directory: directory, id: "first")?.stage == "core-setup")
    let failure = NSError(domain: "Core", code: 7, userInfo: [NSLocalizedDescriptionKey: "CA missing"])
    TunnelStartupDiagnostic.write(directory: directory, id: "first", stage: "startup-failed", error: failure)
    precondition(TunnelStartupDiagnostic.read(directory: directory, id: "first")?.detail == "CA missing [Core:7]")
    TunnelStartupDiagnostic.write(directory: directory, id: "second", stage: "launch-requested")
    precondition(TunnelStartupDiagnostic.read(directory: directory, id: "first") == nil)
    precondition(TunnelStartupDiagnostic.read(directory: directory, id: "second")?.detail == nil)
    print("Passed certificate HTTP response and per-attempt VPN failure persistence checks")
  }
}
