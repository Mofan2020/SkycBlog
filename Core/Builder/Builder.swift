import Foundation

/// 构建器：协调 内容 → 模板 → 输出。
public final class Builder {
    public let config: SiteConfig
    public let projectRoot: String
    public let themeRoot: String
    public var includeDrafts: Bool
    public var onProgress: ((String) -> Void)?

    public init(config: SiteConfig, includeDrafts: Bool = false) {
        self.config = config
        self.projectRoot = config.projectRoot
        self.themeRoot = ThemeManager.themeRoot(projectRoot: projectRoot, themeName: config.themeName)
        self.includeDrafts = includeDrafts
    }

    public func build() -> BuildResult {
        var result = BuildResult()
        let start = Date()
        Log.info("开始构建：\(projectRoot)")

        // 1. 准备输出
        try? FileManager.default.createDirectory(atPath: config.outputDir, withIntermediateDirectories: true)
        do { try FSUtil.cleanDirectory(config.outputDir) } catch { Log.warn("清空输出失败：\(error)") }
        FSUtil.ensureDirectory(config.outputDir)

        // 2. 加载主题资源
        ThemeManager.copyDefaultIfMissing(projectRoot: projectRoot, themeName: config.themeName)
        // static/ 目录拷贝到 outputDir 下对应的子目录,保留 /static/ 路径,这样模板里的 /static/css/main.css 链接能找到文件
        copyStaticFolder(from: (themeRoot as NSString).appendingPathComponent("static"), to: (config.outputDir as NSString).appendingPathComponent("static"))
        copyStaticFolder(from: (projectRoot as NSString).appendingPathComponent("static"), to: (config.outputDir as NSString).appendingPathComponent("static"))

        // 3. 加载内容
        let content = ContentLoader(projectRoot: projectRoot, config: config)
        do { try content.load(includeDrafts: includeDrafts) } catch {
            result.errors.append("内容加载失败：\(error)")
            return result
        }
        result.pages = content.pages

        // 4. 加载插件
        let plugins = PluginManager(projectRoot: projectRoot, disabledFilenames: Set(config.disabledPlugins))
        plugins.loadAll()
        plugins.site = TemplateContextBuilder.build(config: config, pages: content.pages, tags: content.allTags, categories: content.allCategories)
        plugins.fire("beforeBuild")

        // 5. 重新构建 site 上下文（插件可能修改 pages）
        var site = plugins.site
        // 仅当插件真的修改了 pages（即 site["pages"] 数量与 content.pages 不同）时,才采用插件版本
        let originalPostCount = content.pages.filter { $0.kind == .post }.count
        if let pagesArray = site["pages"] as? [Any],
           pagesArray.count != originalPostCount {
            // 把 pages 转换为内部模型
            var newPages: [Page] = []
            for p in pagesArray {
                if let d = p as? [String: Any] {
                    if let p2 = dictToPage(d) { newPages.append(p2) }
                }
            }
            if !newPages.isEmpty {
                content.replacePages(newPages)
            }
        }
        // 重新构建（基于可能被插件修改的 pages）
        site = TemplateContextBuilder.build(config: config, pages: content.pages, tags: content.allTags, categories: content.allCategories)
        // 合并主题默认配置（theme.yaml）
        mergeThemeDefaults(into: &site, themeRoot: themeRoot)
        plugins.site = site
        plugins.fire("afterReadFiles")

        // 6. 渲染
        let engine = TemplateEngine(themeRoot: themeRoot)

        for p in content.pages {
            var ctx = TemplateContextBuilder.pageDict(p)
            ctx["site"] = site["site"] as Any
            ctx["theme"] = site["theme"] as Any
            ctx["standalonePages"] = site["standalonePages"] as Any
            plugins.fire("beforeRender", args: [TemplateContextBuilder.pageDict(p)])
            // 同步插件修改
            if let newSite = plugins.contextJSValue as? [String: Any],
               let override = newSite[p.slug] as? [String: Any] {
                for (k, v) in override { ctx[k] = v }
            }
            // 选用 layout 模板
            let template = pickLayout(engine: engine, name: p.layout)
            let html = engine.render(template: template, context: ctx)
            let path = (config.outputDir as NSString).appendingPathComponent(p.outPath)
            FSUtil.ensureDirectory((path as NSString).deletingLastPathComponent)
            var outHTML: String
            if html.lowercased().contains("<!doctype") {
                outHTML = html
            } else {
                // 模板没有 doctype 时，由 head.html partial 自行提供 <head><body>，但需要外层 doctype+html+lang 包裹
                outHTML = "<!DOCTYPE html>\n<html lang=\"\(config.language)\">\n" + html
            }
            if config.minifyHTML { outHTML = HTMLMinifier.minify(outHTML) }
            let absPath = (config.outputDir as NSString).appendingPathComponent(p.outPath)
            FSUtil.writeText(outHTML, to: absPath)
            plugins.fire("afterRender", args: [p.outPath, outHTML])
            result.generated.append(p.outPath)
        }

        // 7. 索引页（首页）
        renderIndex(engine: engine, site: site, outDir: config.outputDir, posts: content.posts(), paginationSize: config.paginationSize, result: &result)
        // 8. 归档页
        renderArchives(engine: engine, site: site, outDir: config.outputDir, posts: content.posts(), result: &result)
        // 9. 标签聚合
        renderTagPages(engine: engine, site: site, outDir: config.outputDir, posts: content.posts(), tags: content.allTags, result: &result)
        // 10. 分类聚合
        renderCategoryPages(engine: engine, site: site, outDir: config.outputDir, categories: content.allCategories, result: &result)
        // 11. 相册
        renderAlbums(engine: engine, site: site, outDir: config.outputDir, albums: content.albums(), projectRoot: projectRoot, result: &result)
        // 12. RSS / sitemap / search.json / 404
        if config.generateRSS {
            let rss = RSSBuilder.build(config: config, posts: content.posts())
            FSUtil.writeText(rss, to: (config.outputDir as NSString).appendingPathComponent("rss.xml"))
            result.generated.append("rss.xml")
        }
        if config.generateSitemap {
            let sm = SitemapBuilder.build(config: config, pages: content.pages)
            FSUtil.writeText(sm, to: (config.outputDir as NSString).appendingPathComponent("sitemap.xml"))
            result.generated.append("sitemap.xml")
        }
        if config.generateSearchIndex {
            let idx = SearchIndexBuilder.build(pages: content.posts())
            if let data = try? JSONSerialization.data(withJSONObject: idx, options: [.prettyPrinted, .sortedKeys]),
               let str = String(data: data, encoding: .utf8) {
                FSUtil.writeText(str, to: (config.outputDir as NSString).appendingPathComponent("search.json"))
                result.generated.append("search.json")
            }
        }
        // 404.html
        if let tpl = FSUtil.readText((themeRoot as NSString).appendingPathComponent("templates/404.html")) {
            let html = engine.render(template: tpl, context: site)
            let wrap = "<!DOCTYPE html>\n<html lang=\"\(config.language)\">\n<head><meta charset=\"UTF-8\"/><title>404</title></head>\n<body>\n\(html)\n</body></html>"
            FSUtil.writeText(wrap, to: (config.outputDir as NSString).appendingPathComponent("404.html"))
            result.generated.append("404.html")
        }

        plugins.fire("afterBuild")

        let elapsed = Date().timeIntervalSince(start)
        result.elapsed = elapsed
        result.warnings = engine.warnings
        Log.success("构建完成，用时 \(String(format: "%.2f", elapsed)) 秒，生成 \(result.generated.count) 个文件")
        return result
    }

    // MARK: - 索引页（带分页）

    func renderIndex(engine: TemplateEngine, site: [String: Any], outDir: String, posts: [Page], paginationSize: Int, result: inout BuildResult) {
        let template = readTemplate(engine: engine, name: "index")
        let sorted = posts.sorted { $0.date > $1.date }
        let pages: Int = max(1, Int(ceil(Double(sorted.count) / Double(paginationSize))))
        for p in 0..<pages {
            let start = p * paginationSize
            let end = min(start + paginationSize, sorted.count)
            let chunk = Array(sorted[start..<end])
            var ctx = site
            ctx["posts"] = chunk.map { TemplateContextBuilder.pageDict($0) }
            ctx["pageIndex"] = p + 1
            ctx["pageCount"] = pages
            ctx["hasPrev"] = p > 0
            ctx["hasNext"] = p < pages - 1
            let html = engine.render(template: template, context: ctx)
            let outPath: String
            if p == 0 {
                outPath = "index.html"
            } else {
                outPath = "page/\(p + 1)/index.html"
            }
            let abs = (outDir as NSString).appendingPathComponent(outPath)
            FSUtil.ensureDirectory((abs as NSString).deletingLastPathComponent)
            let finalHTML = html.lowercased().contains("<!doctype") ? html : wrapHTML(html, config: config)
            FSUtil.writeText(finalHTML, to: abs)
            result.generated.append(outPath)
        }
    }

    // MARK: - 归档

    func renderArchives(engine: TemplateEngine, site: [String: Any], outDir: String, posts: [Page], result: inout BuildResult) {
        let template = readTemplate(engine: engine, name: "archives")
        var ctx = site
        ctx["archives"] = TemplateContextBuilder.groupByYear(posts: posts)
        let html = engine.render(template: template, context: ctx)
        let abs = (outDir as NSString).appendingPathComponent("archives/index.html")
        FSUtil.ensureDirectory((abs as NSString).deletingLastPathComponent)
        FSUtil.writeText(wrapHTML(html, config: config), to: abs)
        result.generated.append("archives/index.html")
    }

    // MARK: - 标签聚合

    func renderTagPages(engine: TemplateEngine, site: [String: Any], outDir: String, posts: [Page], tags: [String: [Page]], result: inout BuildResult) {
        let template = readTemplate(engine: engine, name: "tag")
        // 标签总览
        var ctx = site
        ctx["tags"] = tags.keys.sorted().map { k -> [String: Any] in
            ["name": k, "slug": Permalink.slugify(k), "count": (tags[k]?.count ?? 0), "url": Permalink.resolveTag(tag: k)]
        }
        let html = engine.render(template: template, context: ctx)
        let abs = (outDir as NSString).appendingPathComponent("tags/index.html")
        FSUtil.ensureDirectory((abs as NSString).deletingLastPathComponent)
        FSUtil.writeText(wrapHTML(html, config: config), to: abs)
        result.generated.append("tags/index.html")
        // 单个标签页
        let single = readTemplate(engine: engine, name: "tag")
        for (name, list) in tags {
            var c = site
            c["tag"] = ["name": name, "slug": Permalink.slugify(name), "url": Permalink.resolveTag(tag: name)]
            c["posts"] = list.sorted { $0.date > $1.date }.map { TemplateContextBuilder.pageDict($0) }
            let h = engine.render(template: single, context: c)
            let p = (outDir as NSString).appendingPathComponent("tags/\(Permalink.slugify(name))/index.html")
            FSUtil.ensureDirectory((p as NSString).deletingLastPathComponent)
            FSUtil.writeText(wrapHTML(h, config: config), to: p)
            result.generated.append("tags/\(Permalink.slugify(name))/index.html")
        }
    }

    // MARK: - 分类聚合

    func renderCategoryPages(engine: TemplateEngine, site: [String: Any], outDir: String, categories: [String: [Page]], result: inout BuildResult) {
        let template = readTemplate(engine: engine, name: "category")
        for (name, list) in categories {
            var c = site
            c["category"] = ["name": name, "url": Permalink.resolveCategory(category: name)]
            c["posts"] = list.sorted { $0.date > $1.date }.map { TemplateContextBuilder.pageDict($0) }
            let h = engine.render(template: template, context: c)
            let p = (outDir as NSString).appendingPathComponent("categories/\(name.lowercased().replacingOccurrences(of: " ", with: "-"))/index.html")
            FSUtil.ensureDirectory((p as NSString).deletingLastPathComponent)
            FSUtil.writeText(wrapHTML(h, config: config), to: p)
            result.generated.append("categories/\(name)/index.html")
        }
    }

    // MARK: - 相册

    func renderAlbums(engine: TemplateEngine, site: [String: Any], outDir: String, albums: [Page], projectRoot: String, result: inout BuildResult) {
        let template = readTemplate(engine: engine, name: "album")
        // 相册总览
        var ctx = site
        ctx["albums"] = albums.map { a -> [String: Any] in
            var d = TemplateContextBuilder.pageDict(a)
            d["slug"] = a.slug
            d["url"] = a.url
            return d
        }
        let html = engine.render(template: template, context: ctx)
        let abs = (outDir as NSString).appendingPathComponent("albums/index.html")
        FSUtil.ensureDirectory((abs as NSString).deletingLastPathComponent)
        FSUtil.writeText(wrapHTML(html, config: config), to: abs)
        result.generated.append("albums/index.html")
        // 单个相册
        for album in albums {
            let albumSrc = (album.sourcePath as NSString).deletingLastPathComponent
            let mediaDest = (outDir as NSString).appendingPathComponent("albums/\(album.slug)/")
            FSUtil.ensureDirectory(mediaDest)
            let fm = FileManager.default
            if let files = try? fm.contentsOfDirectory(atPath: albumSrc) {
                for f in files where f != "index.md" {
                    let src = (albumSrc as NSString).appendingPathComponent(f)
                    let dst = (mediaDest as NSString).appendingPathComponent(f)
                    if fm.fileExists(atPath: dst) { try? fm.removeItem(atPath: dst) }
                    try? fm.copyItem(atPath: src, toPath: dst)
                }
            }
            // 收集媒体信息（EXIF）
            var media: [[String: Any]] = []
            for f in (try? fm.contentsOfDirectory(atPath: albumSrc).sorted()) ?? [] where f != "index.md" {
                let src = (albumSrc as NSString).appendingPathComponent(f)
                let isImage = ["jpg","jpeg","png","gif","webp","heic","heif"].contains((src as NSString).pathExtension.lowercased())
                let isVideo = ["mp4","mov","m4v","webm"].contains((src as NSString).pathExtension.lowercased())
                var m: [String: Any] = [
                    "filename": f,
                    "url": "/albums/\(album.slug)/\(f)",
                    "type": isImage ? "image" : (isVideo ? "video" : "other"),
                ]
                if isImage {
                    let exif = EXIFReader.read(at: src)
                    m["exifSummary"] = EXIFReader.summarize(exif)
                    m["exifJSON"] = serializeEXIF(exif)
                    if let dt = exif.dateTimeOriginal { m["dateTime"] = ISO8601DateFormatter().string(from: dt) }
                    if let w = exif.pixelX, let h = exif.pixelY { m["size"] = "\(w) × \(h)" }
                    if let lat = exif.latitude, let lon = exif.longitude {
                        m["gps"] = "\(lat), \(lon)"
                    }
                }
                media.append(m)
            }
            var c = site
            var albumDict = TemplateContextBuilder.pageDict(album)
            albumDict["slug"] = album.slug
            c["album"] = albumDict
            c["media"] = media
            let h = engine.render(template: template, context: c)
            let p = (outDir as NSString).appendingPathComponent("albums/\(album.slug)/index.html")
            FSUtil.writeText(wrapHTML(h, config: config), to: p)
            result.generated.append("albums/\(album.slug)/index.html")
        }
    }

    func serializeEXIF(_ info: EXIFReader.Info) -> [String: String] {
        var d: [String: String] = [:]
        if let v = info.make { d["make"] = v }
        if let v = info.model { d["model"] = v }
        if let v = info.lens { d["lens"] = v }
        if let v = info.iso { d["iso"] = String(v) }
        if let v = info.aperture { d["aperture"] = String(v) }
        if let v = info.shutter { d["shutter"] = v }
        if let v = info.focalLength { d["focalLength"] = String(Int(v)) }
        if let v = info.dateTimeOriginal { d["dateTime"] = DateUtil.iso.string(from: v) }
        if let v = info.latitude { d["latitude"] = String(v) }
        if let v = info.longitude { d["longitude"] = String(v) }
        return d
    }

    // MARK: - 辅助

    func readTemplate(engine: TemplateEngine, name: String) -> String {
        let path = (themeRoot as NSString).appendingPathComponent("templates/\(name).html")
        if let text = FSUtil.readText(path) { return text }
        engine.warnings.append("模板缺失：\(name).html（已使用 fallback）")
        // 简单回退模板
        return "<!DOCTYPE html><html><head><meta charset=\"UTF-8\"/><title>{{site.title}}</title></head><body><main class=\"container\"><h1>{{site.title}}</h1>{{{content}}}</main></body></html>"
    }

    func pickLayout(engine: TemplateEngine, name: String) -> String {
        let path = (themeRoot as NSString).appendingPathComponent("templates/\(name).html")
        if let text = FSUtil.readText(path) { return text }
        return readTemplate(engine: engine, name: "post")
    }

    func mergeThemeDefaults(into site: inout [String: Any], themeRoot: String) {
        let path = (themeRoot as NSString).appendingPathComponent("theme.yaml")
        guard let text = FSUtil.readText(path) else { return }
        let dict = MiniYAML.load(text)
        guard let cfg = dict["config"] as? [String: Any] else { return }
        if var theme = site["theme"] as? [String: Any] {
            for (k, v) in cfg where theme[k] == nil {
                theme[k] = v
            }
            site["theme"] = theme
        } else {
            site["theme"] = cfg
        }
    }

    func wrapHTML(_ body: String, config: SiteConfig) -> String {
        if body.lowercased().contains("<!doctype") { return body }
        let html = """
        <!DOCTYPE html>
        <html lang="\(config.language)">
        <head>
            <meta charset="UTF-8"/>
            <meta name="viewport" content="width=device-width, initial-scale=1"/>
            <title>\(config.title)</title>
            <meta name="description" content="\(config.description.htmlEscaped)"/>
            <link rel="alternate" type="application/rss+xml" title="\(config.title)" href="/rss.xml"/>
            <link rel="stylesheet" href="/static/css/main.css"/>
        </head>
        <body>
        \(body)
        </body>
        </html>
        """
        return config.minifyHTML ? HTMLMinifier.minify(html) : html
    }

    /// 把 src 目录下的所有文件复制到 dst 目录下(保留子目录结构)。
    /// 若 dst 不存在则自动创建。若 src 不存在则跳过。
    func copyStaticFolder(from src: String, to dst: String) {
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
                copyStaticFolder(from: s, to: d)
            } else {
                if fm.fileExists(atPath: d) { try? fm.removeItem(atPath: d) }
                try? fm.copyItem(atPath: s, toPath: d)
            }
        }
    }

    func dictToPage(_ d: [String: Any]) -> Page? {
        guard let title = d["title"] as? String else { return nil }
        var p = Page(
            id: (d["id"] as? String) ?? title,
            kind: Page.Kind(rawValue: d["kind"] as? String ?? "post") ?? .post,
            sourcePath: d["sourcePath"] as? String ?? "",
            relSourcePath: d["relSourcePath"] as? String ?? "",
            title: title,
            date: (d["date"] as? Date) ?? Date(),
            tags: d["tags"] as? [String] ?? [],
            categories: d["categories"] as? [String] ?? [],
            draft: d["draft"] as? Bool ?? false,
            layout: d["layout"] as? String ?? "post",
            slug: d["slug"] as? String ?? title,
            cover: d["cover"] as? String,
            excerpt: d["excerpt"] as? String,
            url: d["url"] as? String ?? "",
            outPath: d["outPath"] as? String ?? "",
            contentHTML: d["content"] as? String ?? "",
            contentRaw: d["contentRaw"] as? String ?? ""
        )
        p.extra = d
        return p
    }
}

public struct BuildResult {
    public var pages: [Page] = []
    public var generated: [String] = []
    public var errors: [String] = []
    public var warnings: [String] = []
    public var elapsed: TimeInterval = 0
}
