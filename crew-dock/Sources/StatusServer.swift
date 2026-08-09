import Foundation
import Network

/// Minimal HTTP listener for the one endpoint the orchestrator posts to:
///   POST /agent-status  {"character","message","state"}
/// Network.framework rather than a package — the demo Mac has no Xcode, so
/// anything with a dependency graph can't be built here.
final class StatusServer {
    struct Status {
        let character: String
        let message: String
        let state: String
    }

    private let listener: NWListener
    private let onStatus: (Status) -> Void

    init?(port: UInt16, onStatus: @escaping (Status) -> Void) {
        guard let p = NWEndpoint.Port(rawValue: port),
              let l = try? NWListener(using: .tcp, on: p) else { return nil }
        listener = l
        self.onStatus = onStatus
    }

    func start() {
        listener.newConnectionHandler = { [weak self] conn in
            conn.start(queue: .global())
            self?.receive(conn, buffer: Data())
        }
        listener.stateUpdateHandler = { state in
            if case .failed(let e) = state { FileHandle.standardError.write(Data("listener failed: \(e)\n".utf8)) }
        }
        listener.start(queue: .global())
    }

    private func receive(_ conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buf = buffer
            if let data { buf.append(data) }

            if let body = Self.completeBody(buf) {
                if let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
                   let character = json["character"] as? String {
                    self.onStatus(Status(character: character,
                                         message: json["message"] as? String ?? "",
                                         state: json["state"] as? String ?? "working"))
                }
                let payload = Data(#"{"ok":true}"#.utf8)
                let head = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(payload.count)\r\nConnection: close\r\n\r\n"
                conn.send(content: Data(head.utf8) + payload,
                          completion: .contentProcessed { _ in conn.cancel() })
                return
            }

            if error != nil || isComplete { conn.cancel(); return }
            self.receive(conn, buffer: buf)
        }
    }

    /// Returns the body once the full Content-Length has arrived, else nil.
    private static func completeBody(_ buf: Data) -> Data? {
        let sep = Data("\r\n\r\n".utf8)
        guard let r = buf.range(of: sep) else { return nil }
        let header = String(decoding: buf[..<r.lowerBound], as: UTF8.self)
        let length = header
            .split(separator: "\r\n")
            .first { $0.lowercased().hasPrefix("content-length:") }
            .flatMap { Int($0.split(separator: ":")[1].trimmingCharacters(in: .whitespaces)) } ?? 0
        let body = buf[r.upperBound...]
        return body.count >= length ? Data(body.prefix(length)) : nil
    }
}
