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

    // MARK: 视图状态
    @Published var sheet: Sheet? = nil
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
                let summary = BuildSummary(date: Date(), fileCount: result.generated.count, elapsed: elapsed, success: true)
                await MainActor.run {
                    self?.lastBuild = summary
                    self?.isWorking = false
                    self?.log(.success("构建完成 · \(result.generated.count) 文件 · \(String(format: "%.2fs", elapsed))"))
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

    func startServer() {
        guard let project = project else { return }
        guard !isServing else { return }
        let outDir = project.config.outputDir
        do {
            let server = try LocalServer(port: 8765, rootDir: outDir)
            try server.start()
            self.server = server
            self.isServing = true
            self.previewURL = URL(string: "http://localhost:8765/")
            log(.success("预览已启动 · http://localhost:8765/"))
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
