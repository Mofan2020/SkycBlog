import Foundation
import Network

/// 简单的 HTTP 本地服务器（基于 Network.framework），用于 `blog serve`。
public final class LocalServer {
    public let port: UInt16
    public let rootDir: String
    private var listener: NWListener?
    private var connections: [NWConnection] = []
    public var onStatus: ((String) -> Void)?

    public init(port: UInt16 = 8080, rootDir: String) {
        self.port = port
        self.rootDir = rootDir
    }

    public func start() throws {
        let nwPort = NWEndpoint.Port(rawValue: port)!
        let params = NWParameters.tcp
        let listener = try NWListener(using: params, on: nwPort)
        listener.newConnectionHandler = { [weak self] conn in
            self?.handle(conn: conn)
        }
        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready: self?.onStatus?("已启动: http://localhost:\(self?.port ?? 8080)")
            case .failed(let e): self?.onStatus?("错误: \(e)")
            default: break
            }
        }
        listener.start(queue: .global())
        self.listener = listener
        onStatus?("监听端口 \(port)")
    }

    public func stop() {
        listener?.cancel()
        for c in connections { c.cancel() }
        connections.removeAll()
    }

    private func handle(conn: NWConnection) {
        connections.append(conn)
        conn.start(queue: .global())
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            if let data = data, let request = String(data: data, encoding: .utf8) {
                let response = self.handleRequest(request)
                conn.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
                    conn.cancel()
                    self.connections.removeAll { $0 === conn }
                })
            }
            if isComplete || error != nil {
                conn.cancel()
                self.connections.removeAll { $0 === conn }
            }
        }
    }

    func handleRequest(_ request: String) -> String {
        let firstLine = request.split(separator: "\n").first.map(String.init) ?? ""
        let parts = firstLine.split(separator: " ").map(String.init)
        guard parts.count >= 2 else {
            return httpResponse(status: "400 Bad Request", contentType: "text/plain; charset=utf-8", body: "Bad Request")
        }
        var path = parts[1]
        if let q = path.firstIndex(of: "?") { path = String(path[..<q]) }
        if path.hasSuffix("/") { path += "index.html" }
        let decoded = path.removingPercentEncoding ?? path
        let filePath: String
        if decoded.hasPrefix("/") {
            filePath = (rootDir as NSString).appendingPathComponent(String(decoded.dropFirst()))
        } else {
            filePath = (rootDir as NSString).appendingPathComponent(decoded)
        }
        if FileManager.default.fileExists(atPath: filePath) {
            let body = (try? String(contentsOfFile: filePath, encoding: .utf8)) ?? ""
            let ext = (filePath as NSString).pathExtension.lowercased()
            let ct = contentType(for: ext)
            return httpResponse(status: "200 OK", contentType: ct, body: body)
        }
        // 尝试 404.html
        let notFound = (rootDir as NSString).appendingPathComponent("404.html")
        let body = (FileManager.default.fileExists(atPath: notFound) ? (try? String(contentsOfFile: notFound, encoding: .utf8)) : "404 Not Found") ?? "404 Not Found"
        return httpResponse(status: "404 Not Found", contentType: "text/html; charset=utf-8", body: body)
    }

    func httpResponse(status: String, contentType: String, body: String) -> String {
        let bytes = body.utf8.count
        return """
        HTTP/1.1 \(status)\r
        Content-Type: \(contentType)\r
        Content-Length: \(bytes)\r
        Connection: close\r
        \r
        \(body)
        """
    }

    func contentType(for ext: String) -> String {
        switch ext {
        case "html", "htm": return "text/html; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "js": return "application/javascript; charset=utf-8"
        case "json": return "application/json; charset=utf-8"
        case "xml": return "application/xml; charset=utf-8"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "svg": return "image/svg+xml"
        case "mp4": return "video/mp4"
        case "mov": return "video/quicktime"
        case "webm": return "video/webm"
        case "ico": return "image/x-icon"
        case "md": return "text/markdown; charset=utf-8"
        default: return "application/octet-stream"
        }
    }
}
