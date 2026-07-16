import Foundation
import SkycBlogCore

/// `blog kc ...` 命令：钥匙串管理。
struct KeychainCommand {
    static func run(args: [String]) {
        let sub = args.first ?? "list"
        let rest = Array(args.dropFirst())
        switch sub {
        case "set":
            guard rest.count >= 2 else { Log.error("用法: blog kc set <account> <value>"); exit(1) }
            let account = rest[0]
            let value = rest[1]
            if Keychain.set(value, account: account) {
                Log.success("已保存账户：\(account)")
            } else {
                Log.error("保存失败")
            }
        case "get":
            guard let account = rest.first else { Log.error("用法: blog kc get <account>"); exit(1) }
            if let v = Keychain.get(account) { print(v) } else { Log.error("未找到") }
        case "list":
            let accounts = Keychain.allAccounts()
            if accounts.isEmpty { print("(空)") } else { accounts.forEach { print($0) } }
        case "del", "delete":
            guard let account = rest.first else { Log.error("用法: blog kc del <account>"); exit(1) }
            if Keychain.delete(account) { Log.success("已删除：\(account)") } else { Log.error("删除失败") }
        default:
            Log.error("未知子命令：\(sub)")
        }
    }
}
