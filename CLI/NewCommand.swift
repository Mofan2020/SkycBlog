import Foundation
import SkycBlogCore

/// `blog new "<标题>"` 命令：创建一篇新文章。
struct NewCommand {
    static func run(args: [String]) {
        let title: String
        if args.isEmpty {
            print("文章标题: ", terminator: "")
            guard let line = readLine(), !line.isEmpty else { Log.error("请提供标题"); exit(1) }
            title = line
        } else {
            title = args.joined(separator: " ")
        }
        let cwd = FileManager.default.currentDirectoryPath
        do {
            let path = try ProjectScaffold.createPost(projectRoot: cwd, title: title)
            Log.success("已创建：\(path)")
        } catch {
            Log.error(error.localizedDescription)
            exit(1)
        }
    }
}
