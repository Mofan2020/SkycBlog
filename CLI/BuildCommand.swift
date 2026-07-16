import Foundation
import SkycBlogCore

/// `blog build` 命令。
struct BuildCommand {
    static func run(args: [String]) {
        var includeDrafts = false
        var cliOverrides: [String: String] = [:]
        var configPath: String? = nil
        var i = 0
        while i < args.count {
            let a = args[i]
            switch a {
            case "--drafts": includeDrafts = true
            case "--config":
                i += 1; if i < args.count { configPath = args[i] }
            default:
                if a.hasPrefix("--") {
                    let k = String(a.dropFirst(2))
                    let v: String
                    if i + 1 < args.count, !args[i+1].hasPrefix("--") {
                        v = args[i+1]; i += 1
                    } else { v = "true" }
                    cliOverrides[k] = v
                }
            }
            i += 1
        }
        do {
            let root = FileManager.default.currentDirectoryPath
            let config = try ConfigLoader.load(projectRoot: root, cliOverrides: cliOverrides)
            let builder = Builder(config: config, includeDrafts: includeDrafts)
            let result = builder.build()
            if !result.errors.isEmpty {
                for e in result.errors { Log.error(e) }
                exit(1)
            }
            for w in result.warnings { Log.warn(w) }
        } catch {
            Log.error("构建失败：\(error)")
            exit(1)
        }
    }
}
