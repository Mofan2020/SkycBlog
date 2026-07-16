import Foundation

/// 文章/页面管理：重命名、移动 front matter 字段、批量改标签/分类。
public enum PostManager {
    public struct FrontMatter {
        public var title: String
        public var date: String
        public var tags: [String]
        public var categories: [String]
        public var draft: Bool
        public var layout: String
        public var cover: String?
        public var other: [(String, String)]   // 其它键原样保留
    }

    public enum ParseError: Error, LocalizedError {
        case noFrontMatter
        case unterminated
        public var errorDescription: String? {
            switch self {
            case .noFrontMatter: return "缺少 front matter（需以 --- 开头）"
            case .unterminated: return "front matter 未闭合"
            }
        }
    }

    /// 读取 front matter 解析为结构,失败抛错。
    public static func parse(_ text: String) throws -> (FrontMatter, String) {
        guard text.hasPrefix("---") else { throw ParseError.noFrontMatter }
        let lines = text.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { throw ParseError.noFrontMatter }
        var endIndex = -1
        for i in 1..<lines.count {
            if lines[i].trimmingCharacters(in: .whitespaces) == "---" {
                endIndex = i
                break
            }
        }
        if endIndex < 0 { throw ParseError.unterminated }
        let fmLines = Array(lines[1..<endIndex])
        let body = lines[(endIndex+1)...].joined(separator: "\n")
        let dict = MiniYAML.load(fmLines.joined(separator: "\n"))
        var fm = FrontMatter(
            title: (dict["title"] as? String) ?? "",
            date: (dict["date"] as? String) ?? "",
            tags: (dict["tags"] as? [String]) ?? [],
            categories: (dict["categories"] as? [String]) ?? [],
            draft: (dict["draft"] as? Bool) ?? false,
            layout: (dict["layout"] as? String) ?? "post",
            cover: dict["cover"] as? String,
            other: []
        )
        // 收集 known 之外的其他键（按文本顺序）
        let known: Set<String> = ["title","date","tags","categories","draft","layout","cover"]
        for line in fmLines {
            if let colon = line.firstIndex(of: ":") {
                let key = line[..<colon].trimmingCharacters(in: .whitespaces)
                if !known.contains(key) && !key.isEmpty {
                    let val = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                    fm.other.append((key, val))
                }
            }
        }
        return (fm, body)
    }

    /// 渲染回 YAML 文本。
    public static func render(_ fm: FrontMatter, body: String) -> String {
        var lines: [String] = ["---"]
        lines.append("title: \(escapeYAML(fm.title))")
        if !fm.date.isEmpty { lines.append("date: \(fm.date)") }
        if !fm.tags.isEmpty {
            lines.append("tags: [\(fm.tags.map(escapeYAMLInline).joined(separator: ", "))]")
        } else {
            lines.append("tags: []")
        }
        if !fm.categories.isEmpty {
            lines.append("categories: [\(fm.categories.map(escapeYAMLInline).joined(separator: ", "))]")
        } else {
            lines.append("categories: []")
        }
        if fm.draft { lines.append("draft: true") }
        if !fm.layout.isEmpty { lines.append("layout: \(fm.layout)") }
        if let cover = fm.cover, !cover.isEmpty { lines.append("cover: \(escapeYAML(cover))") }
        for (k, v) in fm.other {
            lines.append("\(k): \(v)")
        }
        lines.append("---")
        return lines.joined(separator: "\n") + "\n" + body
    }

    static func escapeYAML(_ s: String) -> String {
        if s.contains(":") || s.contains("#") || s.hasPrefix("\"") {
            return "\"\(s.replacingOccurrences(of: "\"", with: "\\\""))\""
        }
        return s
    }
    static func escapeYAMLInline(_ s: String) -> String {
        if s.contains(",") || s.contains("\"") || s.contains("[") {
            return "\"\(s.replacingOccurrences(of: "\"", with: "\\\""))\""
        }
        return s
    }

    // MARK: - 公开操作

    public static func renameFile(at sourcePath: String, newTitle: String) throws -> String {
        let dir = (sourcePath as NSString).deletingLastPathComponent
        let newName = (try? String(contentsOfFile: sourcePath, encoding: .utf8)).map { _ in "" } ?? ""
        _ = newName
        let titleSlug = slugify(newTitle)
        let prefix = ((sourcePath as NSString).lastPathComponent as NSString).deletingPathExtension
        // 文件名格式 YYYY-MM-DD-<old-slug>.md,保留日期前缀
        let parts = prefix.components(separatedBy: "-")
        let datePrefix: String
        if parts.count >= 4, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2 {
            datePrefix = "\(parts[0])-\(parts[1])-\(parts[2])-"
        } else {
            datePrefix = ""
        }
        let newFilename = "\(datePrefix)\(titleSlug).md"
        let newPath = (dir as NSString).appendingPathComponent(newFilename)
        if newPath == sourcePath { return sourcePath }
        if FileManager.default.fileExists(atPath: newPath) {
            throw NSError(domain: "PostManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "已存在同名文件：\(newFilename)"])
        }
        try FileManager.default.moveItem(atPath: sourcePath, toPath: newPath)
        // 同步修改文件中的 title
        if let text = try? String(contentsOfFile: newPath, encoding: .utf8) {
            let (fm, body) = try parse(text)
            var newFM = fm
            newFM.title = newTitle
            try render(newFM, body: body).write(toFile: newPath, atomically: true, encoding: .utf8)
        }
        return newPath
    }

    public static func updateMetadata(at sourcePath: String,
                                      title: String? = nil,
                                      tags: [String]? = nil,
                                      categories: [String]? = nil,
                                      draft: Bool? = nil,
                                      layout: String? = nil) throws {
        let text = try String(contentsOfFile: sourcePath, encoding: .utf8)
        let (fm, body) = try parse(text)
        var newFM = fm
        if let title = title { newFM.title = title }
        if let tags = tags { newFM.tags = tags }
        if let cats = categories { newFM.categories = cats }
        if let draft = draft { newFM.draft = draft }
        if let layout = layout { newFM.layout = layout }
        let rendered = render(newFM, body: body)
        try rendered.write(toFile: sourcePath, atomically: true, encoding: .utf8)
    }

    public static func slugify(_ s: String) -> String {
        var out = ""
        for ch in s.lowercased() {
            if ch.isLetter || ch.isNumber || ch == "-" || ch == "_" {
                out.append(ch)
            } else if ch == " " {
                out.append("-")
            }
        }
        return out.isEmpty ? "untitled" : out
    }

    /// 创建一个新文章（与 ProjectScaffold 行为一致，但允许指定额外元数据）。
    public static func createPost(projectRoot: String, title: String, tags: [String] = [], categories: [String] = []) throws -> String {
        return try ProjectScaffold.createPost(projectRoot: projectRoot, title: title, tags: tags, categories: categories)
    }
}
