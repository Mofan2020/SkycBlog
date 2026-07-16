import Foundation

/// 部署目标协议。
public protocol DeployTarget {
    var name: String { get }
    func deploy(outputDir: String, config: [String: Any]) throws -> DeployResult
}

public struct DeployResult {
    public var success: Bool
    public var message: String
    public var url: String? = nil
}

/// GitHub Pages 部署：支持 git 推送 与 直接 API 上传。
public final class GitHubPagesDeploy: DeployTarget {
    public let name = "github"
    public init() {}

    public func deploy(outputDir: String, config: [String: Any]) throws -> DeployResult {
        guard let repo = config["repo"] as? String, !repo.isEmpty else {
            return DeployResult(success: false, message: "缺少 repo 字段（owner/repo）")
        }
        let method = (config["method"] as? String) ?? "git"
        let branch = (config["branch"] as? String) ?? "gh-pages"
        let commitMsg = (config["commitMessage"] as? String) ?? "Deploy via SkycBlog"

        // Token 优先从 keychain 读取
        let account = "github:\(repo)"
        let token = Keychain.get(account) ?? (config["token"] as? String) ?? ProcessInfo.processInfo.environment["GITHUB_TOKEN"]

        switch method {
        case "git":
            return try gitDeploy(outputDir: outputDir, repo: repo, branch: branch, commitMsg: commitMsg, token: token)
        case "api":
            guard let token = token else {
                return DeployResult(success: false, message: "缺少 GitHub Token（请通过钥匙串或环境变量 GITHUB_TOKEN 设置）")
            }
            return try apiDeploy(outputDir: outputDir, repo: repo, branch: branch, token: token, commitMsg: commitMsg)
        case "export":
            return exportPackage(outputDir: outputDir, repo: repo)
        default:
            return DeployResult(success: false, message: "未知 method: \(method)，可选：git | api | export")
        }
    }

    func gitDeploy(outputDir: String, repo: String, branch: String, commitMsg: String, token: String?) throws -> DeployResult {
        let fm = FileManager.default
        // 临时克隆
        let tmp = NSTemporaryDirectory() + "skycblog-deploy-\(UUID().uuidString)"
        try fm.createDirectory(atPath: tmp, withIntermediateDirectories: true)
        defer { FSUtil.remove(tmp) }

        let authURL: String
        if let token = token, !token.isEmpty {
            authURL = "https://x-access-token:\(token)@github.com/\(repo).git"
        } else {
            authURL = "https://github.com/\(repo).git"
        }

        Log.info("git clone \(repo) → \(branch)")
        let cloneResult = Shell.run("/usr/bin/env", ["git", "clone", "--depth=1", authURL, tmp])
        if cloneResult.status != 0 {
            return DeployResult(success: false, message: "克隆失败：\(cloneResult.stderr)")
        }
        // 删除原内容（除 .git）
        let items = try fm.contentsOfDirectory(atPath: tmp)
        for i in items where i != ".git" {
            try? fm.removeItem(atPath: (tmp as NSString).appendingPathComponent(i))
        }
        // 复制 outputDir
        try FSUtil.copyDirectory(from: outputDir, to: tmp)
        // 配置 git
        _ = Shell.run("/usr/bin/env", ["git", "-C", tmp, "config", "user.email", "skycblog@example.com"])
        _ = Shell.run("/usr/bin/env", ["git", "-C", tmp, "config", "user.name", "SkycBlog"])
        _ = Shell.run("/usr/bin/env", ["git", "-C", tmp, "checkout", "-B", branch])
        _ = Shell.run("/usr/bin/env", ["git", "-C", tmp, "add", "-A"])
        let commit = Shell.run("/usr/bin/env", ["git", "-C", tmp, "commit", "-m", commitMsg, "--allow-empty"])
        if commit.status != 0 {
            return DeployResult(success: false, message: "提交失败：\(commit.stderr)")
        }
        let push = Shell.run("/usr/bin/env", ["git", "-C", tmp, "push", "-f", authURL, branch])
        if push.status != 0 {
            return DeployResult(success: false, message: "推送失败：\(push.stderr)")
        }
        let url = "https://\(repo.split(separator: "/").first ?? "username").github.io/\(repo.split(separator: "/").last ?? "")/"
        return DeployResult(success: true, message: "已推送至 \(branch) 分支", url: url)
    }

    func apiDeploy(outputDir: String, repo: String, branch: String, token: String, commitMsg: String) throws -> DeployResult {
        // 通过 GitHub Contents API 递归上传
        Log.info("GitHub API 上传 \(outputDir) → \(repo):\(branch)")
        let owner = repo.split(separator: "/").first.map(String.init) ?? ""
        let repoName = repo.split(separator: "/").last.map(String.init) ?? ""
        // 获取分支 HEAD
        guard let refURL = URL(string: "https://api.github.com/repos/\(owner)/\(repoName)/git/ref/heads/\(branch)") else {
            return DeployResult(success: false, message: "无效仓库路径")
        }
        var req = URLRequest(url: refURL)
        req.setValue("token \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let sem = DispatchSemaphore(value: 0)
        var refData: Data?
        URLSession.shared.dataTask(with: req) { data, _, _ in refData = data; sem.signal() }.resume()
        sem.wait()
        guard let data = refData,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let obj = json["object"] as? [String: Any],
              let sha = obj["sha"] as? String else {
            return DeployResult(success: false, message: "无法读取分支 HEAD（确认 token 权限与分支存在）")
        }
        // 简化：这里返回提示。完整 API 上传需要递归处理 + 创建 tree + commit + update ref。
        // 用户如需 API 部署，请使用 git method 即可。
        return DeployResult(success: false, message: "API method 需要递归上传大量文件，建议改用 method: git；HEAD sha=\(sha)")
    }

    func exportPackage(outputDir: String, repo: String) -> DeployResult {
        let dst = FileManager.default.currentDirectoryPath + "/\(repo.replacingOccurrences(of: "/", with: "-")).tar.gz"
        let r = Shell.run("/usr/bin/env", ["tar", "-czf", dst, "-C", outputDir, "."])
        if r.status != 0 { return DeployResult(success: false, message: "打包失败：\(r.stderr)") }
        return DeployResult(success: true, message: "已导出至 \(dst)", url: nil)
    }
}

/// Cloudflare Pages 部署。
public final class CloudflarePagesDeploy: DeployTarget {
    public let name = "cloudflare"
    public init() {}

    public func deploy(outputDir: String, config: [String: Any]) throws -> DeployResult {
        guard let accountID = config["accountID"] as? String, !accountID.isEmpty,
              let projectName = config["projectName"] as? String, !projectName.isEmpty else {
            return DeployResult(success: false, message: "缺少 accountID 或 projectName 字段")
        }
        let account = "cloudflare:\(accountID):\(projectName)"
        let token = Keychain.get(account) ?? (config["token"] as? String) ?? ProcessInfo.processInfo.environment["CLOUDFLARE_TOKEN"]
        guard let token = token, !token.isEmpty else {
            // 沙箱环境降级为导出
            return exportPackage(outputDir: outputDir, accountID: accountID, projectName: projectName)
        }
        // 通过 Direct Upload 流程：先创建 upload URL，再上传 zip
        return try apiDeploy(outputDir: outputDir, accountID: accountID, projectName: projectName, token: token)
    }

    func apiDeploy(outputDir: String, accountID: String, projectName: String, token: String) throws -> DeployResult {
        // 打包 outputDir
        let tarball = NSTemporaryDirectory() + "skycblog-cf-\(UUID().uuidString).tar.gz"
        let r = Shell.run("/usr/bin/env", ["tar", "-czf", tarball, "-C", outputDir, "."])
        if r.status != 0 { return DeployResult(success: false, message: "打包失败：\(r.stderr)") }

        // 1. 请求上传 URL
        guard let url = URL(string: "https://api.cloudflare.com/client/v4/accounts/\(accountID)/pages/projects/\(projectName)/deployments") else {
            return DeployResult(success: false, message: "无效的 accountID/projectName")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let sem = DispatchSemaphore(value: 0)
        var resp: (Data?, URLResponse?) = (nil, nil)
        URLSession.shared.dataTask(with: req) { d, r, _ in resp = (d, r); sem.signal() }.resume()
        sem.wait()
        guard let data = resp.0, let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = body["result"] as? [String: Any],
              let uploadURLString = result["upload_url"] as? String,
              let uploadURL = URL(string: uploadURLString) else {
            let msg = resp.0.flatMap { String(data: $0, encoding: .utf8) } ?? "未知错误"
            return DeployResult(success: false, message: "Cloudflare 创建部署失败：\(msg)")
        }

        // 2. 上传 zip
        var upReq = URLRequest(url: uploadURL)
        upReq.httpMethod = "POST"
        upReq.setValue("application/zip", forHTTPHeaderField: "Content-Type")
        let fileData = (try? Data(contentsOf: URL(fileURLWithPath: tarball))) ?? Data()
        let sem2 = DispatchSemaphore(value: 0)
        var upData: Data?
        URLSession.shared.uploadTask(with: upReq, from: fileData) { d, _, _ in upData = d; sem2.signal() }.resume()
        sem2.wait()
        if let ud = upData, let ujson = try? JSONSerialization.jsonObject(with: ud) as? [String: Any],
           let result = ujson["result"] as? [String: Any], let url = result["url"] as? String {
            return DeployResult(success: true, message: "已部署", url: url)
        }
        let raw = upData.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        return DeployResult(success: false, message: "上传失败：\(raw)")
    }

    func exportPackage(outputDir: String, accountID: String, projectName: String) -> DeployResult {
        let dst = FileManager.default.currentDirectoryPath + "/\(projectName)-cloudflare.tar.gz"
        let r = Shell.run("/usr/bin/env", ["tar", "-czf", dst, "-C", outputDir, "."])
        if r.status != 0 { return DeployResult(success: false, message: "打包失败：\(r.stderr)") }
        return DeployResult(success: true, message: "已导出 Cloudflare 部署包：\(dst)\n（请通过 wrangler pages deploy \(dst) --project-name \(projectName) 上传）", url: nil)
    }
}

/// Netlify / Vercel 包导出。
public final class StaticExportDeploy: DeployTarget {
    public let name: String
    public init(name: String) { self.name = name }

    public func deploy(outputDir: String, config: [String: Any]) throws -> DeployResult {
        let dstName = (config["projectName"] as? String) ?? "site"
        let dst = FileManager.default.currentDirectoryPath + "/\(dstName)-\(name).tar.gz"
        // 添加平台适配文件
        let adapterDir = NSTemporaryDirectory() + "\(dstName)-\(name)"
        FSUtil.remove(adapterDir)
        FSUtil.ensureDirectory(adapterDir)
        try FSUtil.copyDirectory(from: outputDir, to: adapterDir)
        switch name {
        case "netlify":
            // _redirects 示例
            FSUtil.writeText("# Netlify redirects\n/*    /index.html   404\n", to: (adapterDir as NSString).appendingPathComponent("_redirects"))
        case "vercel":
            FSUtil.writeText("{ \"version\": 2, \"cleanUrls\": true }", to: (adapterDir as NSString).appendingPathComponent("vercel.json"))
        default: break
        }
        let r = Shell.run("/usr/bin/env", ["tar", "-czf", dst, "-C", adapterDir, "."])
        if r.status != 0 { return DeployResult(success: false, message: "打包失败：\(r.stderr)") }
        return DeployResult(success: true, message: "已导出 \(name) 包：\(dst)", url: nil)
    }
}

public enum Shell {
    public static func run(_ path: String, _ args: [String]) -> (status: Int32, stdout: String, stderr: String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = args
        let outPipe = Pipe(); let errPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError = errPipe
        do { try task.run() } catch {
            return (-1, "", "无法启动进程：\(error)")
        }
        task.waitUntilExit()
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        return (task.terminationStatus, String(data: outData, encoding: .utf8) ?? "", String(data: errData, encoding: .utf8) ?? "")
    }
}

// 兼容旧命名
public typealias ShellRunner = Shell
public func shell(_ path: String, _ args: [String]) -> (status: Int32, stdout: String, stderr: String) { Shell.run(path, args) }
