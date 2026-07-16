import Foundation

/// 自实现的 CommonMark 子集 Markdown -> HTML 渲染器。
/// 支持：标题、段落、强调、行内代码、代码块（Fenced）、链接、图片、列表（含嵌套）、引用、表格、水平线、HTML 块、自动链接、任务列表、删除线、短代码占位。
public enum MarkdownRenderer {
    public static func render(_ text: String) -> String {
        var lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var out = ""
        var i = 0
        while i < lines.count {
            let line = lines[i]
            // 围栏代码块
            if line.hasPrefix("```") {
                var lang = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                if lang.isEmpty { lang = "text" }
                var code = ""
                i += 1
                while i < lines.count && !lines[i].hasPrefix("```") {
                    code += lines[i] + "\n"
                    i += 1
                }
                if i < lines.count { i += 1 } // 跳过结束 ```
                out += "<pre><code class=\"language-\(lang.htmlEscaped)\">\(code.htmlEscaped)</code></pre>\n"
                continue
            }
            // 缩进代码块（4 空格或 tab）
            if line.hasPrefix("    ") || line.hasPrefix("\t") {
                var code = ""
                while i < lines.count && (lines[i].hasPrefix("    ") || lines[i].hasPrefix("\t") || lines[i].isEmpty) {
                    code += lines[i] + "\n"
                    i += 1
                }
                let trimmed = code.replacingOccurrences(of: "^( {4}|\t)", with: "", options: .regularExpression)
                out += "<pre><code>\(trimmed.htmlEscaped)</code></pre>\n"
                continue
            }
            // 水平线
            if line == "---" || line == "***" || line == "___" {
                out += "<hr/>\n"
                i += 1
                continue
            }
            // 标题
            if let hashMatch = line.range(of: #"^(#{1,6})\s+(.*)$"#, options: .regularExpression) {
                let groups = matches(in: line, pattern: #"^(#{1,6})\s+(.*)$"#)
                if groups.count >= 3 {
                    let level = groups[1].count
                    let title = renderInline(groups[2])
                    out += "<h\(level)>\(title)</h\(level)>\n"
                    i += 1
                    continue
                }
                _ = hashMatch
            }
            // 引用
            if line.hasPrefix("> ") || line == ">" {
                var quote = ""
                while i < lines.count && (lines[i].hasPrefix("> ") || lines[i] == ">" || lines[i].isEmpty) {
                    if lines[i].isEmpty { break }
                    var t = lines[i]
                    if t.hasPrefix("> ") { t = String(t.dropFirst(2)) }
                    else if t == ">" { t = "" }
                    quote += t + "\n"
                    i += 1
                }
                out += "<blockquote>\n" + render(quote) + "</blockquote>\n"
                continue
            }
            // 表格
            if line.contains("|") && i + 1 < lines.count && isTableSeparator(lines[i + 1]) {
                let header = parseTableRow(line)
                i += 2
                var body = ""
                while i < lines.count && lines[i].contains("|") && !lines[i].isEmpty {
                    body += "<tr>"
                    for cell in parseTableRow(lines[i]) {
                        body += "<td>\(renderInline(cell))</td>"
                    }
                    body += "</tr>"
                    i += 1
                }
                var thead = "<tr>"
                for h in header { thead += "<th>\(renderInline(h))</th>" }
                thead += "</tr>"
                out += "<table><thead>\(thead)</thead><tbody>\(body)</tbody></table>\n"
                continue
            }
            // 列表
            if isUnorderedListItem(line) || isOrderedListItem(line) || isTaskListItem(line) {
                let (html, next) = renderList(lines: lines, start: i)
                out += html
                i = next
                continue
            }
            // 空行
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                i += 1
                continue
            }
            // 段落
            var para = ""
            while i < lines.count &&
                  !lines[i].trimmingCharacters(in: .whitespaces).isEmpty &&
                  !lines[i].hasPrefix("```") &&
                  !lines[i].hasPrefix("#") &&
                  !isUnorderedListItem(lines[i]) &&
                  !isOrderedListItem(lines[i]) &&
                  !isTaskListItem(lines[i]) &&
                  !lines[i].hasPrefix("> ") &&
                  !lines[i].hasPrefix("    ") {
                para += lines[i] + "\n"
                i += 1
            }
            if !para.isEmpty {
                out += "<p>\(renderInline(para.trimmingCharacters(in: .whitespacesAndNewlines)))</p>\n"
            }
        }
        return out
    }

    // MARK: - 内联渲染

    public static func renderInline(_ s: String) -> String {
        var t = expandShortcodes(s)
        // 图片 ![alt](url) —— 必须先于链接
        t = replaceRegex(t, pattern: #"!\[([^\]]*)\]\(([^\s)]+)(?:\s+\"([^\"]*)\")?\)"#) { m in
            let alt = m[1].htmlEscaped
            let url = m[2].htmlEscaped
            let title = m.count > 3 ? " title=\"\(m[3].htmlEscaped)\"" : ""
            return "<img src=\"\(url)\" alt=\"\(alt)\"\(title) loading=\"lazy\"/>"
        }
        // 链接 [text](url)
        t = replaceRegex(t, pattern: #"\[([^\]]+)\]\(([^\s)]+)(?:\s+\"([^\"]*)\")?\)"#) { m in
            return "<a href=\"\(m[2].htmlEscaped)\">\(renderInline(m[1]))</a>"
        }
        // 行内代码：先抽出占位，保护内部不被粗体/斜体破坏
        var codeStash: [String] = []
        t = replaceRegex(t, pattern: "`([^`]+)`") { m in
            let token = "\u{0001}\(codeStash.count)\u{0002}"
            codeStash.append("<code>\(m[1].htmlEscaped)</code>")
            return token
        }
        // 删除线 ~~text~~
        t = replaceRegex(t, pattern: "~~(.+?)~~") { m in "<del>\(m[1])</del>" }
        // 粗体 / 斜体 —— 单次扫描避免 O(n²)
        t = applyEmphasis(t)
        // 恢复行内代码占位
        if !codeStash.isEmpty {
            for (i, html) in codeStash.enumerated() {
                t = t.replacingOccurrences(of: "\u{0001}\(i)\u{0002}", with: html)
            }
        }
        // 硬换行
        t = t.replacingOccurrences(of: "  \n", with: "<br/>\n")
        // 自动链接
        t = replaceRegex(t, pattern: #"<(https?://[^>]+)>"#) { m in "<a href=\"\(m[1])\">\(m[1])</a>" }
        return t
    }

    /// 单次扫描处理 *** / ** / __ / * / _,避免对全字符串做多次 `replacingOccurrences` 引发 O(n²)。
    static func applyEmphasis(_ s: String) -> String {
        let chars = Array(s)
        var out = ""
        out.reserveCapacity(s.count)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            // *** 粗斜体 ***
            if c == "*" && i + 2 < chars.count && chars[i + 1] == "*" && chars[i + 2] == "*" {
                if let end = findClosing(of: "***", in: chars, from: i + 3) {
                    let inner = String(chars[i + 3..<end])
                    out += "<b><i>\(inner)</i></b>"
                    i = end + 3
                    continue
                }
            }
            // ** 粗体 **
            if c == "*" && i + 1 < chars.count && chars[i + 1] == "*" {
                if let end = findClosing(of: "**", in: chars, from: i + 2) {
                    let inner = String(chars[i + 2..<end])
                    out += "<b>\(inner)</b>"
                    i = end + 2
                    continue
                }
            }
            // __ 粗体 __
            if c == "_" && i + 1 < chars.count && chars[i + 1] == "_" {
                if let end = findClosing(of: "__", in: chars, from: i + 2) {
                    let inner = String(chars[i + 2..<end])
                    out += "<b>\(inner)</b>"
                    i = end + 2
                    continue
                }
            }
            // * 斜体 *
            if c == "*" {
                if let end = findClosing(of: "*", in: chars, from: i + 1) {
                    let inner = String(chars[i + 1..<end])
                    out += "<i>\(inner)</i>"
                    i = end + 1
                    continue
                }
            }
            // _ 斜体 _
            if c == "_" {
                if let end = findClosing(of: "_", in: chars, from: i + 1) {
                    let inner = String(chars[i + 1..<end])
                    out += "<i>\(inner)</i>"
                    i = end + 1
                    continue
                }
            }
            out.append(c)
            i += 1
        }
        return out
    }

    /// 寻找下一个完整的 `token`,从 from 起;若不存在则返回 nil。
    static func findClosing(of token: String, in chars: [Character], from start: Int) -> Int? {
        let n = token.count
        var i = start
        while i + n <= chars.count {
            var match = true
            for k in 0..<n {
                if chars[i + k] != token[token.index(token.startIndex, offsetBy: k)] {
                    match = false
                    break
                }
            }
            if match { return i }
            i += 1
        }
        return nil
    }

    static func expandShortcodes(_ s: String) -> String {
        // 简易短代码：{% gallery albumName %}、{% youtube id %} 等
        return replaceRegex(s, pattern: #"\{\%\s*([a-zA-Z0-9_-]+)([^%]*)\s*\%\}"#) { m in
            let name = m[1]
            let rest = m[2].trimmingCharacters(in: .whitespaces)
            switch name {
            case "gallery":
                return "<div class=\"shortcode-gallery\" data-album=\"\(rest.htmlEscaped)\"></div>"
            case "youtube":
                let id = rest
                return "<div class=\"shortcode-youtube\"><iframe src=\"https://www.youtube.com/embed/\(id.htmlEscaped)\" frameborder=\"0\" allowfullscreen></iframe></div>"
            case "bilibili":
                return "<div class=\"shortcode-bilibili\"><iframe src=\"//player.bilibili.com/player.html?bvid=\(rest.htmlEscaped)\" frameborder=\"0\"></iframe></div>"
            case "note":
                return "<blockquote class=\"shortcode-note\">\(renderInline(rest))</blockquote>"
            case "highlight":
                return "<mark>\(renderInline(rest))</mark>"
            default:
                return "<span class=\"shortcode shortcode-\(name.htmlEscaped)\">\(renderInline(rest))</span>"
            }
        }
    }

    // MARK: - 列表

    static func isUnorderedListItem(_ s: String) -> Bool {
        return s.range(of: #"^[\-\*\+]\s+"#, options: .regularExpression) != nil
    }
    static func isOrderedListItem(_ s: String) -> Bool {
        return s.range(of: #"^\d+\.\s+"#, options: .regularExpression) != nil
    }
    static func isTaskListItem(_ s: String) -> Bool {
        return s.range(of: #"^[\-\*\+]\s+\[[ xX]\]\s+"#, options: .regularExpression) != nil
    }

    static func renderList(lines: [String], start: Int) -> (String, Int) {
        var i = start
        var out = ""
        var ordered = lines[i].range(of: #"^\d+\.\s+"#, options: .regularExpression) != nil
        out += ordered ? "<ol>\n" : "<ul>\n"
        while i < lines.count {
            let line = lines[i]
            if line.trimmingCharacters(in: .whitespaces).isEmpty { break }
            let isUl = isUnorderedListItem(line)
            let isOl = isOrderedListItem(line)
            let isTask = isTaskListItem(line)
            if !isUl && !isOl && !isTask { break }
            if isOl != ordered { break }
            // 缩进延续
            var content = line
            if let r = line.range(of: #"^([\-\*\+]\s+|\d+\.\s+|\-\s+\[[ xX]\]\s+)"#, options: .regularExpression) {
                content = String(line[r.upperBound...])
            }
            // 任务列表
            if isTask {
                if let r = content.range(of: #"^\[([ xX])\]\s+"#, options: .regularExpression) {
                    let token = String(content[r])
                    let checked = token.count >= 3 && token[token.index(token.startIndex, offsetBy: 1)] != " "
                    let rest = String(content[r.upperBound...])
                    out += "<li class=\"task-item\"><input type=\"checkbox\" disabled\(checked ? " checked" : "")/> \(renderInline(rest))</li>\n"
                }
            } else {
                out += "<li>\(renderInline(content))</li>\n"
            }
            i += 1
        }
        out += ordered ? "</ol>\n" : "</ul>\n"
        return (out, i)
    }

    // MARK: - 表格

    static func isTableSeparator(_ s: String) -> Bool {
        return s.range(of: #"^\|?\s*:?-+:?\s*(\|\s*:?-+:?\s*)+\|?\s*$"#, options: .regularExpression) != nil
    }

    static func parseTableRow(_ s: String) -> [String] {
        var row = s
        if row.hasPrefix("|") { row = String(row.dropFirst()) }
        if row.hasSuffix("|") { row = String(row.dropLast()) }
        return row.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    // MARK: - 摘要

    public static func excerpt(from text: String, length: Int) -> String {
        // 去掉代码块
        var s = text
        s = replaceRegex(s, pattern: "```[\\s\\S]*?```") { _ in "" }
        // 去掉图片
        s = replaceRegex(s, pattern: #"!\[[^\]]*\]\([^)]+\)"#) { _ in "" }
        // 去掉链接语法但保留文本
        s = replaceRegex(s, pattern: #"\[([^\]]+)\]\([^)]+\)"#) { m in m[1] }
        // 去掉标题符号（按行）
        s = replaceRegex(s, pattern: #"^#{1,6}\s+"#, options: [.anchorsMatchLines]) { _ in "" }
        // 去除引用
        s = replaceRegex(s, pattern: #"^>\s*"#, options: [.anchorsMatchLines]) { _ in "" }
        // 去除列表符号
        s = replaceRegex(s, pattern: #"^[\-\*\+]\s+"#, options: [.anchorsMatchLines]) { _ in "" }
        // 去除有序列表符号
        s = replaceRegex(s, pattern: #"^\d+\.\s+"#, options: [.anchorsMatchLines]) { _ in "" }
        // 去除行内代码标记
        s = replaceRegex(s, pattern: "`([^`]+)`") { m in m[1] }
        // 去除粗体斜体标记
        s = s.replacingOccurrences(of: "**", with: "")
        s = s.replacingOccurrences(of: "__", with: "")
        s = s.replacingOccurrences(of: "***", with: "")
        s = s.replacingOccurrences(of: "*", with: "")
        s = s.replacingOccurrences(of: "_", with: "")
        s = s.replacingOccurrences(of: "~~", with: "")
        // 合并空白
        s = s.replacingOccurrences(of: "\n", with: " ")
        while s.contains("  ") {
            s = s.replacingOccurrences(of: "  ", with: " ")
        }
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return "" }
        if s.count <= length { return s }
        // 在最近的完整词处截断
        let truncated = String(s.prefix(length))
        if let lastSpace = truncated.lastIndex(of: " ") {
            return String(truncated[..<lastSpace]) + "…"
        }
        return truncated + "…"
    }

    // MARK: - 正则辅助

    static func replaceRegex(_ s: String, pattern: String, options: NSRegularExpression.Options = []) -> String {
        return replaceRegex(s, pattern: pattern, options: options) { matches in
            matches.joined(separator: "")
        }
    }

    static func replaceRegex(_ s: String, pattern: String, options: NSRegularExpression.Options = [], _ transform: ([String]) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return s }
        let nsString = s as NSString
        let matches = regex.matches(in: s, options: [], range: NSRange(location: 0, length: nsString.length))
        var result = ""
        var cursor = 0
        for m in matches {
            let start = m.range.location
            let len = m.range.length
            if start > cursor {
                result += nsString.substring(with: NSRange(location: cursor, length: start - cursor))
            }
            var groups: [String] = []
            for g in 0..<m.numberOfRanges {
                let r = m.range(at: g)
                if r.location == NSNotFound {
                    groups.append("")
                } else {
                    groups.append(nsString.substring(with: r))
                }
            }
            result += transform(groups)
            cursor = start + len
        }
        if cursor < nsString.length {
            result += nsString.substring(with: NSRange(location: cursor, length: nsString.length - cursor))
        }
        return result
    }

    static func matches(in s: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = s as NSString
        if let m = regex.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) {
            var out: [String] = []
            for g in 0..<m.numberOfRanges {
                let r = m.range(at: g)
                if r.location == NSNotFound { out.append("") } else { out.append(ns.substring(with: r)) }
            }
            return out
        }
        return []
    }
}
