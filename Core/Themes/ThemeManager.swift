import Foundation

/// 主题管理：查找、复制默认主题。
public enum ThemeManager {
    public static func themeRoot(projectRoot: String, themeName: String) -> String {
        let p = (projectRoot as NSString).appendingPathComponent("themes/\(themeName)")
        if FileManager.default.fileExists(atPath: p) { return p }
        return p
    }

    /// 如果用户项目缺主题目录，从内置数据展开默认主题。
    public static func copyDefaultIfMissing(projectRoot: String, themeName: String) {
        let dst = (projectRoot as NSString).appendingPathComponent("themes/\(themeName)")
        if FileManager.default.fileExists(atPath: (dst as NSString).appendingPathComponent("theme.yaml")) {
            return
        }
        // 1. 强制从内嵌数据展开（最可靠的路径，不依赖 Bundle/磁盘）
        FSUtil.ensureDirectory(dst)
        EmbeddedTheme.materialize(targetDirectory: dst)
    }

    /// 查找 bundle 资源路径。
    public static func bundleResourcePath(named: String) -> String? {
        // 1. 当前进程 Bundle 中查找
        let candidates = [
            Bundle.main.url(forResource: named, withExtension: nil),
            Bundle.main.resourceURL?.appendingPathComponent(named),
        ]
        for c in candidates {
            if let url = c, FileManager.default.fileExists(atPath: url.path) { return url.path }
        }
        // 2. SkycBlogCore.framework bundle
        let core = Bundle(identifier: "com.skyc8266.skycblog.SkycBlogCore")
        if let url = core?.url(forResource: named, withExtension: nil) {
            return url.path
        }
        // 3. 任何已加载 framework 的 bundle
        for b in Bundle.allFrameworks + Bundle.allBundles {
            if let url = b.url(forResource: named, withExtension: nil) {
                return url.path
            }
        }
        FileHandle.standardError.write(Data("[theme-warn] 未找到内嵌主题资源 \(named)\n".utf8))
        return nil
    }

    public static func listThemes(projectRoot: String) -> [String] {
        let dir = (projectRoot as NSString).appendingPathComponent("themes")
        guard FileManager.default.fileExists(atPath: dir) else { return [] }
        return (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
    }
}
