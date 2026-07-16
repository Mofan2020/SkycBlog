import Foundation

/// 项目脚手架：在指定目录创建一份完整的 SkycBlog 博客工程。
public enum ProjectScaffold {
    public struct ProjectInitError: LocalizedError {
        public let message: String
        public var errorDescription: String? { message }
        public init(_ message: String) { self.message = message }
    }

    /// 在指定目录创建博客项目。
    /// - Parameters:
    ///   - target: 项目目录的绝对路径（不存在时创建）
    ///   - name: 项目名（同时作为目录名）
    ///   - language: 站点语言（zh-CN / en / ja 等）
    public static func createProject(at target: String, name: String, language: String) throws {
        if FileManager.default.fileExists(atPath: target) {
            throw ProjectInitError("目录已存在：\(target)")
        }
        FSUtil.ensureDirectory(target)
        FSUtil.ensureDirectory("\(target)/content/_posts")
        FSUtil.ensureDirectory("\(target)/content/_drafts")
        FSUtil.ensureDirectory("\(target)/content/pages")
        FSUtil.ensureDirectory("\(target)/content/albums")
        FSUtil.ensureDirectory("\(target)/static/images")
        FSUtil.ensureDirectory("\(target)/scripts")
        FSUtil.ensureDirectory("\(target)/themes")

        let config = """
        title: \(name)
        description: 一个使用 SkycBlog 创建的博客
        author: ""
        language: \(language)
        baseURL: /
        outputDir: output
        buildDrafts: false
        paginationSize: 10
        theme: default
        permalink: /:year/:month/:day/:slug/
        minifyHTML: true
        fingerprintAssets: false
        generateSearchIndex: true
        generateRSS: true
        generateSitemap: true
        themeConfig:
          colors:
            primary: "#3b82f6"
          paginationSize: 10
        deploy:
          github:
            method: git
            repo: ""
            branch: gh-pages
          cloudflare:
            accountID: ""
            projectName: "\(name)"
        """
        FSUtil.writeText(config, to: "\(target)/config.yaml")

        ThemeManager.copyDefaultIfMissing(projectRoot: target, themeName: "default")

        let post = """
        ---
        title: Hello, SkycBlog
        date: \(DateUtil.yyyyMMdd.string(from: Date())) 09:00:00
        tags: [示例, 入门]
        categories: [技术]
        ---

        # 欢迎使用 SkycBlog

        这是你的第一篇文章，编辑 `content/_posts/` 下的 Markdown 文件即可开始写作。

        ## 主要功能

        - 纯 Swift 构建引擎
        - SwiftUI macOS 应用
        - 主题化（兼容 Hexo/Hugo）
        - 插件系统（JavaScriptCore）
        - EXIF 相册
        - 一键部署到 GitHub Pages / Cloudflare Pages

        ```swift
        // 甚至支持代码高亮
        print("Hello, SkycBlog!")
        ```

        > 开始你的博客之旅吧 🚀
        """
        FSUtil.writeText(post, to: "\(target)/content/_posts/hello-skycblog.md")

        let about = """
        ---
        title: 关于
        layout: page
        ---

        # 关于本站

        一个用 **SkycBlog** 构建的静态博客。
        """
        FSUtil.writeText(about, to: "\(target)/content/pages/about.md")

        let plugin = """
        // 示例插件：构建开始前在控制台打印
        hook('beforeBuild', function(ctx) {
            log('准备构建 ' + ctx.site.title + '，共 ' + ctx.posts.length + ' 篇文章');
        });
        """
        FSUtil.writeText(plugin, to: "\(target)/scripts/hello.js")
    }

    /// 在指定项目根目录创建新文章。
    @discardableResult
    public static func createPost(projectRoot: String, title: String) throws -> String {
        let postsDir = (projectRoot as NSString).appendingPathComponent("content/_posts")
        guard FileManager.default.fileExists(atPath: postsDir) else {
            throw ProjectInitError("未找到 content/_posts 目录，请先运行 `blog init`")
        }
        let slug = slugify(title)
        let date = DateUtil.yyyyMMdd.string(from: Date())
        let filename = "\(date)-\(slug).md"
        let path = (postsDir as NSString).appendingPathComponent(filename)
        let text = """
        ---
        title: \(title)
        date: \(date) 09:00:00
        tags: []
        categories: []
        ---

        # \(title)

        在此书写正文。
        """
        FSUtil.writeText(text, to: path)
        return path
    }

    public static func slugify(_ s: String) -> String {
        let lower = s.lowercased()
        var out = ""
        for ch in lower {
            if ch.isLetter || ch.isNumber || ch == "-" {
                out.append(ch)
            } else if ch == " " || ch == "_" {
                out.append("-")
            }
        }
        return out
    }
}
