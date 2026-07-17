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

    // MARK: - 保留注释的注解式解析与序列化 (用于主题配置编辑器)

    /// 解析 YAML, 保留 key 顺序、leading/inline 注释. 返回 CmpMapping.
    public static func loadAnnotated(_ text: String) -> CmpMapping {
        let metas = _buildAnnotatedMetas(text)
        var m = CmpMapping()
        var i = 0
        _annotatedWalkMapping(metas: metas, i: &i, indent: 0, into: &m)
        return m
    }

    /// 序列化 CmpMapping -> YAML 文本 (含注释, 按 entries 顺序)
    public static func dump(_ mapping: CmpMapping) -> String {
        var lines: [String] = []
        emitAnnotatedMapping(mapping, indent: 0, lines: &lines)
        return lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
    }

    private static func emitAnnotatedMapping(_ m: CmpMapping, indent: Int, lines: inout [String]) {
        let pad = String(repeating: " ", count: indent)
        for lc in m.leadingComments {
            lines.append(pad + lc)
        }
        for e in m.entries {
            for lc in e.leadingComments {
                lines.append(pad + lc)
            }
            emitAnnotatedEntry(e, indent: indent, lines: &lines)
        }
    }

    private static func emitAnnotatedEntry(_ e: CmpEntry, indent: Int, lines: inout [String]) {
        let pad = String(repeating: " ", count: indent)
        let safeKey = quoteIfNeeded(e.key)
        switch e.value {
        case .scalar(let s):
            var line = "\(pad)\(safeKey): \(scalarString(s))"
            if let ic = e.inlineComment { line += "  # \(ic)" }
            lines.append(line)
        case .mapping(let m):
            lines.append("\(pad)\(safeKey):")
            emitAnnotatedMapping(m, indent: indent + 2, lines: &lines)
        case .list(let items):
            emitAnnotatedList(items, key: e.key, indent: indent, lines: &lines, inlineComment: e.inlineComment)
        }
    }

    private static func emitAnnotatedList(_ items: [CmpListItem], key: String, indent: Int, lines: inout [String], inlineComment: String?) {
        let pad = String(repeating: " ", count: indent)
        let safeKey = quoteIfNeeded(key)
        if items.isEmpty {
            var line = "\(pad)\(safeKey): []"
            if let ic = inlineComment { line += "  # \(ic)" }
            lines.append(line)
            return
        }
        lines.append("\(pad)\(safeKey):")
        for item in items {
            emitListItemLine(item, indent: indent + 2, lines: &lines)
        }
        if let ic = inlineComment {
            lines.append(pad + "# " + ic)
        }
    }

    private static func emitListItemLine(_ item: CmpListItem, indent: Int, lines: inout [String]) {
        let pad = String(repeating: " ", count: indent)
        for lc in item.leadingComments {
            lines.append(pad + lc)
        }
        switch item.value {
        case .scalar(let s):
            var line = "\(pad)- \(scalarString(s))"
            if let ic = item.inlineComment { line += "  # \(ic)" }
            lines.append(line)
        case .mapping(let m):
            if let first = m.entries.first {
                let safeKey = quoteIfNeeded(first.key)
                let firstVal = annotatedScalarString(first.value)
                if m.entries.count == 1 {
                    var line = "\(pad)- \(safeKey): \(firstVal)"
                    if let ic = first.inlineComment { line += "  # \(ic)" }
                    lines.append(line)
                } else {
                    lines.append("\(pad)- \(safeKey): \(firstVal)")
                    for e in m.entries.dropFirst() {
                        for lc in e.leadingComments { lines.append(pad + "  " + lc) }
                        emitAnnotatedEntry(e, indent: indent + 2, lines: &lines)
                    }
                }
            } else {
                lines.append("\(pad)- {}")
            }
        case .list(let inner):
            lines.append("\(pad)-")
            for it in inner { emitListItemLine(it, indent: indent + 2, lines: &lines) }
        }
    }

    private static func annotatedScalarString(_ v: CmpValue) -> String {
        switch v {
        case .scalar(let s): return scalarString(s)
        case .mapping(let m): return "{ \(inlineMapping(m)) }"
        case .list(let items): return "[\(items.map { inlineListItem($0) }.joined(separator: ", "))]"
        }
    }
    private static func inlineMapping(_ m: CmpMapping) -> String {
        m.entries.map { "\(quoteIfNeeded($0.key)): \(annotatedScalarString($0.value))" }.joined(separator: ", ")
    }
    private static func inlineListItem(_ item: CmpListItem) -> String {
        annotatedScalarString(item.value)
    }
}

// MARK: - line meta + walker (保留顺序 + 注释)
struct MiniYAMLAnnotatedLine {
    let raw: String          // 去掉注释尾后的行 (含缩进)
    let indent: Int
    let leading: [String]    // 上一段"空/注释"行中属于本行的注释
    let inline: String?
    let isPure: Bool         // 整行是空行或纯注释
}

extension MiniYAML {
    fileprivate static func _buildAnnotatedMetas(_ text: String) -> [MiniYAMLAnnotatedLine] {
        let rawLines = text.components(separatedBy: "\n")
        var metas: [MiniYAMLAnnotatedLine] = []
        var pendingComments: [String] = []
        for line in rawLines {
            let leading = _countLeadingSpaces(line)
            let (withoutComment, inline) = _extractInlineComment(line)
            let trimmed = withoutComment.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                metas.append(MiniYAMLAnnotatedLine(raw: "", indent: leading, leading: [], inline: nil, isPure: true))
                continue
            }
            if trimmed.hasPrefix("#") {
                // 纯注释行: 整行保留 (trim 掉前导缩进, 形如 "# xxx")
                let commentText = line.trimmingCharacters(in: .init(charactersIn: " \t"))
                pendingComments.append(commentText)
                metas.append(MiniYAMLAnnotatedLine(raw: commentText, indent: leading, leading: [], inline: nil, isPure: true))
                continue
            }
            metas.append(MiniYAMLAnnotatedLine(raw: withoutComment, indent: leading, leading: pendingComments, inline: inline, isPure: false))
            pendingComments = []
        }
        return metas
    }

    fileprivate static func _countLeadingSpaces(_ s: String) -> Int {
        var c = 0
        for ch in s {
            if ch == " " { c += 1 } else { break }
        }
        return c
    }

    fileprivate static func _extractInlineComment(_ s: String) -> (String, String?) {
        var inStr: Character? = nil
        var bodyEnd = s.endIndex
        for i in s.indices {
            let ch = s[i]
            if let q = inStr {
                if ch == q { inStr = nil }
                continue
            }
            if ch == "\"" || ch == "'" {
                inStr = ch
                continue
            }
            if ch == "#" {
                bodyEnd = i
                break
            }
        }
        let body = String(s[..<bodyEnd])
        var start = bodyEnd
        if start < s.endIndex, s[start] == "#" { start = s.index(after: start) }
        while start < s.endIndex, s[start] == " " || s[start] == "\t" { start = s.index(after: start) }
        let comment = start < s.endIndex ? String(s[start...]).trimmingCharacters(in: .init(charactersIn: " \t\r")) : ""
        return (body, comment.isEmpty ? nil : comment)
    }

    fileprivate static func _annotatedParseScalar(_ s: String) -> Any { parseScalar(s) }
    fileprivate static func _annotatedParseFlowMapping(_ s: String) -> [String: Any] { parseFlowMapping(s) }
    fileprivate static func _annotatedSplitKV(_ s: String) -> (String, String) { splitKV(s) }
}

fileprivate func _annotatedWalkMapping(metas: [MiniYAMLAnnotatedLine], i: inout Int, indent: Int, into m: inout CmpMapping) {
    while i < metas.count {
        let l = metas[i]
        if l.isPure {
            if !l.raw.isEmpty {
                if m.entries.isEmpty {
                    m.leadingComments.append(l.raw)
                } else {
                    m.entries[m.entries.count - 1].leadingComments.append(l.raw)
                }
            }
            i += 1
            continue
        }
        if l.indent < indent { return }
        if l.indent > indent { i += 1; continue }
        let content = String(l.raw.dropFirst(l.indent))
        if content.hasPrefix("- ") { return }
        guard let colon = content.firstIndex(of: ":") else { i += 1; continue }
        let key = String(content[..<colon]).trimmingCharacters(in: .whitespaces)
        let valuePart = content[content.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        var entry = CmpEntry(key: key, value: .scalar(NSNull()), leadingComments: l.leading, inlineComment: l.inline)
        if valuePart.isEmpty {
            if i + 1 < metas.count {
                let next = metas[i + 1]
                if next.indent > indent {
                    if next.isPure { i += 1; continue }
                    let nextContent = String(next.raw.dropFirst(next.indent))
                    if nextContent.hasPrefix("- ") {
                        var items: [CmpListItem] = []
                        _annotatedWalkList(metas: metas, i: &i, indent: next.indent, into: &items)
                        entry.value = .list(items)
                    } else {
                        var sub = CmpMapping()
                        _annotatedWalkMapping(metas: metas, i: &i, indent: next.indent, into: &sub)
                        entry.value = .mapping(sub)
                    }
                    m.entries.append(entry)
                    continue
                }
            }
            m.entries.append(entry)
            i += 1
        } else {
            entry.value = .scalar(MiniYAML._annotatedParseScalar(valuePart))
            m.entries.append(entry)
            i += 1
        }
    }
}

fileprivate func _annotatedWalkList(metas: [MiniYAMLAnnotatedLine], i: inout Int, indent: Int, into items: inout [CmpListItem]) {
    while i < metas.count {
        let l = metas[i]
        if l.isPure {
            if !l.raw.isEmpty {
                if items.isEmpty { /* skip - 无归属 */ } else {
                    items[items.count - 1].leadingComments.append(l.raw)
                }
            }
            i += 1
            continue
        }
        if l.indent < indent { return }
        if l.indent > indent { i += 1; continue }
        let content = String(l.raw.dropFirst(l.indent))
        if !content.hasPrefix("- ") { return }
        let rest = String(content.dropFirst(2))
        var item = CmpListItem(value: .scalar(NSNull()), leadingComments: l.leading, inlineComment: l.inline)
        if rest.isEmpty {
            if i + 1 < metas.count {
                let next = metas[i + 1]
                if next.indent > indent {
                    if next.isPure { i += 1; continue }
                    let nextContent = String(next.raw.dropFirst(next.indent))
                    if nextContent.hasPrefix("- ") {
                        var sub: [CmpListItem] = []
                        _annotatedWalkList(metas: metas, i: &i, indent: next.indent, into: &sub)
                        item.value = .list(sub)
                    } else {
                        var sub = CmpMapping()
                        _annotatedWalkMapping(metas: metas, i: &i, indent: next.indent, into: &sub)
                        item.value = .mapping(sub)
                    }
                    items.append(item)
                    continue
                }
            }
            item.value = .scalar("")
            items.append(item)
            i += 1
        } else if rest.hasPrefix("{") && rest.hasSuffix("}") && rest.count >= 2 {
            let d = MiniYAML._annotatedParseFlowMapping(rest)
            item.value = .mapping(CmpMapping.from(d))
            items.append(item)
            i += 1
        } else if rest.contains(":") && !rest.hasPrefix("\"") && !rest.hasPrefix("'") {
            let (k, v) = MiniYAML._annotatedSplitKV(rest)
            var sub = CmpMapping()
            sub.entries.append(CmpEntry(key: k, value: .scalar(MiniYAML._annotatedParseScalar(v))))
            var j = i + 1
            while j < metas.count {
                let l2 = metas[j]
                if l2.isPure {
                    if !l2.raw.isEmpty {
                        if let lastIdx = sub.entries.indices.last {
                            sub.entries[lastIdx].leadingComments.append(l2.raw)
                        }
                    }
                    j += 1
                    continue
                }
                if l2.indent > indent {
                    let c2 = String(l2.raw.dropFirst(l2.indent))
                    if let c = c2.firstIndex(of: ":") {
                        let k2 = String(c2[..<c]).trimmingCharacters(in: .whitespaces)
                        let v2 = c2[c2.index(after: c)...].trimmingCharacters(in: .whitespaces)
                        sub.entries.append(CmpEntry(key: k2, value: .scalar(MiniYAML._annotatedParseScalar(v2)), leadingComments: l2.leading, inlineComment: l2.inline))
                        j += 1
                        continue
                    }
                    j += 1
                    continue
                }
                break
            }
            item.value = .mapping(sub)
            items.append(item)
            i = j
        } else {
            item.value = .scalar(MiniYAML._annotatedParseScalar(rest))
            items.append(item)
            i += 1
        }
    }
}
