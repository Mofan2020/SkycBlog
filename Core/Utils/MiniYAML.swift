import Foundation

/// 极简 YAML 解析器（满足 SkycBlog 配置需求）。
/// - 键值对（字符串/数字/布尔/null）
/// - 嵌套映射（通过缩进）
/// - 列表（- item）
/// - 双引号 / 单引号字符串
/// - 注释（#，非引号内）
public enum MiniYAML {
    public static func load(_ text: String) -> [String: Any] {
        // 预处理：剥离注释；过滤完全为空的行（保留前导缩进）
        let lines = text.components(separatedBy: "\n")
            .map(stripComment)
            .filter { $0.trimmingCharacters(in: .whitespaces).isEmpty == false }
        let result = parseMapping(lines: lines, from: 0, indent: 0)
        return result.value
    }

    private struct Parsed { let value: [String: Any]; let nextIndex: Int }

    /// 解析一个 mapping 块，从 lines[index] 开始，缩进为 indent。
    private static func parseMapping(lines: [String], from index: Int, indent: Int) -> Parsed {
        var dict: [String: Any] = [:]
        var i = index
        while i < lines.count {
            let line = lines[i]
            let ind = leadingSpaces(line)
            // 缩进小于当前块则退出
            if ind < indent { break }
            // 缩进大于当前块则跳过（异常）
            if ind > indent { i += 1; continue }
            let content = String(line.dropFirst(ind))
            // 列表项不能直接是 mapping 键
            if content.hasPrefix("- ") {
                // 列表作为 mapping 的值时由 parseScalar 之前处理；此处视为结构异常
                break
            }
            // 必须是 key: value 形式
            guard let colon = content.firstIndex(of: ":") else {
                i += 1
                continue
            }
            let key = String(content[..<colon]).trimmingCharacters(in: .whitespaces)
            let valuePart = String(content[content.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            if valuePart.isEmpty {
                // 嵌套 mapping 或 list
                if i + 1 < lines.count {
                    let next = lines[i + 1]
                    let nextInd = leadingSpaces(next)
                    if nextInd > indent {
                        let nextContent = String(next.dropFirst(nextInd))
                        if nextContent.hasPrefix("- ") {
                            // 列表
                            let listResult = parseList(lines: lines, from: i + 1, indent: nextInd)
                            dict[key] = listResult.value
                            i = listResult.nextIndex
                            continue
                        } else {
                            // mapping
                            let sub = parseMapping(lines: lines, from: i + 1, indent: nextInd)
                            dict[key] = sub.value
                            i = sub.nextIndex
                            continue
                        }
                    }
                }
                dict[key] = ""
            } else {
                dict[key] = parseScalar(valuePart)
            }
            i += 1
        }
        return Parsed(value: dict, nextIndex: i)
    }

    private struct ParsedList { let value: [Any]; let nextIndex: Int }

    private static func parseList(lines: [String], from index: Int, indent: Int) -> ParsedList {
        var list: [Any] = []
        var i = index
        while i < lines.count {
            let line = lines[i]
            let ind = leadingSpaces(line)
            if ind < indent { break }
            if ind > indent { i += 1; continue }
            let content = String(line.dropFirst(ind))
            if !content.hasPrefix("- ") { break }
            let rest = String(content.dropFirst(2))
            if rest.isEmpty {
                // 列表项是一个嵌套结构
                if i + 1 < lines.count {
                    let next = lines[i + 1]
                    let nextInd = leadingSpaces(next)
                    if nextInd > indent {
                        let nextContent = String(next.dropFirst(nextInd))
                        if nextContent.hasPrefix("- ") {
                            let sub = parseList(lines: lines, from: i + 1, indent: nextInd)
                            list.append(sub.value)
                            i = sub.nextIndex
                            continue
                        } else {
                            let sub = parseMapping(lines: lines, from: i + 1, indent: nextInd)
                            list.append(sub.value)
                            i = sub.nextIndex
                            continue
                        }
                    }
                }
                list.append("")
            } else if rest.hasPrefix("{") && rest.hasSuffix("}") && rest.count >= 2 {
                // Flow-style mapping: - { key: val, key: val }
                list.append(parseFlowMapping(rest))
                i += 1
            } else if rest.contains(":") && !rest.hasPrefix("\"") && !rest.hasPrefix("'") {
                // 列表项是 dict（首行 + 后续行）
                let (inlineKey, inlineValue) = splitKV(rest)
                var lines2: [String] = []
                lines2.append(rest)
                if !inlineValue.isEmpty {
                    // 形如 "- key: value"，行内已有值
                }
                i += 1
                while i < lines.count {
                    let l2 = lines[i]
                    let ind2 = leadingSpaces(l2)
                    if ind2 <= indent { break }
                    // 缩进是 indent + 2 视为属于该项
                    lines2.append(String(l2.dropFirst(indent + 2)))
                    i += 1
                }
                let sub = parseMapping(lines: lines2, from: 0, indent: 0)
                list.append(sub.value)
            } else {
                list.append(parseScalar(rest))
                i += 1
            }
        }
        return ParsedList(value: list, nextIndex: i)
    }

    private static func splitKV(_ s: String) -> (String, String) {
        guard let c = s.firstIndex(of: ":") else { return (s, "") }
        let k = String(s[..<c]).trimmingCharacters(in: .whitespaces)
        let v = String(s[s.index(after: c)...]).trimmingCharacters(in: .whitespaces)
        return (k, v)
    }

    private static func leadingSpaces(_ s: String) -> Int {
        var c = 0
        for ch in s {
            if ch == " " { c += 1 } else { break }
        }
        return c
    }

    private static func stripComment(_ s: String) -> String {
        var inStr: Character? = nil
        var out = ""
        for ch in s {
            if let q = inStr {
                out.append(ch)
                if ch == q { inStr = nil }
                continue
            }
            if ch == "\"" || ch == "'" {
                inStr = ch
                out.append(ch)
                continue
            }
            if ch == "#" { break }
            out.append(ch)
        }
        // 注意：保留前导空白以维持缩进结构；只去掉尾部空白
        var endIdx = out.endIndex
        while endIdx > out.startIndex {
            let prev = out.index(before: endIdx)
            if out[prev] == " " || out[prev] == "\t" {
                endIdx = prev
            } else {
                break
            }
        }
        return String(out[..<endIdx])
    }

    /// 解析 flow-style mapping：{ key: val, key: val }
    /// 支持字符串内冒号、逗号；支持嵌套花括号/方括号。
    private static func parseFlowMapping(_ s: String) -> [String: Any] {
        var t = s.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("{") { t = String(t.dropFirst()) }
        if t.hasSuffix("}") { t = String(t.dropLast()) }
        var dict: [String: Any] = [:]
        // 顶层拆分（按逗号，忽略字符串内/嵌套括号内）
        var depth = 0
        var inStr: Character? = nil
        var current = ""
        var parts: [String] = []
        for ch in t {
            if let q = inStr {
                current.append(ch)
                if ch == q { inStr = nil }
                continue
            }
            if ch == "\"" || ch == "'" { inStr = ch; current.append(ch); continue }
            if ch == "[" || ch == "{" { depth += 1; current.append(ch); continue }
            if ch == "]" || ch == "}" { depth -= 1; current.append(ch); continue }
            if ch == "," && depth == 0 { parts.append(current); current = ""; continue }
            current.append(ch)
        }
        if !current.trimmingCharacters(in: .whitespaces).isEmpty {
            parts.append(current)
        }
        for p in parts {
            let trimmed = p.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            // 拆 key: value（仅顶层第一个冒号）
            var d = 0
            var inS: Character? = nil
            var colonIdx: String.Index? = nil
            for idx in trimmed.indices {
                let ch = trimmed[idx]
                if let q = inS {
                    if ch == q { inS = nil }
                    continue
                }
                if ch == "\"" || ch == "'" { inS = ch; continue }
                if ch == "[" || ch == "{" { d += 1; continue }
                if ch == "]" || ch == "}" { d -= 1; continue }
                if ch == ":" && d == 0 { colonIdx = idx; break }
            }
            guard let ci = colonIdx else { continue }
            let key = String(trimmed[..<ci]).trimmingCharacters(in: .whitespaces)
            let valStr = String(trimmed[trimmed.index(after: ci)...]).trimmingCharacters(in: .whitespaces)
            dict[key] = parseScalar(valStr)
        }
        return dict
    }

    private static func parseScalar(_ s: String) -> Any {
        var t = s.trimmingCharacters(in: .whitespaces)
        // Flow-style mapping: { key: val, key: val }
        if t.hasPrefix("{") && t.hasSuffix("}") && t.count >= 2 {
            return parseFlowMapping(t)
        }
        // Inline array: [a, b, c]
        if t.hasPrefix("[") && t.hasSuffix("]") && t.count >= 2 {
            let inner = String(t.dropFirst().dropLast())
            // Simple split on top-level commas
            var parts: [String] = []
            var depth = 0
            var inStr: Character? = nil
            var current = ""
            for ch in inner {
                if let q = inStr {
                    current.append(ch)
                    if ch == q { inStr = nil }
                    continue
                }
                if ch == "\"" || ch == "'" {
                    inStr = ch
                    current.append(ch)
                    continue
                }
                if ch == "[" || ch == "{" { depth += 1 }
                if ch == "]" || ch == "}" { depth -= 1 }
                if ch == "," && depth == 0 {
                    parts.append(current)
                    current = ""
                } else {
                    current.append(ch)
                }
            }
            if !current.isEmpty { parts.append(current) }
            return parts.map { parseScalar($0.trimmingCharacters(in: .whitespaces)) }
        }
        if t.count >= 2 {
            if (t.hasPrefix("\"") && t.hasSuffix("\"")) || (t.hasPrefix("'") && t.hasSuffix("'")) {
                return String(t.dropFirst().dropLast())
            }
        }
        if t == "true" { return true }
        if t == "false" { return false }
        if t == "null" || t == "~" { return NSNull() }
        if let i = Int(t) { return i }
        if let d = Double(t) { return d }
        return t
    }

    // MARK: - Dump (用于写回 _config.yml / theme.yaml)
    /// 将 [String: Any] 序列化为 YAML 文本 (UTF-8).
    public static func dump(_ root: [String: Any]) -> String {
        var lines: [String] = []
        emitMapping(root, indent: 0, lines: &lines)
        // 末尾保留一个换行 (Hexo/SkycBlog 风格)
        if lines.isEmpty { return "" }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func emitMapping(_ dict: [String: Any], indent: Int, lines: inout [String]) {
        let pad = String(repeating: " ", count: indent)
        for (k, v) in dict.sorted(by: { $0.key < $1.key }) {
            let safeKey = quoteIfNeeded(k)
            if let sub = v as? [String: Any], !sub.isEmpty {
                lines.append("\(pad)\(safeKey):")
                emitMapping(sub, indent: indent + 2, lines: &lines)
            } else if let arr = v as? [Any] {
                lines.append("\(pad)\(safeKey):")
                emitList(arr, indent: indent + 2, lines: &lines)
            } else {
                lines.append("\(pad)\(safeKey): \(scalarString(v))")
            }
        }
    }

    private static func emitList(_ arr: [Any], indent: Int, lines: inout [String]) {
        let pad = String(repeating: " ", count: indent)
        for item in arr {
            if let sub = item as? [String: Any], !sub.isEmpty {
                // YAML 中, list of mapping 的标准写法: 首行 "- key: val", 后续行缩进
                if let first = sub.sorted(by: { $0.key < $1.key }).first {
                    let firstSafe = quoteIfNeeded(first.key)
                    var rest = sub
                    rest.removeValue(forKey: first.key)
                    if rest.isEmpty {
                        lines.append("\(pad)- \(firstSafe): \(scalarString(first.value))")
                    } else {
                        lines.append("\(pad)- \(firstSafe): \(scalarString(first.value))")
                        emitMapping(rest, indent: indent + 4, lines: &lines)
                    }
                } else {
                    lines.append("\(pad)- {}")
                }
            } else if let subArr = item as? [Any] {
                lines.append("\(pad)-")
                emitList(subArr, indent: indent + 2, lines: &lines)
            } else {
                lines.append("\(pad)- \(scalarString(item))")
            }
        }
    }

    private static func scalarString(_ v: Any) -> String {
        if v is NSNull { return "null" }
        if let b = v as? Bool { return b ? "true" : "false" }
        if let i = v as? Int { return String(i) }
        if let d = v as? Double { return String(d) }
        if let s = v as? String {
            // 含特殊字符 -> 强制加双引号
            let needQuote = s.isEmpty ||
                s.contains(":") || s.contains("#") || s.contains("\n") ||
                s.first == " " || s.last == " " || s.first == "\"" || s.first == "'" ||
                ["true", "false", "null", "yes", "no"].contains(s.lowercased()) ||
                Int(s) != nil || Double(s) != nil
            if needQuote {
                let escaped = s.replacingOccurrences(of: "\\", with: "\\\\")
                                .replacingOccurrences(of: "\"", with: "\\\"")
                return "\"\(escaped)\""
            }
            return s
        }
        if let arr = v as? [Any] {
            // inline array
            let inner = arr.map { scalarString($0) }.joined(separator: ", ")
            return "[\(inner)]"
        }
        return String(describing: v)
    }

    private static func quoteIfNeeded(_ s: String) -> String {
        if s.isEmpty { return "\"\"" }
        if s.range(of: "^[A-Za-z_][A-Za-z0-9_\\-]*$", options: .regularExpression) != nil {
            return s
        }
        let escaped = s.replacingOccurrences(of: "\\", with: "\\\\")
                        .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
