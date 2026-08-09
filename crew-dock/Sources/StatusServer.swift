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
        /// What the agent is *doing* rather than who it is (sorting, booking,
        /// research, analysis…). Added by A so motion can be keyed to the work
        /// instead of to a name — two agents doing research then move alike and
        /// the dock never has to learn the roster. Optional: older senders and
        /// hand-written `curl` calls omit it.
        let activity: String
    }

    private let listener: NWListener
    private let onStatus: (Status) -> Void

    init?(port: UInt16, onStatus: @escaping (Status) -> Void) {
        // SO_REUSEADDR. Without it the bind fails for ~15s after the previous
        // dock exits: the listener is long gone, but the POST connections it
        // accepted sit in TIME_WAIT and hold the port. Restarting the dock
        // straight after a run — exactly what you do between rehearsals — hit
        // "Address already in use" while nothing was actually listening.
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        guard let p = NWEndpoint.Port(rawValue: port),
              let l = try? NWListener(using: params, on: p) else { return nil }
        listener = l
        self.onStatus = onStatus
    }

    func start() {
        listener.newConnectionHandler = { [weak self] conn in
            conn.start(queue: .global())
            self?.receive(conn, buffer: Data())
        }
        // Binding is asynchronous, so "listening" can only honestly be printed
        // from .ready. It used to be printed by main.swift the moment start()
        // returned, and a failed bind only added a second line below it — so a
        // dock that had received nothing all run still opened its log with
        // "crew dock listening on :4002". That is the log lying about the one
        // thing it exists to prove.
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                FileHandle.standardError.write(Data("crew dock listening on :4002\n".utf8))
            case .failed(let e):
                // Almost always another dock still holding the port. Staying up
                // is worse than dying: an app on screen that can never receive a
                // line looks exactly like a working one until the show starts.
                FileHandle.standardError.write(Data(
                    "listener failed: \(e)\nis another Crew.app running? ./run-demo.sh stop\n".utf8))
                exit(1)
            default: break
            }
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
                                         state: json["state"] as? String ?? "working",
                                         activity: json["activity"] as? String ?? ""))
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
