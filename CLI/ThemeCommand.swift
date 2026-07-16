import Foundation
import SkycBlogCore

/// `blog theme ...` 命令。
struct ThemeCommand {
    static func run(args: [String]) {
        let sub = args.first ?? "list"
        let rest = Array(args.dropFirst())
        let root = FileManager.default.currentDirectoryPath
        switch sub {
        case "list":
            let names = ThemeManager.listThemes(projectRoot: root)
            if names.isEmpty {
                print("(无主题)")
            } else {
                for n in names { print("• \(n)") }
            }
        case "install":
            guard let url = rest.first else {
                Log.error("用法: blog theme install <url>")
                exit(1)
            }
            installTheme(url: url, projectRoot: root)
        case "info":
            guard let name = rest.first else {
                Log.error("用法: blog theme info <name>")
                exit(1)
            }
            showInfo(name: name, projectRoot: root)
        case "remove":
            guard let name = rest.first else {
                Log.error("用法: blog theme remove <name>")
                exit(1)
            }
            let p = (root as NSString).appendingPathComponent("themes/\(name)")
            try? FileManager.default.removeItem(atPath: p)
            Log.success("已删除主题：\(name)")
        default:
            Log.error("未知子命令：\(sub)")
        }
    }

    static func installTheme(url: String, projectRoot: String) {
        // 简易实现：如果是 HTTP URL，下载 ZIP；如果是 .git 结尾，使用 git clone
        let fm = FileManager.default
        let tmp = NSTemporaryDirectory() + "skycblog-theme-\(UUID().uuidString)"
        try? fm.createDirectory(atPath: tmp, withIntermediateDirectories: true)
        defer { FSUtil.remove(tmp) }
        let name: String
        if url.hasSuffix(".git") {
            let r = Shell.run("/usr/bin/env", ["git", "clone", "--depth=1", url, tmp])
            if r.status != 0 {
                Log.error("git clone 失败：\(r.stderr)")
                return
            }
            name = (url as NSString).lastPathComponent.replacingOccurrences(of: ".git", with: "")
        } else if url.hasSuffix(".zip") {
            let zipPath = tmp + "/theme.zip"
            let r = Shell.run("/usr/bin/curl", ["-L", "-o", zipPath, url])
            if r.status != 0 { Log.error("下载失败：\(r.stderr)"); return }
            _ = Shell.run("/usr/bin/unzip", ["-q", zipPath, "-d", tmp + "/extracted"])
            // 取第一个目录
            let items = (try? fm.contentsOfDirectory(atPath: tmp + "/extracted")) ?? []
            guard let first = items.first else { Log.error("ZIP 包为空"); return }
            try? fm.moveItem(atPath: tmp + "/extracted/\(first)", toPath: tmp + "/theme")
            name = (url as NSString).lastPathComponent.replacingOccurrences(of: ".zip", with: "")
        } else {
            Log.error("仅支持 .git 或 .zip URL")
            return
        }
        let dst = (projectRoot as NSString).appendingPathComponent("themes/\(name)")
        FSUtil.ensureDirectory((projectRoot as NSString).appendingPathComponent("themes"))
        try? fm.removeItem(atPath: dst)
        try? fm.copyItem(atPath: tmp + "/theme", toPath: dst)
        Log.success("主题已安装：\(name)")
        Log.info("在 config.yaml 设置 themeName: \(name) 即可启用")
    }

    static func showInfo(name: String, projectRoot: String) {
        let p = (projectRoot as NSString).appendingPathComponent("themes/\(name)/theme.yaml")
        if let text = FSUtil.readText(p), let dict = MiniYAML.load(text) as? [String: Any] {
            print("主题：\(name)")
            for (k, v) in dict { print("  \(k): \(v)") }
        } else {
            Log.error("找不到主题或无法解析 theme.yaml")
        }
    }
}
