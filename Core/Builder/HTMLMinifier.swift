import Foundation

/// 轻量 HTML 压缩器：去除多余空白与注释。
public enum HTMLMinifier {
    public static func minify(_ html: String) -> String {
        // 去除 HTML 注释
        var s = html
        s = replaceRegex(s, pattern: "<!--[\\s\\S]*?-->") { _ in "" }
        // 标签之间压缩空白
        s = replaceRegex(s, pattern: ">\\s+<") { _ in "><" }
        s = replaceRegex(s, pattern: "\\s{2,}") { _ in " " }
        return s
    }

    private static func replaceRegex(_ s: String, pattern: String, _ transform: ([String]) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return s }
        let ns = s as NSString
        let matches = regex.matches(in: s, range: NSRange(location: 0, length: ns.length))
        var out = ""
        var cur = 0
        for m in matches {
            let r = m.range
            if r.location > cur { out += ns.substring(with: NSRange(location: cur, length: r.location - cur)) }
            out += transform([])
            cur = r.location + r.length
        }
        if cur < ns.length { out += ns.substring(with: NSRange(location: cur, length: ns.length - cur)) }
        return out
    }
}
