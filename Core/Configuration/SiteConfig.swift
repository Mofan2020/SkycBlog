import Foundation

/// SkycBlog 主配置。
public struct SiteConfig {
    public var title: String = "SkycBlog"
    public var description: String = ""
    public var author: String = ""
    public var language: String = "zh-CN"
    public var baseURL: String = "/"
    public var outputDir: String = "output"
    public var buildDrafts: Bool = false
    public var paginationSize: Int = 10
    public var themeName: String = "default"
    public var permalink: String = "/:year/:month/:day/:slug/"
    public var minifyHTML: Bool = true
    public var fingerprintAssets: Bool = false
    public var generateSearchIndex: Bool = true
    public var generateRSS: Bool = true
    public var generateSitemap: Bool = true
    public var disabledPlugins: [String] = []
    public var themeConfig: [String: Any] = [:]
    public var deploy: [String: Any] = [:]
    public var extra: [String: Any] = [:]
    public var projectRoot: String = "."

    /// 默认值。
    public static let defaults: SiteConfig = SiteConfig()

    public init() {}

    /// 任何字典字段查找。
    public func lookup(_ dotted: String) -> Any? {
        let parts = dotted.split(separator: ".").map(String.init)
        var cur: Any? = mirrorDict()
        for p in parts {
            if let d = cur as? [String: Any], let v = d[p] {
                cur = v
            } else {
                return nil
            }
        }
        return cur
    }

    private func mirrorDict() -> [String: Any] {
        var d: [String: Any] = [
            "title": title,
            "description": description,
            "author": author,
            "language": language,
            "baseURL": baseURL,
            "outputDir": outputDir,
            "buildDrafts": buildDrafts,
            "paginationSize": paginationSize,
            "themeName": themeName,
            "permalink": permalink,
            "minifyHTML": minifyHTML,
            "fingerprintAssets": fingerprintAssets,
            "generateSearchIndex": generateSearchIndex,
            "generateRSS": generateRSS,
            "generateSitemap": generateSitemap,
            "themeConfig": themeConfig,
            "deploy": deploy,
            "extra": extra,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: d),
           let mirror = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return mirror
        }
        return d
    }
}

/// 配置加载器（YAML / JSON / TOML）+ CLI 覆盖。
public final class ConfigLoader {
    /// 从 projectRoot 加载配置（按优先级：CLI 覆盖 > config.yaml > config.yml > config.json > config.toml）。
    public static func load(projectRoot: String, cliOverrides: [String: String] = [:]) throws -> SiteConfig {
        var config = SiteConfig.defaults
        config.projectRoot = FSUtil.normalize(projectRoot)

        let candidates = ["config.yaml", "config.yml", "config.json", "config.toml"]
        for name in candidates {
            let path = (config.projectRoot as NSString).appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: path) {
                if let merged = try loadFile(path: path) {
                    // loadFile 内部 merge 默认从 SiteConfig.defaults 出发, 该默认值 projectRoot="."
                    // 必须把调用方传进来的 projectRoot 重新设回, 否则后续路径处理全错。
                    var m = merged
                    m.projectRoot = config.projectRoot
                    config = m
                }
                break
            }
        }

        // CLI 覆盖
        for (k, v) in cliOverrides {
            applyOverride(&config, key: k, value: v)
        }

        // 路径标准化: 强制把 outputDir 落到项目根下, 避免:
        //   1) 写成了 /output 这类系统目录(写不进去或写到别处)
        //   2) 写成了 /Users/.../别的项目, 导致一个博客的构建产物出现在另一个博客里
        // 规则: 若已经是项目根的子路径 → 取相对; 否则强制为 <projectRoot>/<basename>
        let rawOut = (config.outputDir as NSString).expandingTildeInPath
        let normalized = FSUtil.normalize(rawOut)
        let rootWithSep = config.projectRoot.hasSuffix("/") ? config.projectRoot : config.projectRoot + "/"
        let finalOut: String
        if !normalized.hasPrefix("/") {
            // 相对路径 → 拼到 projectRoot
            finalOut = (config.projectRoot as NSString).appendingPathComponent(normalized)
        } else if normalized == config.projectRoot {
            finalOut = config.projectRoot
        } else if normalized.hasPrefix(rootWithSep) {
            // 已经是项目根内的子路径 → 接受
            finalOut = normalized
        } else {
            // 系统级或项目外的绝对路径 → 强制重定向到项目根下
            let baseName = (normalized as NSString).lastPathComponent
            finalOut = (config.projectRoot as NSString).appendingPathComponent(baseName.isEmpty ? "output" : baseName)
        }
        config.outputDir = finalOut

        return config
    }

    private static func loadFile(path: String) throws -> SiteConfig? {
        guard let text = FSUtil.readText(path) else { return nil }
        let ext = (path as NSString).pathExtension.lowercased()
        var dict: [String: Any] = [:]
        switch ext {
        case "yaml", "yml":
            dict = MiniYAML.load(text)
        case "json":
            if let data = text.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                dict = obj
            }
        case "toml":
            dict = TOMLParser.parse(text)
        default:
            return nil
        }
        return merge(dict: dict, into: SiteConfig.defaults)
    }

    private static func merge(dict: [String: Any], into base: SiteConfig) -> SiteConfig {
        var c = base
        if let v = dict["title"] as? String { c.title = v }
        if let v = dict["description"] as? String { c.description = v }
        if let v = dict["author"] as? String { c.author = v }
        if let v = dict["language"] as? String { c.language = v }
        if let v = dict["baseURL"] as? String { c.baseURL = v }
        if let v = dict["outputDir"] as? String { c.outputDir = v }
        if let v = dict["buildDrafts"] as? Bool { c.buildDrafts = v }
        if let v = dict["paginationSize"] as? Int { c.paginationSize = v }
        if let v = dict["themeName"] as? String { c.themeName = v }
        if let v = dict["theme"] as? String { c.themeName = v }
        if let v = dict["permalink"] as? String { c.permalink = v }
        if let v = dict["minifyHTML"] as? Bool { c.minifyHTML = v }
        if let v = dict["fingerprintAssets"] as? Bool { c.fingerprintAssets = v }
        if let v = dict["generateSearchIndex"] as? Bool { c.generateSearchIndex = v }
        if let v = dict["generateRSS"] as? Bool { c.generateRSS = v }
        if let v = dict["generateSitemap"] as? Bool { c.generateSitemap = v }
        if let v = dict["themeConfig"] as? [String: Any] { c.themeConfig = v }
        if let v = dict["deploy"] as? [String: Any] { c.deploy = v }
        if let v = dict["extra"] as? [String: Any] { c.extra = v }
        if let v = dict["disabledPlugins"] as? [String] { c.disabledPlugins = v }
        return c
    }

    private static func applyOverride(_ c: inout SiteConfig, key: String, value: String) {
        switch key {
        case "title": c.title = value
        case "description": c.description = value
        case "author": c.author = value
        case "language": c.language = value
        case "baseURL", "baseUrl": c.baseURL = value
        case "output", "outputDir": c.outputDir = value
        case "buildDrafts": c.buildDrafts = (value == "true" || value == "1")
        case "paginationSize": c.paginationSize = Int(value) ?? c.paginationSize
        case "theme", "themeName": c.themeName = value
        case "permalink": c.permalink = value
        case "drafts": c.buildDrafts = (value == "true" || value == "1")
        default: c.extra[key] = value
        }
    }
}

/// TOML 简化解析器（仅支持项目配置所需的子集）。
public enum TOMLParser {
    public static func parse(_ text: String) -> [String: Any] {
        var result: [String: Any] = [:]
        var currentTable: [String: Any] = [:]
        var currentPath: [String] = []
        let lines = text.components(separatedBy: "\n")

        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            if line.hasPrefix("[") && line.hasSuffix("]") {
                let section = String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                currentPath = section.split(separator: ".").map { $0.trimmingCharacters(in: .whitespaces) }
                if currentPath.count == 1 {
                    if result[currentPath[0]] == nil { result[currentPath[0]] = [String: Any]() }
                    currentTable = (result[currentPath[0]] as? [String: Any]) ?? [:]
                } else {
                    // 嵌套表
                    var nested: [String: Any] = result
                    for (idx, p) in currentPath.enumerated() {
                        if idx == currentPath.count - 1 {
                            if nested[p] == nil { nested[p] = [String: Any]() }
                            if var dict = nested[p] as? [String: Any] {
                                nested[p] = dict
                            }
                        } else {
                            if nested[p] == nil { nested[p] = [String: Any]() }
                            nested = (nested[p] as? [String: Any]) ?? [:]
                        }
                    }
                    result = nested
                    currentTable = (result[currentPath.last!] as? [String: Any]) ?? [:]
                }
                continue
            }
            // key = value
            if let eq = line.firstIndex(of: "=") {
                let k = line[..<eq].trimmingCharacters(in: .whitespaces)
                var v = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
                if let c = v.first, c == "\"" || c == "'" {
                    v = String(v.dropFirst().dropLast())
                }
                let parsed: Any = inferValue(String(v))
                if currentPath.isEmpty {
                    result[k] = parsed
                } else if currentPath.count == 1 {
                    currentTable[k] = parsed
                    result[currentPath[0]] = currentTable
                } else {
                    var nested: [String: Any] = result
                    for (idx, p) in currentPath.enumerated() {
                        if idx == currentPath.count - 1 {
                            if var d = nested[p] as? [String: Any] {
                                d[k] = parsed
                                nested[p] = d
                            }
                        } else {
                            if nested[p] == nil { nested[p] = [String: Any]() }
                            nested = (nested[p] as? [String: Any]) ?? [:]
                        }
                    }
                    result = nested
                }
            }
        }
        return result
    }

    private static func inferValue(_ s: String) -> Any {
        if s == "true" { return true }
        if s == "false" { return false }
        if let i = Int(s) { return i }
        if let d = Double(s) { return d }
        // 数组
        if s.hasPrefix("[") && s.hasSuffix("]") {
            let inner = String(s.dropFirst().dropLast())
            let parts = splitTopLevel(inner)
            return parts.map { inferValue($0.trimmingCharacters(in: .whitespaces)) }
        }
        return s
    }

    private static func splitTopLevel(_ s: String) -> [String] {
        var parts: [String] = []
        var depth = 0
        var current = ""
        for ch in s {
            if ch == "[" { depth += 1 }
            if ch == "]" { depth -= 1 }
            if ch == "," && depth == 0 {
                parts.append(current)
                current = ""
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty { parts.append(current) }
        return parts
    }
}

/// 极简 TOML 序列化器 (用于把 dict 写回 theme.toml).
/// 仅支持项目配置所需的子集: 字符串/整数/浮点/布尔/数组/[String:Any] 嵌套.
public enum MiniTOML {
    public static func dump(_ root: [String: Any]) -> String {
        var lines: [String] = []
        // 顶层用 [section] 标头 (如果 root 中只有非嵌套标量, 也可省略; 但 Hugo theme.toml 一律用 section 风格)
        // 简单起见: 把所有顶层 key 放一个 [theme] section, 顶层是 dict 的再用 [parent.child] 嵌套
        for (k, v) in root.sorted(by: { $0.key < $1.key }) {
            emitKeyValue(key: k, value: v, sectionPath: [], lines: &lines)
        }
        return lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
    }

    private static func emitKeyValue(key: String, value: Any, sectionPath: [String], lines: inout [String]) {
        if let sub = value as? [String: Any] {
            // 新 section (避免重复)
            let newPath = sectionPath + [key]
            if lines.count > 0 { lines.append("") } // section 之间空行
            lines.append("[\(newPath.joined(separator: "."))]")
            for (k, v) in sub.sorted(by: { $0.key < $1.key }) {
                emitKeyValue(key: k, value: v, sectionPath: newPath, lines: &lines)
            }
        } else if let arr = value as? [Any] {
            lines.append("\(key) = \(tomlArrayLiteral(arr))")
        } else {
            lines.append("\(key) = \(tomlScalar(value))")
        }
    }

    private static func tomlScalar(_ v: Any) -> String {
        if v is NSNull { return "\"\"" }
        if let b = v as? Bool { return b ? "true" : "false" }
        if let i = v as? Int { return String(i) }
        if let d = v as? Double { return String(d) }
        if let s = v as? String { return tomlStringLiteral(s) }
        return tomlStringLiteral(String(describing: v))
    }

    private static func tomlStringLiteral(_ s: String) -> String {
        // 用单引号包裹; 内部的反斜杠和单引号转义
        let escaped = s.replacingOccurrences(of: "\\", with: "\\\\")
                        .replacingOccurrences(of: "'", with: "\\'")
                        .replacingOccurrences(of: "\n", with: "\\n")
        return "'\(escaped)'"
    }

    private static func tomlArrayLiteral(_ arr: [Any]) -> String {
        let inner = arr.map { v -> String in
            if v is [String: Any] {
                // inline table 不易表达, 跳过复杂对象
                return "\"{...}\""
            }
            return tomlScalar(v)
        }.joined(separator: ", ")
        return "[\(inner)]"
    }
}
