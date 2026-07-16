import Foundation
import SkycBlogCore

/// `blog deploy [target]` 命令。
struct DeployCommand {
    static func run(args: [String]) {
        let targetName = args.first ?? "github"
        let root = FileManager.default.currentDirectoryPath
        let config: SiteConfig
        do { config = try ConfigLoader.load(projectRoot: root) } catch {
            Log.error("配置加载失败：\(error)")
            exit(1)
        }
        // 先构建
        let result = Builder(config: config, includeDrafts: config.buildDrafts).build()
        if !result.errors.isEmpty { for e in result.errors { Log.error(e) }; exit(1) }
        Log.info("已构建 \(result.generated.count) 个文件")
        // 选用目标
        var targets: [DeployTarget] = []
        let deployMap = config.deploy
        if targetName == "all" {
            for (k, v) in deployMap {
                if let dict = v as? [String: Any] {
                    targets.append(makeTarget(name: k, config: dict))
                }
            }
        } else {
            guard let entry = deployMap[targetName] as? [String: Any] else {
                Log.error("未找到部署目标：\(targetName)。请在 config.yaml 的 deploy.<target> 配置。")
                exit(1)
            }
            targets.append(makeTarget(name: targetName, config: entry))
        }
        if targets.isEmpty {
            Log.error("没有可用的部署目标，请检查 config.yaml 的 deploy 字段")
            exit(1)
        }
        for t in targets {
            Log.info("部署到 \(t.name) ...")
            do {
                let r = try t.deploy(outputDir: config.outputDir, config: deployMap[t.name] as? [String: Any] ?? [:])
                if r.success {
                    Log.success("\(t.name): \(r.message)")
                    if let u = r.url { Log.info("URL: \(u)") }
                } else {
                    Log.error("\(t.name): \(r.message)")
                }
            } catch {
                Log.error("\(t.name) 失败：\(error)")
            }
        }
    }

    static func makeTarget(name: String, config: [String: Any]) -> DeployTarget {
        switch name {
        case "github": return GitHubPagesDeploy()
        case "cloudflare", "cf": return CloudflarePagesDeploy()
        case "netlify": return StaticExportDeploy(name: "netlify")
        case "vercel": return StaticExportDeploy(name: "vercel")
        default: return StaticExportDeploy(name: name)
        }
    }
}
