import Foundation

/// 一篇内容（文章/页面/相册）的统一数据模型。
public struct Page: CustomStringConvertible, Identifiable, Hashable {
    public enum Kind: String { case post, page, draft, album }

    public var id: String                  // 唯一 slug
    public var kind: Kind
    public var sourcePath: String          // 源文件绝对路径
    public var relSourcePath: String       // 相对 projectRoot
    public var title: String
    public var date: Date
    public var tags: [String] = []
    public var categories: [String] = []
    public var draft: Bool = false
    public var layout: String = "post"
    public var slug: String = ""
    public var cover: String? = nil
    public var excerpt: String? = nil
    public var url: String = ""            // 站点内绝对 URL（含 baseURL）
    public var outPath: String = ""        // 站点内相对输出路径
    public var contentHTML: String = ""    // 已渲染的 HTML
    public var contentRaw: String = ""     // 原始 Markdown
    public var extra: [String: Any] = [:]  // 其他 front matter

    public var description: String { "\(kind.rawValue)[\(id)]" }

    public static func == (lhs: Page, rhs: Page) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// 内容收集与解析。
public final class ContentLoader {
    public let projectRoot: String
    public let config: SiteConfig
    public private(set) var pages: [Page] = []
    public var allPages: [Page] { pages }
    public func replacePages(_ new: [Page]) { self.pages = new }
    public private(set) var allTags: [String: [Page]] = [:]
    public private(set) var allCategories: [String: [Page]] = [:]

    public init(projectRoot: String, config: SiteConfig) {
        self.projectRoot = projectRoot
        self.config = config
    }

    public func load(includeDrafts: Bool) throws {
        pages.removeAll()
        allTags.removeAll()
        allCategories.removeAll()

        let fm = FileManager.default
        let root = projectRoot as NSString

        // 1. 加载文章
        try loadPosts(in: root.appendingPathComponent("content/_posts"), kind: .post, fm: fm)
        if includeDrafts || config.buildDrafts {
            try loadPosts(in: root.appendingPathComponent("content/_drafts"), kind: .draft, fm: fm)
        }
        // 2. 加载独立页面
        try loadPages(in: root.appendingPathComponent("content/pages"), kind: .page, fm: fm)
        // 3. 加载相册
        try loadAlbums(in: root.appendingPathComponent("content/albums"), fm: fm)

        // 4. 分类聚合
        for p in pages {
            for t in p.tags {
                allTags[t, default: []].append(p)
            }
            for c in p.categories {
                allCategories[c, default: []].append(p)
            }
        }
    }

    private func loadPosts(in dir: String, kind: Page.Kind, fm: FileManager) throws {
        guard fm.fileExists(atPath: dir) else { return }
        let files = try fm.contentsOfDirectory(atPath: dir).filter { FSUtil.isMarkdown($0) }.sorted()
        for f in files {
            let path = (dir as NSString).appendingPathComponent(f)
            let relPath = ((path as NSString).replacingOccurrences(of: projectRoot + "/", with: ""))
            let page = try parseFile(path: path, relPath: relPath, kind: kind, fm: fm)
            if page.draft && !config.buildDrafts && kind != .draft { continue }
            pages.append(page)
        }
        // 按日期倒序
        if kind == .post {
            pages.sort { $0.date > $1.date }
        }
    }

    private func loadPages(in dir: String, kind: Page.Kind, fm: FileManager) throws {
        guard fm.fileExists(atPath: dir) else { return }
        let files = try fm.contentsOfDirectory(atPath: dir).filter { FSUtil.isMarkdown($0) }.sorted()
        for f in files {
            let path = (dir as NSString).appendingPathComponent(f)
            let relPath = ((path as NSString).replacingOccurrences(of: projectRoot + "/", with: ""))
            let page = try parseFile(path: path, relPath: relPath, kind: kind, fm: fm)
            pages.append(page)
        }
    }

    private func loadAlbums(in dir: String, fm: FileManager) throws {
        guard fm.fileExists(atPath: dir) else { return }
        let albums = try fm.contentsOfDirectory(atPath: dir)
        for name in albums {
            let albumDir = (dir as NSString).appendingPathComponent(name)
            var isDir: ObjCBool = false
            fm.fileExists(atPath: albumDir, isDirectory: &isDir)
            if !isDir.boolValue { continue }
            let indexPath = (albumDir as NSString).appendingPathComponent("index.md")
            if fm.fileExists(atPath: indexPath) {
                let relPath = ((indexPath as NSString).replacingOccurrences(of: projectRoot + "/", with: ""))
                var page = try parseFile(path: indexPath, relPath: relPath, kind: .album, fm: fm)
                page.id = name
                page.slug = name
                page.layout = "album"
                page.title = page.title.isEmpty ? name : page.title
                // 收集媒体
                let media = (try? fm.contentsOfDirectory(atPath: albumDir)) ?? []
                page.extra["media"] = media.filter { !$0.hasSuffix(".md") }.sorted()
                pages.append(page)
            }
        }
    }

    private func parseFile(path: String, relPath: String, kind: Page.Kind, fm: FileManager) throws -> Page {
        let text = try String(contentsOfFile: path, encoding: .utf8)
        let (fmData, body) = FrontMatterParser.split(text)
        let rawID = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        // 去掉文件名开头的日期前缀（YYYY-MM-DD-），让 page.id = 真正的 slug
        let idSlug: String
        if kind == .post {
            let parts = rawID.components(separatedBy: "-")
            if parts.count >= 4, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2 {
                idSlug = parts[3...].joined(separator: "-")
            } else {
                idSlug = rawID
            }
        } else {
            idSlug = rawID
        }
        var p = Page(
            id: idSlug,
            kind: kind,
            sourcePath: path,
            relSourcePath: relPath,
            title: fmData.string("title") ?? ((path as NSString).lastPathComponent as NSString).deletingPathExtension,
            date: fmData.date() ?? Date(),
            tags: fmData.stringArray("tags"),
            categories: fmData.stringArray("categories"),
            draft: fmData.bool("draft"),
            layout: fmData.string("layout") ?? "post",
            slug: fmData.string("slug") ?? idSlug,
            cover: fmData.string("cover"),
            excerpt: fmData.string("excerpt"),
            contentRaw: body
        )
        p.extra = fmData.dict
        // 渲染 Markdown
        p.contentHTML = MarkdownRenderer.render(body)
        // 摘要
        if p.excerpt == nil || p.excerpt!.isEmpty {
            p.excerpt = MarkdownRenderer.excerpt(from: body, length: 150)
        }
        // 计算 URL：page 类型（独立页面）使用 /:slug/ 模式，post 使用配置的 permalink 模式
        let urlPath: String
        if p.kind == .page {
            let slug = p.slug.isEmpty ? p.id : p.slug
            urlPath = "/\(slug)/"
        } else {
            urlPath = Permalink.resolve(config: config, page: p)
        }
        p.url = (config.baseURL.hasSuffix("/") ? String(config.baseURL.dropLast()) : config.baseURL) + urlPath
        let trimmedURL = urlPath.hasPrefix("/") ? String(urlPath.dropFirst()) : urlPath
        p.outPath = trimmedURL.isEmpty ? "index.html" : trimmedURL
        if !p.outPath.hasSuffix(".html") {
            p.outPath = (p.outPath as NSString).appendingPathComponent("index.html")
        }
        return p
    }

    public func posts() -> [Page] { pages.filter { $0.kind == .post } }
    public func draftPages() -> [Page] { pages.filter { $0.kind == .draft } }
    public func standalonePages() -> [Page] { pages.filter { $0.kind == .page } }
    public func albums() -> [Page] { pages.filter { $0.kind == .album } }
}

/// 永久链接模式解析。
public enum Permalink {
    public static func resolve(config: SiteConfig, page: Page) -> String {
        var pattern = config.permalink
        let comps = Calendar.current.dateComponents([.year, .month, .day], from: page.date)
        let year = comps.year ?? 1970
        let month = String(format: "%02d", comps.month ?? 1)
        let day = String(format: "%02d", comps.day ?? 1)
        let slug = page.slug.isEmpty ? page.id : page.slug
        let category = page.categories.first ?? "uncategorized"

        pattern = pattern.replacingOccurrences(of: ":year", with: "\(year)")
        pattern = pattern.replacingOccurrences(of: ":month", with: month)
        pattern = pattern.replacingOccurrences(of: ":day", with: day)
        pattern = pattern.replacingOccurrences(of: ":slug", with: slug)
        pattern = pattern.replacingOccurrences(of: ":category", with: category)
        if !pattern.hasSuffix("/") { pattern += "/" }
        return pattern
    }

    public static func resolveTag(tag: String) -> String { "/tags/\(slugify(tag))/" }
    public static func resolveCategory(category: String) -> String { "/categories/\(category.lowercased().replacingOccurrences(of: " ", with: "-"))/" }
    public static func slugify(_ s: String) -> String {
        return s.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "/", with: "-")
    }
}
