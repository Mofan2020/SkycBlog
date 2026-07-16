import Foundation
import SkycBlogCore

/// `blog init <name>` 命令。
struct InitCommand {
    static func run(args: [String]) {
        guard let name = args.first, !name.isEmpty else {
            Log.error("用法: blog init <name>")
            exit(1)
        }
        let parent = FileManager.default.currentDirectoryPath
        let target = (parent as NSString).appendingPathComponent(name)
        do {
            try ProjectScaffold.createProject(at: target, name: name, language: "zh-CN")
            Log.success("项目已创建：\(target)")
            Log.info("下一步：")
            Log.info("  cd \(name)")
            Log.info("  blog build")
            Log.info("  blog serve")
        } catch {
            Log.error("创建失败：\(error.localizedDescription)")
            exit(1)
        }
    }
}
