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
                    config = merged
                }
                break
            }
        }

        // CLI 覆盖
        for (k, v) in cliOverrides {
            applyOverride(&config, key: k, value: v)
        }

        // 路径标准化
        config.outputDir = FSUtil.normalize(
            (config.outputDir as NSString).expandingTildeInPath
        )
        if !config.outputDir.hasPrefix("/") {
            config.outputDir = (config.projectRoot as NSString).appendingPathComponent(config.outputDir)
        }

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
        if let v = dict["permalink"] as? String { c.permalink = v }
        if let v = dict["minifyHTML"] as? Bool { c.minifyHTML = v }
        if let v = dict["fingerprintAssets"] as? Bool { c.fingerprintAssets = v }
        if let v = dict["generateSearchIndex"] as? Bool { c.generateSearchIndex = v }
        if let v = dict["generateRSS"] as? Bool { c.generateRSS = v }
        if let v = dict["generateSitemap"] as? Bool { c.generateSitemap = v }
        if let v = dict["themeConfig"] as? [String: Any] { c.themeConfig = v }
        if let v = dict["deploy"] as? [String: Any] { c.deploy = v }
        if let v = dict["extra"] as? [String: Any] { c.extra = v }
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
