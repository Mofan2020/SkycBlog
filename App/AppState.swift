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

    // MARK: - 分类 / 标签

    func addTag(_ tag: String) {
        guard let project = project, !project.allTags.keys.contains(tag) else { return }
        // 在 _posts/_drafts/pages 中找一篇空 front matter 加上,或更新 frontMatter
        // 更友好的做法：让用户逐篇编辑；这里不自动注入,只作为 UI 占位（暂未做"全局标签池"）
        log(.info("提示：在文章上添加标签 #\(tag) 即可使用"))
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
    case settings = "项目设置"

    var id: String { rawValue }

    static let contentSections: [LibrarySection] = [.posts, .drafts, .pages, .albums]
    static let taxonomySections: [LibrarySection] = [.tags, .categories]
    static let adminSections: [LibrarySection] = [.assets, .plugins, .settings]

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
        case .settings: return "gearshape"
        }
    }
}
