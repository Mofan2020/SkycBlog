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
        let projectRoot = root.path
        let config = try ConfigLoader.load(projectRoot: projectRoot)
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
