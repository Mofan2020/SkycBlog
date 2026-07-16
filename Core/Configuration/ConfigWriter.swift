import Foundation

/// 把 `SiteConfig` 序列化为 yaml/json 文件,覆盖到 `config.yaml`。
public enum ConfigWriter {
    public static func write(_ config: SiteConfig, to projectRoot: String, as format: String = "yaml") throws {
        let path = (projectRoot as NSString).appendingPathComponent("config.\(format)")
        let text: String
        switch format {
        case "json": text = renderJSON(config)
        default: text = renderYAML(config)
        }
        try text.write(toFile: path, atomically: true, encoding: .utf8)
    }

    public static func renderYAML(_ c: SiteConfig) -> String {
        var lines: [String] = []
        lines.append("title: \(esc(c.title))")
        lines.append("description: \(esc(c.description))")
        lines.append("author: \(esc(c.author))")
        lines.append("language: \(c.language)")
        lines.append("baseURL: \(c.baseURL)")
        // outputDir 写回相对路径
        let relOut = relativize(c.outputDir, against: c.projectRoot)
        lines.append("outputDir: \(relOut)")
        lines.append("buildDrafts: \(c.buildDrafts)")
        lines.append("paginationSize: \(c.paginationSize)")
        lines.append("theme: \(c.themeName)")
        lines.append("permalink: \(c.permalink)")
        lines.append("minifyHTML: \(c.minifyHTML)")
        lines.append("fingerprintAssets: \(c.fingerprintAssets)")
        lines.append("generateSearchIndex: \(c.generateSearchIndex)")
        lines.append("generateRSS: \(c.generateRSS)")
        lines.append("generateSitemap: \(c.generateSitemap)")
        if !c.disabledPlugins.isEmpty {
            lines.append("disabledPlugins: [\(c.disabledPlugins.map { esc($0) }.joined(separator: ", "))]")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    public static func renderJSON(_ c: SiteConfig) -> String {
        let dict: [String: Any] = [
            "title": c.title,
            "description": c.description,
            "author": c.author,
            "language": c.language,
            "baseURL": c.baseURL,
            "outputDir": relativize(c.outputDir, against: c.projectRoot),
            "buildDrafts": c.buildDrafts,
            "paginationSize": c.paginationSize,
            "theme": c.themeName,
            "permalink": c.permalink,
            "minifyHTML": c.minifyHTML,
            "fingerprintAssets": c.fingerprintAssets,
            "generateSearchIndex": c.generateSearchIndex,
            "generateRSS": c.generateRSS,
            "generateSitemap": c.generateSitemap,
            "disabledPlugins": c.disabledPlugins,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    static func esc(_ s: String) -> String {
        if s.contains(":") || s.contains("#") || s.hasPrefix("\"") || s.contains("\n") {
            return "\"\(s.replacingOccurrences(of: "\"", with: "\\\""))\""
        }
        return s
    }

    static func relativize(_ abs: String, against root: String) -> String {
        let absNorm = (abs as NSString).expandingTildeInPath
        let rootNorm = (root as NSString).expandingTildeInPath
        // 1) 完全相等 → "."
        if absNorm == rootNorm { return "." }
        // 2) 是 root 的子路径 → 取相对
        let prefix = rootNorm.hasSuffix("/") ? rootNorm : rootNorm + "/"
        if absNorm.hasPrefix(prefix) {
            return String(absNorm.dropFirst(prefix.count))
        }
        // 3) 已经写的是相对路径（不以 / 开头）
        if !absNorm.hasPrefix("/") {
            return absNorm
        }
        // 4) 项目外的绝对路径（如 /output、/var/...、/Users/.../别的项目）→
        //    强制取 basename 作为相对路径，默认 "output" 避免写错位置
        let baseName = (absNorm as NSString).lastPathComponent
        return baseName.isEmpty ? "output" : baseName
    }
}
