import Foundation
import SkycBlogCore

/// 对当前打开的博客项目进行内存表示。
final class BlogProject: ObservableObject, Identifiable {
    let id = UUID()
    let root: URL
    let config: SiteConfig
    @Published var posts: [Page] = []
    @Published var pages: [Page] = []
    @Published var drafts: [Page] = []
    @Published var albums: [Page] = []
    @Published var allTags: [String: [Page]] = [:]
    @Published var allCategories: [String: [Page]] = [:]
    @Published var lastBuildResult: BuildResult? = nil

    var outputDir: URL { URL(fileURLWithPath: config.outputDir) }

    static func load(root: URL) throws -> BlogProject {
        let configPath = root.appendingPathComponent("config.yaml").path
        let text = try String(contentsOfFile: configPath, encoding: .utf8)
        let dict = MiniYAML.load(text)
        let projectRoot = root.path
        var config = SiteConfig()
        config.projectRoot = projectRoot
        config.title = (dict["title"] as? String) ?? "My Blog"
        if let desc = dict["description"] as? String { config.description = desc }
        if let author = dict["author"] as? String { config.author = author }
        config.language = (dict["language"] as? String) ?? "zh-CN"
        if let baseURL = dict["baseURL"] as? String { config.baseURL = baseURL }
        config.outputDir = ((dict["outputDir"] as? String) ?? "output").replacingOccurrences(of: "~", with: projectRoot)
        if let themeName = dict["theme"] as? String { config.themeName = themeName }
        config.themeConfig = (dict["themeConfig"] as? [String: Any]) ?? [:]
        config.permalink = (dict["permalink"] as? String) ?? "/:year/:month/:day/:slug/"
        config.paginationSize = (dict["paginationSize"] as? Int) ?? 10
        config.generateRSS = (dict["generateRSS"] as? Bool) ?? true
        config.generateSitemap = (dict["generateSitemap"] as? Bool) ?? true
        config.generateSearchIndex = (dict["generateSearchIndex"] as? Bool) ?? true
        config.minifyHTML = (dict["minifyHTML"] as? Bool) ?? true
        let p = BlogProject(root: root, config: config)
        p.refresh()
        return p
    }

    init(root: URL, config: SiteConfig) {
        self.root = root
        self.config = config
    }

    /// 重新扫描 content 目录。
    func refresh() {
        do {
            let loader = ContentLoader(projectRoot: root.path, config: config)
            try loader.load(includeDrafts: true)
            self.posts = loader.posts().filter { $0.kind == .post }
            self.drafts = loader.draftPages()
            self.pages = loader.pages
            self.albums = loader.albums()
            self.allTags = loader.allTags
            self.allCategories = loader.allCategories
        } catch {
            print("刷新内容失败：\(error)")
        }
    }

    /// 执行一次完整构建。
    func runBuild() throws -> BuildResult {
        let builder = Builder(config: config)
        return builder.build()
    }
}
