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
        let decoded = path.removingPercentEncoding ?? path
        // 不允许路径穿越
        if decoded.contains("..") {
            return httpResponse(status: "403 Forbidden", contentType: "text/plain; charset=utf-8", body: "Forbidden: Path contains '..'")
        }
        // 解析相对路径：默认空/末尾 / 视作目录,走 index.html
        var relPath = decoded
        if relPath.hasPrefix("/") { relPath = String(relPath.dropFirst()) }
        if relPath.isEmpty || relPath.hasSuffix("/") { relPath += "index.html" }
        let filePath = (rootDir as NSString).appendingPathComponent(relPath)
        // 标准化后再次校验,防止跳出 rootDir
        let rootURL = URL(fileURLWithPath: rootDir, isDirectory: true).standardizedFileURL.path
        let fileURL = URL(fileURLWithPath: filePath).standardizedFileURL.path
        if !fileURL.hasPrefix(rootURL) {
            return httpResponse(status: "403 Forbidden", contentType: "text/plain; charset=utf-8", body: "Forbidden: Path escapes root")
        }

        // 判断目录
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: filePath, isDirectory: &isDirectory)
        if exists && isDirectory.boolValue {
            let idx = (filePath as NSString).appendingPathComponent("index.html")
            if FileManager.default.fileExists(atPath: idx) {
                let body = (try? String(contentsOfFile: idx, encoding: .utf8)) ?? ""
                let ext = (idx as NSString).pathExtension.lowercased()
                return httpResponse(status: "200 OK", contentType: contentType(for: ext), body: body)
            } else {
                return listDirectory(at: filePath, requestPath: decoded)
            }
        }

        if exists {
            let body = (try? String(contentsOfFile: filePath, encoding: .utf8)) ?? ""
            let ext = (filePath as NSString).pathExtension.lowercased()
            let ct = contentType(for: ext)
            return httpResponse(status: "200 OK", contentType: ct, body: body)
        }

        // 友好 404
        return notFoundResponse(requestedPath: decoded)
    }

    /// 友好 404:优先用站点自身的 404.html,否则给一段说明 HTML。
    func notFoundResponse(requestedPath: String) -> String {
        let customPath = (rootDir as NSString).appendingPathComponent("404.html")
        if FileManager.default.fileExists(atPath: customPath) {
            if let text = try? String(contentsOfFile: customPath, encoding: .utf8) {
                return httpResponse(status: "404 Not Found", contentType: "text/html; charset=utf-8", body: text)
            }
        }
        let html = """
        <!DOCTYPE html>
        <html lang="zh-CN">
        <head>
          <meta charset="UTF-8"/>
          <title>404 · 未找到</title>
          <style>
            :root { color-scheme: light dark; }
            body { font-family: "PingFang SC", -apple-system, sans-serif;
                   background: #f7f2eb; color: #1f1f21;
                   display: flex; min-height: 100vh; margin: 0;
                   align-items: center; justify-content: center; }
            @media (prefers-color-scheme: dark) {
              body { background: #1a1a1c; color: #ececef; }
              code, .hint { background: rgba(255,255,255,0.06); color: #cfcfd2; }
            }
            .card { max-width: 520px; padding: 40px 44px; border-radius: 14px;
                    background: rgba(255,255,255,0.6); }
            @media (prefers-color-scheme: dark) { .card { background: rgba(255,255,255,0.05); } }
            h1 { font-size: 56px; margin: 0 0 8px; color: #bf5233; }
            h2 { font-size: 18px; font-weight: 500; margin: 0 0 24px; opacity: 0.7; }
            code, .hint { background: rgba(0,0,0,0.06); padding: 2px 6px; border-radius: 4px;
                          font-family: "SF Mono", monospace; font-size: 13px; }
            .hint { display: block; padding: 10px 14px; margin: 8px 0; }
            ul { padding-left: 20px; line-height: 1.8; }
            a { color: #bf5233; }
          </style>
        </head>
        <body>
          <div class="card">
            <h1>404</h1>
            <h2>请求的页面不存在</h2>
            <p>请求路径：<code>\(escapeHTML(requestedPath))</code></p>
            <p>可能原因：</p>
            <ul>
              <li>还没有构建 —— 请先在 SkycBlog App 中点击「构建」</li>
              <li>构建后未刷新 —— 重新构建一次</li>
              <li>输出目录为空 —— 检查 <code>\(escapeHTML(rootDir))</code></li>
            </ul>
            <p class="hint">提示：构建完成后站点首页应为 <code>/index.html</code>。</p>
            <p><a href="/">返回首页</a></p>
          </div>
        </body>
        </html>
        """
        return httpResponse(status: "404 Not Found", contentType: "text/html; charset=utf-8", body: html)
    }

    /// 简单目录列表(开发用)。
    func listDirectory(at dir: String, requestPath: String) -> String {
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: dir).sorted()) ?? []
        let rows = entries.map { e -> String in
            let p = (dir as NSString).appendingPathComponent(e)
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: p, isDirectory: &isDir)
            let icon = isDir.boolValue ? "📁" : "📄"
            return "<li>\(icon) <a href=\"\(e)\">\(escapeHTML(e))</a></li>"
        }.joined()
        let html = """
        <!DOCTYPE html><html><head><meta charset="UTF-8"/><title>\(escapeHTML(requestPath))</title>
        <style>body{font-family:"PingFang SC",sans-serif;max-width:760px;margin:40px auto;padding:0 20px;color:#1f1f21;background:#f7f2eb}
        @media(prefers-color-scheme:dark){body{background:#1a1a1c;color:#ececef}}
        h1{font-weight:500;font-size:18px;opacity:0.7}ul{list-style:none;padding:0}
        li{padding:6px 0}a{color:#bf5233;text-decoration:none}a:hover{text-decoration:underline}</style>
        </head><body><h1>\(escapeHTML(requestPath))</h1><ul>\(rows)</ul></body></html>
        """
        return httpResponse(status: "200 OK", contentType: "text/html; charset=utf-8", body: html)
    }

    /// 简单 HTML 转义,避免 404 页面里被注入。
    func escapeHTML(_ s: String) -> String {
        return s.replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
                .replacingOccurrences(of: "\"", with: "&quot;")
                .replacingOccurrences(of: "'", with: "&#39;")
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
