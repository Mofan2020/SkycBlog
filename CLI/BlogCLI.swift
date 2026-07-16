import Foundation
import SkycBlogCore
import SkycBlogCore

/// CLI 主入口。
@main
struct BlogCLI {
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        let cmd = args.first ?? "help"
        let rest = Array(args.dropFirst())

        switch cmd {
        case "init":          InitCommand.run(args: rest)
        case "new":           NewCommand.run(args: rest)
        case "build":         BuildCommand.run(args: rest)
        case "serve":         ServeCommand.run(args: rest)
        case "deploy":        DeployCommand.run(args: rest)
        case "theme":         ThemeCommand.run(args: rest)
        case "keychain", "kc": KeychainCommand.run(args: rest)
        case "version", "-v", "--version":
            print("SkycBlog 1.0.0 (Swift \(swiftVersion()))")
        case "help", "-h", "--help":
            printHelp()
        default:
            Log.error("未知命令：\(cmd)")
            printHelp()
            exit(1)
        }
    }

    static func swiftVersion() -> String {
        #if swift(>=5.10)
        return "5.10+"
        #else
        return ""
        #endif
    }

    static func printHelp() {
        let help = """
        SkycBlog — 静态博客框架

        用法:
          blog init <name>             在当前目录新建一个博客项目
          blog new "<标题>"             创建一篇新文章
          blog build [--drafts]        构建站点
          blog serve [--port 8080]     启动本地预览服务器
          blog deploy [target]         部署（github / cloudflare / netlify / vercel）
          blog theme install <url>     从 URL（Git 或 ZIP）安装主题
          blog theme list              列出已安装主题
          blog kc set <account> <val>  保存密钥到钥匙串
          blog kc list                 列出钥匙串账户
          blog kc del <account>        删除钥匙串条目
          blog version                 输出版本
        """
        print(help)
    }
}
