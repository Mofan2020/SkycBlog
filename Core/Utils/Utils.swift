import Foundation

/// 通用工具方法：路径处理、字符串、文件 IO、日志。
public enum FSUtil {
    /// 确保目录存在（递归创建）。
    @discardableResult
    public static func ensureDirectory(_ path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return true
        } catch {
            FileHandle.standardError.write(Data("[error] cannot create directory \(path): \(error)\n".utf8))
            return false
        }
    }

    /// 递归复制一个目录。
    public static func copyDirectory(from src: String, to dst: String) throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: dst) {
            try fm.createDirectory(atPath: dst, withIntermediateDirectories: true)
        }
        let items = try fm.contentsOfDirectory(atPath: src)
        for item in items {
            let s = (src as NSString).appendingPathComponent(item)
            let d = (dst as NSString).appendingPathComponent(item)
            var isDir: ObjCBool = false
            fm.fileExists(atPath: s, isDirectory: &isDir)
            if isDir.boolValue {
                try copyDirectory(from: s, to: d)
            } else {
                if fm.fileExists(atPath: d) { try fm.removeItem(atPath: d) }
                try fm.copyItem(atPath: s, toPath: d)
            }
        }
    }

    /// 递归清空一个目录（保留目录本身）。
    public static func cleanDirectory(_ path: String) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else { return }
        let items = try fm.contentsOfDirectory(atPath: path)
        for item in items {
            let p = (path as NSString).appendingPathComponent(item)
            try fm.removeItem(atPath: p)
        }
    }

    /// 递归删除一个目录。
    public static func remove(_ path: String) {
        let fm = FileManager.default
        if fm.fileExists(atPath: path) {
            try? fm.removeItem(atPath: path)
        }
    }

    /// 规范化路径分隔符。
    public static func normalize(_ path: String) -> String {
        let expanded = (path as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expanded).standardizedFileURL.path
    }

    /// 路径是否是一个 Markdown 文件。
    public static func isMarkdown(_ path: String) -> Bool {
        let ext = (path as NSString).pathExtension.lowercased()
        return ext == "md" || ext == "markdown"
    }

    /// 读取文件文本，失败返回 nil。
    public static func readText(_ path: String) -> String? {
        return try? String(contentsOfFile: path, encoding: .utf8)
    }

    /// 写入文件。
    @discardableResult
    public static func writeText(_ text: String, to path: String) -> Bool {
        do {
            let dir = (path as NSString).deletingLastPathComponent
            ensureDirectory(dir)
            try text.write(toFile: path, atomically: true, encoding: .utf8)
            return true
        } catch {
            FileHandle.standardError.write(Data("[error] cannot write \(path): \(error)\n".utf8))
            return false
        }
    }

    /// 写二进制。
    @discardableResult
    public static func writeBytes(_ data: Data, to path: String) -> Bool {
        do {
            let dir = (path as NSString).deletingLastPathComponent
            ensureDirectory(dir)
            try data.write(to: URL(fileURLWithPath: path))
            return true
        } catch {
            FileHandle.standardError.write(Data("[error] cannot write \(path): \(error)\n".utf8))
            return false
        }
    }
}

/// 简单日志记录。
public final class Log {
    public enum Level: String { case info, warn, error, success, debug }

    public static var quiet = false
    public static var jsonMode = false

    public static func emit(_ level: Level, _ message: String) {
        if quiet && level == .info { return }
        if jsonMode {
            if let data = try? JSONSerialization.data(withJSONObject: ["level": level.rawValue, "message": message], options: []) {
                FileHandle.standardOutput.write(data)
                FileHandle.standardOutput.write(Data("\n".utf8))
            }
        } else {
            let prefix: String
            switch level {
            case .info:    prefix = "ℹ️ "
            case .warn:    prefix = "⚠️ "
            case .error:   prefix = "❌ "
            case .success: prefix = "✅ "
            case .debug:   prefix = "🔍 "
            }
            print("\(prefix) \(message)")
        }
    }

    public static func info(_ s: String)    { emit(.info, s) }
    public static func warn(_ s: String)    { emit(.warn, s) }
    public static func error(_ s: String)   { emit(.error, s) }
    public static func success(_ s: String) { emit(.success, s) }
    public static func debug(_ s: String)   { emit(.debug, s) }
}

/// Front Matter 解析结果。
public struct FrontMatter {
    public var raw: String = ""
    public var dict: [String: Any] = [:]

    public func string(_ key: String) -> String? { dict[key] as? String }
    public func bool(_ key: String, default def: Bool = false) -> Bool {
        if let v = dict[key] as? Bool { return v }
        if let v = dict[key] as? String { return v.lowercased() == "true" }
        return def
    }
    public func date(_ key: String = "date") -> Date? {
        if let d = dict[key] as? Date { return d }
        if let s = dict[key] as? String {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = f.date(from: s) { return d }
            let f2 = ISO8601DateFormatter()
            if let d = f2.date(from: s) { return d }
            // Hexo 风格: "yyyy-MM-dd HH:mm:ss" 视为站点本地时区
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd HH:mm:ss"
            df.timeZone = TimeZone.current
            if let d = df.date(from: s) { return d }
            df.dateFormat = "yyyy-MM-dd HH:mm"
            if let d = df.date(from: s) { return d }
            df.dateFormat = "yyyy-MM-dd"
            if let d = df.date(from: s) { return d }
        }
        return nil
    }
    public func stringArray(_ key: String) -> [String] {
        if let a = dict[key] as? [String] { return a }
        if let a = dict[key] as? [Any] { return a.compactMap { $0 as? String } }
        return []
    }
    public func any(_ key: String) -> Any? { dict[key] }
}

/// Front Matter 解析器，支持 YAML、TOML、JSON。
public enum FrontMatterParser {
    /// 把文本分割为 front matter 与正文。
    public static func split(_ text: String) -> (FrontMatter, String) {
        var fm = FrontMatter()
        let lines = text.components(separatedBy: "\n")
        guard let first = lines.first, first.trimmingCharacters(in: .whitespaces) == "---" else {
            return (fm, text)
        }
        // YAML 风格：--- ... ---
        if lines.count > 2 {
            // 查找第二个 ---
            for i in 1..<lines.count {
                if lines[i].trimmingCharacters(in: .whitespaces) == "---" {
                    let yamlText = lines[1..<i].joined(separator: "\n")
                    fm.raw = yamlText
                    fm.dict = MiniYAML.load(yamlText)
                    let body = lines[(i + 1)...].joined(separator: "\n")
                    return (fm, body)
                }
            }
        }
        return (fm, text)
    }
}

/// 日期工具。
public enum DateUtil {
    public static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    public static let yyyyMMdd: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f
    }()
    public static let human: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()
}

/// 字符串 HTML 转义。
public extension String {
    var htmlEscaped: String {
        var s = self
        s = s.replacingOccurrences(of: "&", with: "&amp;")
        s = s.replacingOccurrences(of: "<", with: "&lt;")
        s = s.replacingOccurrences(of: ">", with: "&gt;")
        s = s.replacingOccurrences(of: "\"", with: "&quot;")
        s = s.replacingOccurrences(of: "'", with: "&#39;")
        return s
    }
    var htmlAttrEscaped: String { return htmlEscaped }
}
