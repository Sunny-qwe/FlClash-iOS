import Foundation

struct CertificateProfileResponse {
  let path: String
  let profile: Data

  func response(to request: Data) -> Data? {
    guard request.count <= 8192,
      let text = String(data: request, encoding: .utf8),
      text.contains("\r\n\r\n") else { return nil }
    let firstLine = text.components(separatedBy: "\r\n")[0]
    let valid = firstLine == "GET \(path) HTTP/1.1" || firstLine == "GET \(path) HTTP/1.0"
    let body = valid ? profile : Data()
    let header = "HTTP/1.1 \(valid ? "200 OK" : "404 Not Found")\r\n"
      + "Content-Type: application/x-apple-aspen-config\r\n"
      + "Content-Disposition: attachment; filename=FlClash-CA.mobileconfig\r\n"
      + "Cache-Control: no-store\r\nConnection: close\r\nContent-Length: \(body.count)\r\n\r\n"
    return Data(header.utf8) + body
  }
}

#if canImport(UIKit)
import Network
import UIKit

@MainActor
final class CertificateProfileServer {
  private var listener: NWListener?
  private var connections: [UUID: NWConnection] = [:]
  private var expiry: Timer?
  private var backgroundTask = UIBackgroundTaskIdentifier.invalid
  private var completion: ((Error?) -> Void)?

  func install(_ profile: Data, completion: @escaping (Error?) -> Void) {
    stop()
    self.completion = completion
    do {
      let parameters = NWParameters.tcp
      parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
      let listener = try NWListener(using: parameters)
      let response = CertificateProfileResponse(
        path: "/\(UUID().uuidString)/FlClash.mobileconfig", profile: profile
      )
      self.listener = listener
      backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Certificate download") {
        Task { @MainActor in self.stop() }
      }
      expiry = Timer.scheduledTimer(withTimeInterval: 120, repeats: false) { _ in
        Task { @MainActor in self.stop() }
      }
      listener.stateUpdateHandler = { [weak self, weak listener] state in
        MainActor.assumeIsolated {
          guard let self, let listener, self.listener === listener else { return }
          switch state {
          case .ready:
            guard let port = listener.port,
              let url = URL(string: "http://127.0.0.1:\(port.rawValue)\(response.path)") else {
              self.stop()
              return
            }
            UIApplication.shared.open(url) { opened in
              guard self.listener === listener else { return }
              if opened { self.finish(nil) } else { self.stop() }
            }
          case .failed(let error):
            self.finish(error)
            self.stop()
          default: break
          }
        }
      }
      listener.newConnectionHandler = { [weak self] connection in
        MainActor.assumeIsolated {
          guard let self, self.connections.count < 4 else { connection.cancel(); return }
          let id = UUID()
          self.connections[id] = connection
          connection.start(queue: .main)
          self.receive(connection, id: id, data: Data(), response: response)
        }
      }
      listener.start(queue: .main)
    } catch {
      finish(error)
      stop()
    }
  }

  private func receive(_ connection: NWConnection, id: UUID, data: Data, response: CertificateProfileResponse) {
    connection.receive(minimumIncompleteLength: 1, maximumLength: 8193) { [weak self] bytes, _, ended, error in
      MainActor.assumeIsolated {
        guard let self else { return }
        let received = data + (bytes ?? Data())
        if let payload = response.response(to: received) {
          connection.send(content: payload, completion: .contentProcessed { _ in
            MainActor.assumeIsolated {
              connection.cancel()
              self.connections.removeValue(forKey: id)
            }
          })
        } else if error != nil || ended || received.count > 8192 {
          connection.cancel()
          self.connections.removeValue(forKey: id)
        } else {
          self.receive(connection, id: id, data: received, response: response)
        }
      }
    }
  }

  private func finish(_ error: Error?) {
    let callback = completion
    completion = nil
    callback?(error)
  }

  private func stop() {
    listener?.cancel()
    listener = nil
    connections.values.forEach { $0.cancel() }
    connections.removeAll()
    expiry?.invalidate()
    expiry = nil
    if backgroundTask != .invalid {
      UIApplication.shared.endBackgroundTask(backgroundTask)
      backgroundTask = .invalid
    }
    finish(NSError(domain: "FlClash.Certificate", code: 1,
      userInfo: [NSLocalizedDescriptionKey: "Could not open the certificate download. Please try again."]))
  }
}
#endif
