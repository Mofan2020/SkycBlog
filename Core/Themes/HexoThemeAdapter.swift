import Foundation

/// Hexo 主题适配器。
/// 检测到 active theme 是 .hexo 后, 接管构建流程, 用 EJSEngine 渲染全量页面。
public final class HexoThemeAdapter {
    public let projectRoot: String
    public let themeRoot: String
    public let config: SiteConfig
    public var warnings: [String] = []
    public var errors: [String] = []

    public init(projectRoot: String, themeRoot: String, config: SiteConfig) {
        self.projectRoot = projectRoot
        self.themeRoot = themeRoot
        self.config = config
    }

    public func build(pages: [Page], tags: [String: [Page]], categories: [String: [Page]], outDir: String, onProgress: ((String) -> Void)? = nil) -> BuildResult {
        var result = BuildResult()
        let engine = EJSEngine(themeRoot: themeRoot)
        // 注入通用 helpers, 让 url_for / full_url / trim 等 Hexo 风格函数可用
        engine.helpers["trim"] = { (args: [Any?]) -> Any in
            if let s = args.first as? String { return s.trimmingCharacters(in: .whitespacesAndNewlines) }
            return args.first ?? NSNull()
        }

        // 1. 复制 source/ 目录资源到 output/
        let sourceDir = (themeRoot as NSString).appendingPathComponent("source")
        copyDir(from: sourceDir, to: outDir)

        // 2. 构造 site 上下文
        let site = TemplateContextBuilder.build(config: config, pages: pages, tags: tags, categories: categories)
        // Hexo 风格别名: site.title 等已经在 site["site"] 中, 同时 site.title 也可用
        var siteContext: [String: Any] = site["site"] as? [String: Any] ?? [:]
        for (k, v) in site where k != "site" {
            siteContext[k] = v
        }
        // 保留 "site" 命名空间 (模板里 site.author / site.title 等可访问)
        siteContext["site"] = site["site"] as? [String: Any] ?? siteContext
        // Hexo 风格: `config` 是站点 + 主题合并的 config. 但因为 site-level config 在 site["site"], 让 `config` 直接等于 site
        siteContext["config"] = siteContext
        // 兼容: config.title / config.author
        siteContext["config"] = [
            "title": config.title,
            "subtitle": config.description,
            "description": config.description,
            "author": config.author,
            "language": config.language,
            "url": config.baseURL,
            "permalink": config.permalink ?? ":year/:month/:day/:slug/",
            "theme": config.themeName,
            "root": config.baseURL,
        ]
        // 让 url 全局可用
        siteContext["url"] = config.baseURL
        siteContext["root"] = config.baseURL
        siteContext["theme"] = config.themeConfig
        // Hexo 主题 _config.yml (来自 theme.root/_config.yml) 作为 theme.config
        if let hexoTheme = loadHexoThemeConfig() {
            siteContext["theme"] = hexoTheme
            siteContext["__theme_cfg__"] = hexoTheme
            // 主题 _config.yml 里 `helpers:` 字段作为 simple helpers 注入 (String/Number/Array)
            if let helpers = hexoTheme["helpers"] as? [String: Any] {
                for (k, v) in helpers {
                    siteContext[k] = v
                }
            }
        }
        // 分类字段名: categories (pl)
        siteContext["__hexo_eng__"] = true

        // 构造 site.tags / site.categories 数组 (Hexo 风格, 每个带 name/slug/count)
        let siteTagsList: [[String: Any]] = tags.map { (name, list) in
            return ["name": name, "slug": Permalink.slugify(name), "count": list.count, "path": "/tags/\(Permalink.slugify(name))/"]
        }.sorted { ($0["name"] as? String ?? "") < ($1["name"] as? String ?? "") }
        let siteCatsList: [[String: Any]] = categories.map { (name, list) in
            return ["name": name, "slug": Permalink.slugify(name), "count": list.count, "path": "/categories/\(Permalink.slugify(name))/"]
        }.sorted { ($0["name"] as? String ?? "") < ($1["name"] as? String ?? "") }
        var siteNS = (siteContext["site"] as? [String: Any]) ?? [:]
        siteNS["tags"] = siteTagsList
        siteNS["categories"] = siteCatsList
        siteContext["site"] = siteNS
        siteContext["tags"] = siteTagsList
        siteContext["categories"] = siteCatsList
        // 站点 posts 列表 (Hexo 风格: site.posts 是 [dict])
        siteContext["posts"] = pages.filter { $0.kind == .post }.map { hexoPost($0) }
        // i18n 字符串: 从 themeRoot/languages/<lang>.yml 读
        if let i18n = loadI18n() {
            siteContext["__i18n__"] = i18n
        }

        onProgress?("Hexo: 渲染首页")
        renderHome(engine: engine, site: siteContext, posts: pages.filter { $0.kind == .post }, outDir: outDir, result: &result)
        onProgress?("Hexo: 渲染文章页")
        for post in pages where post.kind == .post {
            renderPost(engine: engine, site: siteContext, post: post, outDir: outDir, result: &result)
        }
        onProgress?("Hexo: 渲染独立页")
        for page in pages where page.kind == .page {
            renderStandalonePage(engine: engine, site: siteContext, page: page, outDir: outDir, result: &result)
        }
        onProgress?("Hexo: 渲染归档")
        renderArchive(engine: engine, site: siteContext, posts: pages.filter { $0.kind == .post }, outDir: outDir, result: &result)
        onProgress?("Hexo: 渲染标签")
        for (tagName, list) in tags {
            renderTag(engine: engine, site: siteContext, tagName: tagName, list: list, outDir: outDir, result: &result)
        }
        onProgress?("Hexo: 渲染分类")
        for (catName, list) in categories {
            renderCategory(engine: engine, site: siteContext, catName: catName, list: list, outDir: outDir, result: &result)
        }
        onProgress?("Hexo: 渲染相册")
        for album in pages where album.kind == .album {
            renderAlbum(engine: engine, site: siteContext, album: album, outDir: outDir, result: &result)
        }
        onProgress?("Hexo: 渲染 404")
        render404(engine: engine, site: siteContext, outDir: outDir, result: &result)

        // 3. 整体资源拷贝 (Hexo 主题可能含 source/css, source/js, source/images, source/fancybox 等)
        copyDir(from: sourceDir, to: outDir)

        // 4. 把 _partial 也作为一种资源, 不再拷贝 (已被引擎吃掉)
        result.warnings.append(contentsOf: engine.warnings)
        result.warnings.append(contentsOf: warnings)
        result.errors.append(contentsOf: errors)
        return result
    }

    // MARK: - helpers

    private func loadHexoThemeConfig() -> [String: Any]? {
        let path = (themeRoot as NSString).appendingPathComponent("_config.yml")
        guard let text = FSUtil.readText(path) else { return nil }
        return MiniYAML.load(text)
    }

    /// 加载 i18n: themeRoot/languages/<lang>.yml
    /// 优先尝试 config.language, 然后 en, 然后 zh-CN
    private func loadI18n() -> [String: Any]? {
        let langs = [config.language, "en", "zh-CN", "zh-TW", "default"]
        for lang in langs {
            if lang.isEmpty { continue }
            let path = (themeRoot as NSString).appendingPathComponent("languages/\(lang).yml")
            if let text = FSUtil.readText(path) {
                let dict = MiniYAML.load(text)
                if !dict.isEmpty {
                    return dict
                }
            }
        }
        return nil
    }

    private func findLayout(_ candidates: [String]) -> String? {
        for c in candidates {
            let abs = (themeRoot as NSString).appendingPathComponent(c)
            if FSUtil.readText(abs) != nil { return c }
        }
        return nil
    }

    private func ensureDir(_ path: String) {
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    }

    // MARK: - 页面渲染

    private func renderHome(engine: EJSEngine, site: [String: Any], posts: [Page], outDir: String, result: inout BuildResult) {
        guard let layout = findLayout(["layout/index.ejs", "layout/index.html", "index.ejs"]) else {
            warnings.append("Hexo: 缺 layout/index.ejs, 跳过首页")
            return
        }
        let sorted = posts.sorted { $0.date > $1.date }
        let pages = max(1, Int(ceil(Double(sorted.count) / Double(config.paginationSize))))
        for p in 0..<pages {
            let start = p * config.paginationSize
            let end = min(start + config.paginationSize, sorted.count)
            let chunk = Array(sorted[start..<end])
            var ctx = site
            ctx["page"] = makeHexoPage(p: chunk.first, posts: chunk.map { hexoPost($0) }, pageNumber: p + 1, totalPages: pages, current: "/", type: "index")
            ctx["posts"] = chunk.map { hexoPost($0) }
            ctx["pagination"] = ["prev": p > 0 ? "page/\(p)" : nil, "next": p < pages - 1 ? "page/\(p + 2)" : nil, "page": p + 1, "total": pages]
            ctx["__type__"] = "index"
            let html = engine.renderFile(relPath: layout, context: ctx)
            let outPath = p == 0 ? "index.html" : "page/\(p + 1)/index.html"
            writeOut(html: html, outPath: outPath, outDir: outDir, result: &result, type: "首页")
        }
    }

    private func renderPost(engine: EJSEngine, site: [String: Any], post: Page, outDir: String, result: inout BuildResult) {
        let layout = findLayout(["layout/post.ejs", "layout/post.html", "post.ejs"]) ?? findLayout(["layout/index.ejs"]) ?? "layout/index.ejs"
        var ctx = site
        ctx["page"] = hexoPost(post)
        ctx["post"] = hexoPost(post)
        ctx["posts"] = [hexoPost(post)]
        ctx["__type__"] = "post"
        let html = engine.renderFile(relPath: layout, context: ctx)
        // 输出到 /<year>/<month>/<day>/<slug>/index.html
        let url = post.url
        var rel = url
        if rel.hasPrefix("/") { rel = String(rel.dropFirst()) }
        if !rel.hasSuffix(".html") {
            if rel.hasSuffix("/") { rel += "index.html" } else { rel += "/index.html" }
        }
        writeOut(html: html, outPath: rel, outDir: outDir, result: &result, type: "文章")
    }

    private func renderStandalonePage(engine: EJSEngine, site: [String: Any], page: Page, outDir: String, result: inout BuildResult) {
        let layout = findLayout(["layout/page.ejs", "layout/page.html", "page.ejs"]) ?? findLayout(["layout/post.ejs"]) ?? "layout/page.ejs"
        var ctx = site
        ctx["page"] = hexoPage(page)
        ctx["__type__"] = "page"
        let html = engine.renderFile(relPath: layout, context: ctx)
        var rel = page.url
        if rel.hasPrefix("/") { rel = String(rel.dropFirst()) }
        if !rel.hasSuffix(".html") {
            if rel.hasSuffix("/") { rel += "index.html" } else { rel += "/index.html" }
        }
        writeOut(html: html, outPath: rel, outDir: outDir, result: &result, type: "页面")
    }

    private func renderArchive(engine: EJSEngine, site: [String: Any], posts: [Page], outDir: String, result: inout BuildResult) {
        guard let layout = findLayout(["layout/archive.ejs", "layout/archives.ejs", "archive.ejs"]) else { return }
        let sorted = posts.sorted { $0.date > $1.date }
        var ctx = site
        ctx["page"] = makeHexoPage(posts: sorted.map { hexoPost($0) }, type: "archive")
        ctx["posts"] = sorted.map { hexoPost($0) }
        ctx["__type__"] = "archive"
        let html = engine.renderFile(relPath: layout, context: ctx)
        writeOut(html: html, outPath: "archives/index.html", outDir: outDir, result: &result, type: "归档")
    }

    private func renderTag(engine: EJSEngine, site: [String: Any], tagName: String, list: [Page], outDir: String, result: inout BuildResult) {
        guard let layout = findLayout(["layout/tag.ejs", "tag.ejs"]) else { return }
        let sorted = list.sorted { $0.date > $1.date }
        var ctx = site
        ctx["page"] = makeHexoPage(posts: sorted.map { hexoPost($0) }, type: "tag", tag: tagName)
        ctx["posts"] = sorted.map { hexoPost($0) }
        ctx["tag"] = ["name": tagName, "slug": Permalink.slugify(tagName)]
        ctx["__type__"] = "tag"
        let html = engine.renderFile(relPath: layout, context: ctx)
        let slug = Permalink.slugify(tagName)
        writeOut(html: html, outPath: "tags/\(slug)/index.html", outDir: outDir, result: &result, type: "标签")
    }

    private func renderCategory(engine: EJSEngine, site: [String: Any], catName: String, list: [Page], outDir: String, result: inout BuildResult) {
        guard let layout = findLayout(["layout/category.ejs", "category.ejs"]) else { return }
        let sorted = list.sorted { $0.date > $1.date }
        var ctx = site
        ctx["page"] = makeHexoPage(posts: sorted.map { hexoPost($0) }, type: "category", category: catName)
        ctx["posts"] = sorted.map { hexoPost($0) }
        let catSlug = Permalink.slugify(catName)
        ctx["category"] = ["name": catName, "slug": catSlug]
        ctx["__type__"] = "category"
        let html = engine.renderFile(relPath: layout, context: ctx)
        writeOut(html: html, outPath: "categories/\(catSlug)/index.html", outDir: outDir, result: &result, type: "分类")
    }

    private func renderAlbum(engine: EJSEngine, site: [String: Any], album: Page, outDir: String, result: inout BuildResult) {
        // 优先用 album.ejs, 回退 index.ejs
        let layout = findLayout(["layout/album.ejs", "album.ejs"]) ?? findLayout(["layout/index.ejs"]) ?? "layout/index.ejs"
        var ctx = site
        let albumDir = (album.sourcePath as NSString).deletingLastPathComponent
        let media = listAlbumMedia(albumDir: albumDir, albumSlug: album.slug)
        var albumDict = TemplateContextBuilder.pageDict(album)
        albumDict["slug"] = album.slug
        ctx["page"] = albumDict
        ctx["album"] = albumDict
        ctx["media"] = media
        let html = engine.renderFile(relPath: layout, context: ctx)
        writeOut(html: html, outPath: "albums/\(album.slug)/index.html", outDir: outDir, result: &result, type: "相册")
        // 拷贝媒体文件
        let dest = (outDir as NSString).appendingPathComponent("albums/\(album.slug)")
        ensureDir(dest)
        for m in media {
            if let src = m["__src__"] as? String {
                let fname = (src as NSString).lastPathComponent
                let dst = (dest as NSString).appendingPathComponent(fname)
                try? FileManager.default.removeItem(atPath: dst)
                try? FileManager.default.copyItem(atPath: src, toPath: dst)
            }
        }
    }

    private func render404(engine: EJSEngine, site: [String: Any], outDir: String, result: inout BuildResult) {
        let layout = findLayout(["layout/404.ejs", "404.ejs", "layout/index.ejs"])
        guard let layout = layout else { return }
        var ctx = site
        ctx["page"] = makeHexoPage(type: "404")
        let html = engine.renderFile(relPath: layout, context: ctx)
        writeOut(html: html, outPath: "404.html", outDir: outDir, result: &result, type: "404")
    }

    // MARK: - Hexo 风格的 page/post 对象

    private func hexoPost(_ p: Page) -> [String: Any] {
        var d = TemplateContextBuilder.pageDict(p)
        d["layout"] = "post"
        d["permalink"] = p.url
        d["path"] = p.url
        d["source"] = p.sourcePath
        d["content"] = p.contentHTML
        d["raw"] = p.contentRaw
        d["excerpt"] = p.excerpt ?? excerptFromContent(p.contentHTML)
        d["date"] = p.date
        d["updated"] = p.date
        d["title"] = d["title"] ?? p.title
        d["tags"] = d["tags"] ?? []
        d["categories"] = d["categories"] ?? []
        // Hexo 风格: permalink 始终以 / 开头
        if let pl = d["permalink"] as? String, !pl.hasPrefix("/"), !pl.hasPrefix("http") {
            d["permalink"] = "/" + pl
        }
        if let pth = d["path"] as? String, !pth.hasPrefix("/"), !pth.hasPrefix("http") {
            d["path"] = "/" + pth
        }
        return d
    }

    private func hexoPage(_ p: Page) -> [String: Any] {
        var d = TemplateContextBuilder.pageDict(p)
        d["layout"] = "page"
        d["permalink"] = p.url
        d["path"] = p.url
        d["source"] = p.sourcePath
        d["content"] = p.contentHTML
        d["raw"] = p.contentRaw
        d["excerpt"] = p.excerpt ?? excerptFromContent(p.contentHTML)
        d["date"] = p.date
        d["updated"] = p.date
        d["title"] = d["title"] ?? p.title
        d["tags"] = d["tags"] ?? []
        d["categories"] = d["categories"] ?? []
        if let pl = d["permalink"] as? String, !pl.hasPrefix("/"), !pl.hasPrefix("http") {
            d["permalink"] = "/" + pl
        }
        if let pth = d["path"] as? String, !pth.hasPrefix("/"), !pth.hasPrefix("http") {
            d["path"] = "/" + pth
        }
        return d
    }

    private func makeHexoPage(p: Page? = nil, posts: [[String: Any]] = [], pageNumber: Int = 1, totalPages: Int = 1, current: String = "/", type: String = "index", tag: String? = nil, category: String? = nil) -> [String: Any] {
        var d: [String: Any] = [
            "posts": posts as Any,
            "page": pageNumber as Any,
            "total": totalPages as Any,
            "per_page": config.paginationSize as Any,
            "current": current as Any,
            "path": current as Any,
            "type": type as Any,
        ]
        if let p = p { d["__inner_page__"] = hexoPost(p) }
        if let tag = tag { d["tag"] = tag }
        if let category = category { d["category"] = category }
        return d
    }

    private func excerptFromContent(_ html: String) -> String {
        // 简单去标签取前 150 字符
        let stripped = html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        if stripped.count <= 150 { return stripped }
        return String(stripped.prefix(150)) + "…"
    }

    // MARK: - IO

    private func writeOut(html: String, outPath: String, outDir: String, result: inout BuildResult, type: String) {
        if html.isEmpty { warnings.append("\(type) 模板渲染为空: \(outPath)"); return }
        let final = config.minifyHTML ? html : html
        let abs = (outDir as NSString).appendingPathComponent(outPath)
        ensureDir((abs as NSString).deletingLastPathComponent)
        FSUtil.writeText(final, to: abs)
        result.generated.append(outPath)
    }

    private func listAlbumMedia(albumDir: String, albumSlug: String) -> [[String: Any]] {
        let fm = FileManager.default
        var out: [[String: Any]] = []
        guard let files = try? fm.contentsOfDirectory(atPath: albumDir) else { return out }
        for f in files.sorted() where f != "index.md" {
            let src = (albumDir as NSString).appendingPathComponent(f)
            let ext = (f as NSString).pathExtension.lowercased()
            let isImage = ["jpg","jpeg","png","gif","webp","heic","heif"].contains(ext)
            let isVideo = ["mp4","mov","m4v","webm"].contains(ext)
            out.append([
                "filename": f,
                "url": "/albums/\(albumSlug)/\(f)",
                "type": isImage ? "image" : (isVideo ? "video" : "other"),
                "__src__": src
            ] as [String: Any])
        }
        return out
    }

    private func copyDir(from src: String, to dst: String) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: src) else { return }
        try? fm.createDirectory(atPath: dst, withIntermediateDirectories: true)
        let items = (try? fm.contentsOfDirectory(atPath: src)) ?? []
        for item in items {
            let s = (src as NSString).appendingPathComponent(item)
            let d = (dst as NSString).appendingPathComponent(item)
            var isDir: ObjCBool = false
            fm.fileExists(atPath: s, isDirectory: &isDir)
            if isDir.boolValue {
                copyDir(from: s, to: d)
            } else {
                if fm.fileExists(atPath: d) { try? fm.removeItem(atPath: d) }
                try? fm.copyItem(atPath: s, toPath: d)
            }
        }
    }
}
