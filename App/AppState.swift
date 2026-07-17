import Foundation
import SwiftUI
import SkycBlogCore
import AppKit

/// 全局应用状态。
@MainActor
final class AppState: ObservableObject {
    // MARK: 模态
    enum Sheet: String, Identifiable {
        case newProject, openProject, newPost, projectInfo, deploy
        var id: String { rawValue }
    }

    /// 非枚举型 sheet,用 struct 携带参数（重命名/编辑元数据等）
    struct PageRef: Identifiable, Equatable { let id: String }
    struct AlbumRef: Identifiable, Equatable { let id: String }

    // MARK: 视图状态
    @Published var sheet: Sheet? = nil
    @Published var renamePageTarget: Page? = nil
    @Published var metadataPageTarget: Page? = nil
    @Published var renameAlbumTarget: Page? = nil
    @Published var newAlbumSheet: Bool = false
    @Published var selectedAlbumID: String? = nil
    @Published var selectedAlbumForDetail: Page? = nil
    @Published var consoleVisible: Bool = true
    @Published var selection: LibrarySection = .posts
    @Published var selectedPageID: String? = nil

    // MARK: 项目
    @Published var project: BlogProject? = nil
    @Published var recentProjects: [URL] = []

    // MARK: 状态
    @Published var isWorking: Bool = false
    @Published var isServing: Bool = false
    @Published var lastBuild: BuildSummary? = nil
    @Published var previewURL: URL? = nil

    // MARK: 控制台日志
    @Published var console: [LogEntry] = []

    // MARK: 编辑器状态
    @Published var editor: EditorState = EditorState()

    private var server: LocalServer? = nil

    init() {
        loadRecents()
    }

    // MARK: - 项目

    func openProject(at url: URL) {
        do {
            let p = try BlogProject.load(root: url)
            self.project = p
            self.selectedPageID = p.posts.first?.id
            log(.success("已打开项目：\(p.root.lastPathComponent)"))
            addRecent(url)
        } catch {
            log(.error("打开项目失败：\(error.localizedDescription)"))
        }
    }

    func createProject(at parent: URL, name: String, language: String) {
        do {
            let target = parent.appendingPathComponent(name)
            try ProjectScaffold.createProject(at: target.path, name: name, language: language)
            let p = try BlogProject.load(root: target)
            self.project = p
            self.selectedPageID = p.posts.first?.id
            log(.success("已创建项目：\(name)"))
            addRecent(target)
        } catch {
            log(.error("创建项目失败：\(error.localizedDescription)"))
        }
    }

    func closeProject() {
        stopServer()
        self.project = nil
        self.selectedPageID = nil
        self.lastBuild = nil
        self.previewURL = nil
        self.editor = EditorState()
    }

    func revealProjectInFinder() {
        guard let url = project?.root else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: - 构建

    func runBuild(clean: Bool = false) {
        guard let project = project else { return }
        isWorking = true
        log(.info(clean ? "清理并构建…" : "开始构建…"))
        let projectRoot = project.root.path
        let captured: SiteConfig = project.config
        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                if clean {
                    let outDir = captured.outputDir
                    try? FileManager.default.removeItem(atPath: outDir)
                }
                var cfg = captured
                cfg.projectRoot = projectRoot
                let builder = Builder(config: cfg)
                let start = Date()
                let result = try builder.build()
                let elapsed = Date().timeIntervalSince(start)
                let summary = BuildSummary(date: Date(), fileCount: result.generated.count, elapsed: elapsed, success: result.errors.isEmpty)
                await MainActor.run {
                    self?.lastBuild = summary
                    self?.isWorking = false
                    if !result.errors.isEmpty {
                        self?.log(.error("构建完成但有错误："))
                        for e in result.errors { self?.log(.error("  · \(e)")) }
                    }
                    if !result.warnings.isEmpty {
                        for w in result.warnings.prefix(5) { self?.log(.warn(w)) }
                    }
                    self?.log(.success("构建完成 · \(result.generated.count) 文件 · \(String(format: "%.2fs", elapsed)) · 输出：\(cfg.outputDir)"))
                    // 刷新项目内容
                    self?.project?.refresh()
                }
            } catch {
                await MainActor.run {
                    self?.isWorking = false
                    self?.log(.error("构建失败：\(error.localizedDescription)"))
                }
            }
        }
    }

    // MARK: - 预览服务器

    func startServer(autoBuild: Bool = true) {
        guard let project = project else { return }
        guard !isServing else { return }
        let outDir = project.config.outputDir
        // 如果 output 目录不存在或没有 index.html,且允许自动构建,先构建一次
        let indexPath = (outDir as NSString).appendingPathComponent("index.html")
        let needsBuild = !FileManager.default.fileExists(atPath: indexPath)
        if needsBuild && autoBuild {
            log(.info("输出目录为空,先构建一次…"))
            runBuild(clean: false)
        }
        do {
            let server = try LocalServer(port: 8765, rootDir: outDir)
            try server.start()
            self.server = server
            self.isServing = true
            self.previewURL = URL(string: "http://localhost:8765/")
            log(.success("预览已启动 · http://localhost:8765/  ·  根目录：\(outDir)"))
        } catch {
            log(.error("启动预览失败：\(error.localizedDescription)"))
        }
    }

    func stopServer() {
        server?.stop()
        server = nil
        isServing = false
        previewURL = nil
        log(.info("预览已停止"))
    }

    // MARK: - 文章

    func createNewPost(title: String) {
        guard let project = project else { return }
        do {
            let path = try ProjectScaffold.createPost(projectRoot: project.root.path, title: title)
            project.refresh()
            log(.success("已创建文章：\((path as NSString).lastPathComponent)"))
            // 自动打开
            if let page = project.posts.first(where: { $0.sourcePath == path }) {
                selectedPageID = page.id
            }
        } catch {
            log(.error("创建文章失败：\(error.localizedDescription)"))
        }
    }

    func deletePage(_ page: Page) {
        do {
            try FileManager.default.removeItem(atPath: page.sourcePath)
            project?.refresh()
            if selectedPageID == page.id { selectedPageID = project?.posts.first?.id }
            log(.info("已删除：\(page.title)"))
        } catch {
            log(.error("删除失败：\(error.localizedDescription)"))
        }
    }

    // MARK: - 文章管理

    func renamePage(_ page: Page, to newTitle: String) {
        guard let project = project else { return }
        let oldID = page.id
        do {
            let newPath = try PostManager.renameFile(at: page.sourcePath, newTitle: newTitle)
            project.refresh()
            // 选中新文章
            if let p = (project.posts + project.drafts + project.pages).first(where: { $0.sourcePath == newPath }) {
                selectedPageID = p.id
            } else {
                if selectedPageID == oldID { selectedPageID = project.posts.first?.id }
            }
            log(.success("已重命名为：\(newTitle)"))
        } catch {
            log(.error("重命名失败：\(error.localizedDescription)"))
        }
    }

    func updatePageMetadata(_ page: Page,
                            title: String? = nil,
                            tags: [String]? = nil,
                            categories: [String]? = nil,
                            draft: Bool? = nil) {
        do {
            try PostManager.updateMetadata(at: page.sourcePath,
                                           title: title, tags: tags, categories: categories, draft: draft)
            project?.refresh()
            log(.success("已更新：\(title ?? page.title)"))
        } catch {
            log(.error("更新失败：\(error.localizedDescription)"))
        }
    }

    // MARK: - 相册

    func createAlbum(title: String) {
        guard let project = project else { return }
        do {
            _ = try AlbumManager.createAlbum(projectRoot: project.root.path, title: title)
            project.refresh()
            log(.success("已创建相册：\(title)"))
        } catch {
            log(.error("创建相册失败：\(error.localizedDescription)"))
        }
    }

    func renameAlbum(oldName: String, newTitle: String) {
        guard let project = project else { return }
        do {
            try AlbumManager.renameAlbum(projectRoot: project.root.path, oldName: oldName, newName: newTitle)
            // 同步 index.md 的 title
            let dir = AlbumManager.albumDir(projectRoot: project.root.path, albumName: AlbumManager.slugify(newTitle))
            let indexPath = (dir as NSString).appendingPathComponent("index.md")
            if let text = try? String(contentsOfFile: indexPath, encoding: .utf8) {
                let (fm, body) = try PostManager.parse(text)
                var newFM = fm
                newFM.title = newTitle
                try PostManager.render(newFM, body: body).write(toFile: indexPath, atomically: true, encoding: .utf8)
            }
            project.refresh()
            log(.success("已重命名相册：\(newTitle)"))
        } catch {
            log(.error("重命名相册失败：\(error.localizedDescription)"))
        }
    }

    func deleteAlbum(name: String) {
        guard let project = project else { return }
        do {
            try AlbumManager.deleteAlbum(projectRoot: project.root.path, name: name)
            project.refresh()
            log(.info("已删除相册：\(name)"))
        } catch {
            log(.error("删除相册失败：\(error.localizedDescription)"))
        }
    }

    func addMedia(albumName: String, sourceURLs: [URL]) {
        guard let project = project else { return }
        for url in sourceURLs {
            do {
                let name = try AlbumManager.addMedia(projectRoot: project.root.path, albumName: albumName, sourceURL: url)
                log(.success("已添加：\(name)"))
            } catch {
                log(.error("添加失败：\(url.lastPathComponent) — \(error.localizedDescription)"))
            }
        }
        project.refresh()
    }

    func removeMedia(albumName: String, filename: String) {
        guard let project = project else { return }
        do {
            try AlbumManager.removeMedia(projectRoot: project.root.path, albumName: albumName, filename: filename)
            project.refresh()
            log(.info("已删除：\(filename)"))
        } catch {
            log(.error("删除失败：\(error.localizedDescription)"))
        }
    }

    func renameMedia(albumName: String, oldName: String, newName: String) {
        guard let project = project else { return }
        do {
            try AlbumManager.renameMedia(projectRoot: project.root.path, albumName: albumName, oldName: oldName, newName: newName)
            project.refresh()
            log(.info("已重命名：\(newName)"))
        } catch {
            log(.error("重命名失败：\(error.localizedDescription)"))
        }
    }

    func albumMediaList(name: String) -> [AlbumManager.MediaInfo] {
        guard let project = project else { return [] }
        let dir = AlbumManager.albumDir(projectRoot: project.root.path, albumName: name)
        return AlbumManager.listMedia(in: dir)
    }

    func openAlbumDetail(album: Page) {
        selectedAlbumForDetail = album
        selectedAlbumID = album.id
    }

    // MARK: - 插件

    func listPlugins() -> [PluginInfo] {
        guard let project = project else { return [] }
        let dir = (project.root.path as NSString).appendingPathComponent("scripts")
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
        return files.filter { $0.hasSuffix(".js") }.sorted().map { name in
            PluginInfo(name: name,
                       enabled: !project.config.disabledPlugins.contains(name),
                       path: (dir as NSString).appendingPathComponent(name))
        }
    }

    func setPluginEnabled(name: String, enabled: Bool) {
        guard let project = project else { return }
        var cfg = project.config
        var list = cfg.disabledPlugins
        if enabled {
            list.removeAll { $0 == name }
        } else {
            if !list.contains(name) { list.append(name) }
        }
        cfg.disabledPlugins = list
        do {
            try ConfigWriter.write(cfg, to: project.root.path)
            // 重新加载
            self.project = try BlogProject.load(root: project.root)
            log(.info("插件 \(name) \(enabled ? "已启用" : "已禁用")"))
        } catch {
            log(.error("保存配置失败：\(error.localizedDescription)"))
        }
    }

    // MARK: - 主题

    /// 列出项目 themes/ 下所有主题, 标记当前激活的
    func listThemes() -> [(info: ThemeInfo, isActive: Bool)] {
        guard let project = project else { return [] }
        let active = project.config.themeName
        let list = ThemeManager.listThemes(projectRoot: project.root.path)
        return list.map { ($0, $0.name == active) }
    }

    /// 激活一个主题 (写 config.yaml 的 theme 字段), 激活后自动 refresh
    func activateTheme(name: String) {
        guard let project = project else { return }
        let result = ThemeManager.activateTheme(name: name, projectRoot: project.root.path)
        if result.ok {
            project.refresh()
            log(.success(result.message))
        } else {
            log(.error(result.message))
        }
    }

    /// 从本地路径安装一个主题
    func installThemeFromPath(source: String, name: String) {
        guard let project = project else { return }
        let result = ThemeManager.installTheme(fromSource: source, projectRoot: project.root.path, destName: name)
        if result.ok {
            project.refresh()
            log(.success(result.message))
        } else {
            log(.error(result.message))
        }
    }

    /// 在 Finder 中显示主题目录
    func revealThemeInFinder(name: String) {
        guard let project = project else { return }
        let root = ThemeManager.themeRoot(projectRoot: project.root.path, themeName: name)
        guard FileManager.default.fileExists(atPath: root) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: root)])
    }

    // MARK: - 分类 / 标签

    /// 确保某个标签存在 (写入隐藏 _draft 虚拟草稿, 用户可在文章元数据里删除)
    func ensureTagExists(_ name: String) {
        ensureTaxonomy(name: name, kind: "tags")
    }

    func ensureCategoryExists(_ name: String) {
        ensureTaxonomy(name: name, kind: "categories")
    }

    /// 写入一个隐藏 draft, 包含指定的 tag/cat, 让其出现在列表里。
    /// 用户随后在文章元数据 sheet 里调整。
    private func ensureTaxonomy(name: String, kind: String) {
        guard let project = project else { return }
        let v = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !v.isEmpty else { return }

        // 已存在就不写了
        let existing: Set<String>
        switch kind {
        case "tags":       existing = Set(project.allTags.keys)
        case "categories": existing = Set(project.allCategories.keys)
        default:           existing = []
        }
        if existing.contains(v) {
            log(.info("`\(v)` 已存在"))
            return
        }

        let draftsDir = project.root.appendingPathComponent("content/_drafts")
        try? FileManager.default.createDirectory(at: draftsDir, withIntermediateDirectories: true)
        let path = draftsDir.appendingPathComponent("_taxonomy-\(kind).md")

        // 读已存在 front matter (如果存在)
        var currentTags: [String] = []
        var currentCats: [String] = []
        if let text = try? String(contentsOf: path, encoding: .utf8),
           let parsed = try? PostManager.parse(text) {
            currentTags = parsed.0.tags
            currentCats = parsed.0.categories
        }
        let newTags: [String] = (kind == "tags") ? Array(Set(currentTags + [v])).sorted() : currentTags
        let newCats: [String] = (kind == "categories") ? Array(Set(currentCats + [v])).sorted() : currentCats

        // 直接手写 YAML 头 (避免依赖 FrontMatter init)
        var lines: [String] = ["---"]
        lines.append("title: \"Tag Pool (auto)\"")
        lines.append("date: 1970-01-01 00:00:00")
        lines.append("draft: true")
        lines.append("layout: post")
        if newTags.isEmpty {
            lines.append("tags: []")
        } else {
            lines.append("tags: [" + newTags.map { "\"\($0)\"" }.joined(separator: ", ") + "]")
        }
        if newCats.isEmpty {
            lines.append("categories: []")
        } else {
            lines.append("categories: [" + newCats.map { "\"\($0)\"" }.joined(separator: ", ") + "]")
        }
        lines.append("---")
        lines.append("")
        lines.append("<!-- 虚拟草稿, 用来集中保存标签/分类池. 在文章上编辑元数据 sheet 里调整实际使用. -->")

        do {
            let text = lines.joined(separator: "\n")
            try text.write(toFile: path.path, atomically: true, encoding: .utf8)
            project.refresh()
            log(.success("已新建\(kind == "tags" ? "标签" : "分类") `\(v)`"))
        } catch {
            log(.error("写入失败：\(error.localizedDescription)"))
        }
    }

    /// 重命名一个标签：对所有 markdown front matter 中的 `tags` 列表做替换。
    func renameTagEverywhere(from old: String, to new: String) {
        guard let project = project else { return }
        var changed = 0
        let sources = collectAllMarkdownSources(projectRoot: project.root.path)
        for path in sources {
            do {
                let text = try String(contentsOfFile: path, encoding: .utf8)
                let (fm, body) = try PostManager.parse(text)
                var fmLocal = fm
                var tags = fmLocal.tags
                var touched = false
                for i in tags.indices where tags[i] == old {
                    tags[i] = new
                    touched = true
                }
                // 删重复
                if touched {
                    var seen = Set<String>()
                    tags = tags.filter { seen.insert($0).inserted }
                    fmLocal.tags = tags
                    try PostManager.render(fmLocal, body: body).write(toFile: path, atomically: true, encoding: .utf8)
                    changed += 1
                }
            } catch {
                log(.error("更新 \(path) 失败：\(error.localizedDescription)"))
            }
        }
        project.refresh()
        log(.success("已把标签 `\(old)` → `\(new)` (涉及 \(changed) 篇文章)"))
    }

    func removeTagEverywhere(_ tag: String) {
        guard let project = project else { return }
        var changed = 0
        let sources = collectAllMarkdownSources(projectRoot: project.root.path)
        for path in sources {
            do {
                let text = try String(contentsOfFile: path, encoding: .utf8)
                let (fm, body) = try PostManager.parse(text)
                var fmLocal = fm
                let before = fmLocal.tags.count
                let after = fmLocal.tags.filter { $0 != tag }
                if after.count != before {
                    fmLocal.tags = after
                    try PostManager.render(fmLocal, body: body).write(toFile: path, atomically: true, encoding: .utf8)
                    changed += 1
                }
            } catch {
                log(.error("更新 \(path) 失败：\(error.localizedDescription)"))
            }
        }
        project.refresh()
        log(.success("已从 \(changed) 篇文章移除标签 `\(tag)`"))
    }

    func renameCategoryEverywhere(from old: String, to new: String) {
        guard let project = project else { return }
        var changed = 0
        let sources = collectAllMarkdownSources(projectRoot: project.root.path)
        for path in sources {
            do {
                let text = try String(contentsOfFile: path, encoding: .utf8)
                let (fm, body) = try PostManager.parse(text)
                var fmLocal = fm
                var cats = fmLocal.categories
                var touched = false
                for i in cats.indices where cats[i] == old {
                    cats[i] = new
                    touched = true
                }
                if touched {
                    var seen = Set<String>()
                    cats = cats.filter { seen.insert($0).inserted }
                    fmLocal.categories = cats
                    try PostManager.render(fmLocal, body: body).write(toFile: path, atomically: true, encoding: .utf8)
                    changed += 1
                }
            } catch {
                log(.error("更新 \(path) 失败：\(error.localizedDescription)"))
            }
        }
        project.refresh()
        log(.success("已把分类 `\(old)` → `\(new)` (涉及 \(changed) 篇文章)"))
    }

    func removeCategoryEverywhere(_ cat: String) {
        guard let project = project else { return }
        var changed = 0
        let sources = collectAllMarkdownSources(projectRoot: project.root.path)
        for path in sources {
            do {
                let text = try String(contentsOfFile: path, encoding: .utf8)
                let (fm, body) = try PostManager.parse(text)
                var fmLocal = fm
                let before = fmLocal.categories.count
                let after = fmLocal.categories.filter { $0 != cat }
                if after.count != before {
                    fmLocal.categories = after
                    try PostManager.render(fmLocal, body: body).write(toFile: path, atomically: true, encoding: .utf8)
                    changed += 1
                }
            } catch {
                log(.error("更新 \(path) 失败：\(error.localizedDescription)"))
            }
        }
        project.refresh()
        log(.success("已从 \(changed) 篇文章移除分类 `\(cat)`"))
    }

    /// 收集项目里所有 markdown 源文件（_posts、_drafts、pages、albums/*/index.md）。
    private func collectAllMarkdownSources(projectRoot: String) -> [String] {
        let fm = FileManager.default
        var out: [String] = []
        let dirs = [
            "\(projectRoot)/content/_posts",
            "\(projectRoot)/content/_drafts",
            "\(projectRoot)/content/pages",
        ]
        for d in dirs where fm.fileExists(atPath: d) {
            if let files = try? fm.contentsOfDirectory(atPath: d) {
                for f in files where f.hasSuffix(".md") {
                    out.append((d as NSString).appendingPathComponent(f))
                }
            }
        }
        let albumRoot = "\(projectRoot)/content/albums"
        if fm.fileExists(atPath: albumRoot), let albums = try? fm.contentsOfDirectory(atPath: albumRoot) {
            for a in albums {
                let dir = (albumRoot as NSString).appendingPathComponent(a)
                var isDir: ObjCBool = false
                fm.fileExists(atPath: dir, isDirectory: &isDir)
                if isDir.boolValue {
                    let idx = (dir as NSString).appendingPathComponent("index.md")
                    if fm.fileExists(atPath: idx) { out.append(idx) }
                }
            }
        }
        return out
    }

    // MARK: - 日志

    func log(_ entry: LogEntry) {
        console.append(entry)
        if console.count > 1000 { console.removeFirst(console.count - 1000) }
    }

    func clearLog() { console.removeAll() }

    // MARK: - 最近项目

    private static let recentsKey = "SkycBlog.recents"

    private func loadRecents() {
        if let arr = UserDefaults.standard.array(forKey: Self.recentsKey) as? [String] {
            recentProjects = arr.map { URL(fileURLWithPath: $0) }
        }
    }

    private func addRecent(_ url: URL) {
        var arr = recentProjects.filter { $0 != url }
        arr.insert(url, at: 0)
        if arr.count > 8 { arr = Array(arr.prefix(8)) }
        recentProjects = arr
        UserDefaults.standard.set(arr.map(\.path), forKey: Self.recentsKey)
    }
}

// MARK: - 辅助模型

struct BuildSummary: Equatable {
    let date: Date
    let fileCount: Int
    let elapsed: Double
    let success: Bool
}

struct LogEntry: Identifiable, Equatable {
    enum Level: String { case info, success, warn, error }
    let id = UUID()
    let date = Date()
    let level: Level
    let message: String

    static func info(_ m: String) -> LogEntry { LogEntry(level: .info, message: m) }
    static func success(_ m: String) -> LogEntry { LogEntry(level: .success, message: m) }
    static func warn(_ m: String) -> LogEntry { LogEntry(level: .warn, message: m) }
    static func error(_ m: String) -> LogEntry { LogEntry(level: .error, message: m) }
}

/// 插件元数据。
struct PluginInfo: Identifiable, Equatable {
    let name: String
    let enabled: Bool
    let path: String
    var id: String { name }
}

/// 编辑器状态。
final class EditorState: ObservableObject {
    @Published var text: String = ""
    @Published var previewVisible: Bool = true
    @Published var isDirty: Bool = false
    @Published var lastSave: Date? = nil
    @Published var pageID: String? = nil
}

/// 内容库分区。
enum LibrarySection: String, CaseIterable, Identifiable, Hashable {
    case posts = "文章"
    case drafts = "草稿"
    case pages = "页面"
    case albums = "相册"
    case tags = "标签"
    case categories = "分类"
    case assets = "资源"
    case plugins = "插件"
    case themes = "主题"
    case settings = "项目设置"

    var id: String { rawValue }

    static let contentSections: [LibrarySection] = [.posts, .drafts, .pages, .albums]
    static let taxonomySections: [LibrarySection] = [.tags, .categories]
    static let adminSections: [LibrarySection] = [.themes, .assets, .plugins, .settings]

    var systemImage: String {
        switch self {
        case .posts: return "doc.text"
        case .drafts: return "pencil.and.outline"
        case .pages: return "doc.richtext"
        case .albums: return "photo.stack"
        case .tags: return "tag"
        case .categories: return "folder"
        case .assets: return "photo"
        case .plugins: return "puzzlepiece"
        case .themes: return "paintpalette"
        case .settings: return "gearshape"
        }
    }
}
