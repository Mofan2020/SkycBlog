import Foundation

/// Mustache 风格模板引擎。
/// - 变量：{{ var }} / {{ var.path }} / {{# var }} ... {{/ var }}
/// - 条件：{{#if cond}}...{{else}}...{{/if}}  / {{^ cond}}
/// - 循环：{{#each items}}...{{/each}}  / {{# items}}...{{/ items}}
/// - 部分模板：{{> name }}
/// - 注释：{{! ... }}
/// - 短代码：{% name params %}（内联）
public final class TemplateEngine {
    public let themeRoot: String
    public var helpers: [String: ([Any?]) -> String] = [:]
    public var partialCache: [String: String] = [:]
    public var warnings: [String] = []
    public var contextStack: [[String: Any]] = []

    public init(themeRoot: String) {
        self.themeRoot = themeRoot
        registerBuiltinHelpers()
    }

    public func render(template: String, context: [String: Any]) -> String {
        contextStack = [context]
        return renderString(template)
    }

    public func renderFile(name: String, context: [String: Any]) -> String {
        let path = (themeRoot as NSString).appendingPathComponent("templates/\(name).html")
        guard let tpl = FSUtil.readText(path) else {
            warnings.append("模板文件缺失: \(name).html")
            return "<!-- missing template: \(name) -->"
        }
        return render(template: tpl, context: context)
    }

    public func renderString(_ s: String) -> String {
        let expanded = expandBlocks(s)
        return process(expanded)
    }

    // MARK: - 块标签解析（先把所有 #… / ^… / /… 解析为最终内容）

    func expandBlocks(_ s: String) -> String {
        var out = ""
        var i = s.startIndex
        var textBufferStart = s.startIndex
        while i < s.endIndex {
            if let open = s.range(of: "{{", range: i..<s.endIndex),
               let close = s.range(of: "}}", range: open.upperBound..<s.endIndex) {
                let between = String(s[open.upperBound..<close.lowerBound]).trimmingCharacters(in: .whitespaces)
                if between.hasPrefix("#") || between.hasPrefix("^") {
                    // 把 textBuffer 追加到 out
                    out += s[textBufferStart..<open.lowerBound]
                    // 寻找匹配的结束标签
                    let startTag = between
                    let endTag = "/" + String(startTag.dropFirst().split(separator: " ", maxSplits: 1).first ?? "")
                    if let (content, after) = findBlock(in: s, from: close.upperBound, openTag: startTag, endTag: endTag) {
                        let blockHTML = renderBlock(startTag, content: content)
                        out += blockHTML
                        i = after
                        textBufferStart = after
                        continue
                    } else {
                        warnings.append("块标签未闭合：\(startTag)")
                        i = close.upperBound
                        textBufferStart = close.upperBound
                        continue
                    }
                } else {
                    out += s[textBufferStart..<close.upperBound]
                    i = close.upperBound
                    textBufferStart = close.upperBound
                    continue
                }
            } else {
                break
            }
        }
        out += s[textBufferStart..<s.endIndex]
        return out
    }

    /// 找到匹配的 {{/...}} 块并返回 (内容, 结束位置)。
    func findBlock(in s: String, from: String.Index, openTag: String, endTag: String) -> (String, String.Index)? {
        var depth = 1
        var i = from
        // 同时检测嵌套：相同开标签的 #xxx 与 ^xxx 都计入 depth
        let openerPrefix = String(openTag.split(separator: " ", maxSplits: 1).first ?? "")
        let openerBody = String(openerPrefix.dropFirst())  // 去掉 # 或 ^
        while i < s.endIndex {
            if let open = s.range(of: "{{", range: i..<s.endIndex),
               let close = s.range(of: "}}", range: open.upperBound..<s.endIndex) {
                let tag = String(s[open.upperBound..<close.lowerBound]).trimmingCharacters(in: .whitespaces)
                let token = String(tag.split(separator: " ", maxSplits: 1).first ?? "")
                if (tag.hasPrefix("#") || tag.hasPrefix("^")) {
                    let tokenBody = String(token.dropFirst())
                    if tokenBody == openerBody { depth += 1 }
                } else if tag.hasPrefix("/") {
                    let tokenBody = String(token.dropFirst())
                    if tokenBody == openerBody {
                        depth -= 1
                        if depth == 0 {
                            return (String(s[from..<open.lowerBound]), close.upperBound)
                        }
                    }
                }
                i = close.upperBound
            } else {
                return nil
            }
        }
        return nil
    }

    func renderBlock(_ openTag: String, content: String) -> String {
        if openTag.hasPrefix("^") {
            let key = String(openTag.dropFirst()).trimmingCharacters(in: .whitespaces)
            let v = resolvePath(key)
            if isFalsy(v) { return process(expandBlocks(content)) } else { return "" }
        }
        if openTag.hasPrefix("#") {
            let body = String(openTag.dropFirst()).trimmingCharacters(in: .whitespaces)
            let tokens = body.split(separator: " ", maxSplits: 1).map(String.init)
            if tokens.first == "if" {
                let cond = tokens.count > 1 ? tokens[1] : ""
                let v = resolvePath(cond)
                if let (truthy, falsy) = splitElse(content) {
                    return isFalsy(v) ? process(expandBlocks(falsy)) : process(expandBlocks(truthy))
                }
                return isFalsy(v) ? "" : process(expandBlocks(content))
            } else if tokens.first == "unless" {
                let cond = tokens.count > 1 ? tokens[1] : ""
                let v = resolvePath(cond)
                if let (truthy, falsy) = splitElse(content) {
                    return isFalsy(v) ? process(expandBlocks(truthy)) : process(expandBlocks(falsy))
                }
                return isFalsy(v) ? process(expandBlocks(content)) : ""
            } else if tokens.first == "each" {
                let varName = tokens.count > 1 ? tokens[1] : ""
                let v = resolvePath(varName)
                guard let arr = v as? [Any] else { return "" }
                var out = ""
                for (idx, item) in arr.enumerated() {
                    pushScope(item: item, index: idx, total: arr.count, key: varName)
                    out += process(expandBlocks(content))
                    popScope()
                }
                return out
            } else {
                let v = resolvePath(body)
                if isFalsy(v) { return "" }
                if let arr = v as? [Any] {
                    var out = ""
                    for (idx, item) in arr.enumerated() {
                        pushScope(item: item, index: idx, total: arr.count, key: body)
                        out += process(expandBlocks(content))
                        popScope()
                    }
                    return out
                }
                return process(expandBlocks(content))
            }
        }
        return ""
    }

    /// 把 "{{else}}" 切分为 (truthy, falsy)。
    func splitElse(_ s: String) -> (String, String)? {
        // 简单文本扫描：查找 {{else}} 顶层出现
        let markers = ["{{else}}", "{{ else }}"]
        for m in markers {
            if let r = s.range(of: m) {
                return (String(s[..<r.lowerBound]), String(s[r.upperBound...]))
            }
        }
        return nil
    }

    func pushScope(item: Any, index: Int, total: Int, key: String) {
        var local = currentContext()
        if let dict = item as? [String: Any] {
            for (k, v) in dict { local[k] = v }
            if dict["@index"] == nil { local["@index"] = index }
        } else {
            local["this"] = item
            local["@index"] = index
        }
        local["@first"] = (index == 0)
        local["@last"] = (index == total - 1)
        local["@key"] = key
        contextStack.append(local)
    }

    func popScope() { if contextStack.count > 1 { contextStack.removeLast() } }

    func currentContext() -> [String: Any] { contextStack.last ?? [:] }

    // MARK: - 普通标签处理

    func process(_ s: String) -> String {
        var out = ""
        var i = s.startIndex
        while i < s.endIndex {
            // 寻找下一个 {{
            if let open = s.range(of: "{{", range: i..<s.endIndex) {
                out += s[i..<open.lowerBound]
                // 判断是否是 {{{ (三花括号)
                let afterOpen = open.upperBound
                if afterOpen < s.endIndex && s[afterOpen] == "{" {
                    // 三花括号 {{{ var }}}  不转义
                    if let close = s.range(of: "}}", range: open.upperBound..<s.endIndex) {
                        let tag = String(s[open.upperBound..<close.lowerBound])
                            .trimmingCharacters(in: .whitespaces)
                            .trimmingCharacters(in: CharacterSet(charactersIn: "{}"))
                        out += handleRawTag(tag)
                        i = close.upperBound
                        continue
                    }
                }
                // 普通 {{ var }}
                if let close = s.range(of: "}}", range: open.upperBound..<s.endIndex) {
                    let tag = String(s[open.upperBound..<close.lowerBound]).trimmingCharacters(in: .whitespaces)
                    out += handleTag(tag)
                    i = close.upperBound
                    continue
                } else {
                    out += s[open.lowerBound..<s.endIndex]
                    break
                }
            } else {
                out += s[i..<s.endIndex]
                break
            }
        }
        return expandShortcodes(out)
    }

    /// 处理 {{{ var }}} ——不转义
    func handleRawTag(_ raw: String) -> String {
        if raw.hasPrefix("!") { return "" }
        if raw.hasPrefix("#") || raw.hasPrefix("^") || raw.hasPrefix("/") { return "" }
        let parts = raw.split(separator: " ").map(String.init)
        if let first = parts.first, helpers[first] != nil {
            let args: [Any?] = parts.dropFirst().map { resolvePath(String($0)) }
            return helpers[first]!(args)
        }
        return stringify(resolvePath(raw))
    }

    /// 处理 partial 时的递归：先 expandBlocks 再 process。
    func processWithBlocks(_ s: String) -> String {
        return process(expandBlocks(s))
    }

    func handleTag(_ raw: String) -> String {
        // 注释
        if raw.hasPrefix("!") { return "" }
        // 部分模板
        if raw.hasPrefix(">") {
            return renderPartial(name: String(raw.dropFirst()).trimmingCharacters(in: .whitespaces))
        }
        // 块标记（已被 expandBlocks 处理）
        if raw.hasPrefix("#") || raw.hasPrefix("^") || raw.hasPrefix("/") { return "" }
        // helper 调用
        let parts = raw.split(separator: " ").map(String.init)
        if let first = parts.first, helpers[first] != nil {
            let args: [Any?] = parts.dropFirst().map { resolvePath(String($0)) }
            return helpers[first]!(args)
        }
        // 简单变量
        return stringify(resolvePath(raw)).htmlEscaped
    }

    func renderPartial(name: String) -> String {
        if let cached = partialCache[name] { return processWithBlocks(cached) }
        let path = (themeRoot as NSString).appendingPathComponent("templates/\(name).html")
        guard let text = FSUtil.readText(path) else {
            warnings.append("缺失部分模板：\(name)")
            return ""
        }
        partialCache[name] = text
        return processWithBlocks(text)
    }
    // MARK: - 短代码

    func expandShortcodes(_ s: String) -> String {
        return replaceRegex(s, pattern: #"\{\%\s*([a-zA-Z0-9_-]+)\s*([^%]*?)\s*\%\}"#) { m in
            let name = m[1]
            let rest = m[2].trimmingCharacters(in: .whitespaces)
            switch name {
            case "gallery":
                return "<div class=\"shortcode-gallery\" data-album=\"\(rest.htmlEscaped)\"></div>"
            case "youtube":
                return "<div class=\"shortcode-youtube\"><iframe src=\"https://www.youtube.com/embed/\(rest.htmlEscaped)\" allowfullscreen></iframe></div>"
            case "bilibili":
                return "<div class=\"shortcode-bilibili\"><iframe src=\"//player.bilibili.com/player.html?bvid=\(rest.htmlEscaped)\" allowfullscreen></iframe></div>"
            case "note":
                return "<blockquote class=\"shortcode-note\">\(rest)</blockquote>"
            case "highlight":
                return "<mark>\(rest)</mark>"
            case "center":
                return "<div class=\"shortcode-center\">\(rest)</div>"
            default:
                return "<span class=\"shortcode shortcode-\(name.htmlEscaped)\">\(rest)</span>"
            }
        }
    }

    // MARK: - helpers

    func registerBuiltinHelpers() {
        helpers["year"] = { _ in String(Calendar.current.component(.year, from: Date())) }
        helpers["dateFormat"] = { args in
            guard let d = args.first as? Date else { return "" }
            return DateUtil.human.string(from: d)
        }
        helpers["urlEncode"] = { args in
            (args.first as? String ?? "").addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        }
        helpers["excerptOf"] = { args in
            guard let s = args.first as? String else { return "" }
            return MarkdownRenderer.excerpt(from: s, length: 150)
        }
        helpers["json"] = { args in
            if let d = args.first {
                if let data = try? JSONSerialization.data(withJSONObject: d, options: [.fragmentsAllowed, .sortedKeys]),
                   let str = String(data: data, encoding: .utf8) {
                    return str
                }
            }
            return ""
        }
        helpers["asset"] = { args in (args.first as? String) ?? "" }
        helpers["upper"] = { args in (args.first as? String ?? "").uppercased() }
        helpers["lower"] = { args in (args.first as? String ?? "").lowercased() }
        helpers["stripHTML"] = { args in
            (args.first as? String ?? "").replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        }
        helpers["truncate"] = { args in
            let s = (args.first as? String) ?? ""
            let n = (args.dropFirst().first as? Int) ?? 100
            if s.count <= n { return s }
            return String(s.prefix(n)) + "…"
        }
        helpers["count"] = { args in
            if let a = args.first as? [Any] { return String(a.count) }
            if let s = args.first as? String { return String(s.count) }
            return "0"
        }
    }

    // MARK: - 解析

    /// 递归剥掉 Optional 包装，便于处理 dict["key"] 返回的 Any?
    func unwrap(_ v: Any?) -> Any? {
        if let s = v as? String { return s }
        if let d = v as? [String: Any] { return d }
        if let a = v as? [Any] { return a }
        if let i = v as? Int { return i }
        if let b = v as? Bool { return b }
        if let dd = v as? Double { return dd }
        // 镜像 mirror：剥 Optional
        let mirror = Mirror(reflecting: v as Any)
        if mirror.displayStyle == .optional {
            if let child = mirror.children.first {
                return unwrap(child.value)
            }
            return nil
        }
        return v
    }

    func resolvePath(_ path: String) -> Any? {
        if path.isEmpty { return nil }
        let parts = path.split(separator: ".").map(String.init)
        var cur: Any? = unwrap(currentContext())
        for p in parts {
            if let d = cur as? [String: Any] { cur = unwrap(d[p]) }
            else if let a = cur as? [Any], let idx = Int(p), idx >= 0, idx < a.count { cur = unwrap(a[idx]) }
            else { return nil }
        }
        return cur
    }

    func stringify(_ v: Any?) -> String {
        if v == nil { return "" }
        if let s = v as? String { return s }
        if let b = v as? Bool { return b ? "true" : "false" }
        if let i = v as? Int { return String(i) }
        if let d = v as? Double { return String(d) }
        if let d = v as? Date { return DateUtil.iso.string(from: d) }
        if let arr = v as? [Any] { return arr.map { stringify($0) }.joined(separator: ", ") }
        if let arr = v as? [String] { return arr.joined(separator: ", ") }
        if let dict = v as? [String: Any] {
            if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.fragmentsAllowed, .sortedKeys]),
               let str = String(data: data, encoding: .utf8) { return str }
        }
        return String(describing: v!)
    }

    func isFalsy(_ v: Any?) -> Bool {
        if v == nil { return true }
        if let b = v as? Bool { return !b }
        if let s = v as? String { return s.isEmpty }
        if let a = v as? [Any] { return a.isEmpty }
        if let d = v as? [String: Any] { return d.isEmpty }
        if let i = v as? Int { return i == 0 }
        return false
    }

    // MARK: - 正则

    func replaceRegex(_ s: String, pattern: String, _ transform: ([String]) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return s }
        let nsString = s as NSString
        let matches = regex.matches(in: s, range: NSRange(location: 0, length: nsString.length))
        var result = ""
        var cursor = 0
        for m in matches {
            let start = m.range.location
            let len = m.range.length
            if start > cursor { result += nsString.substring(with: NSRange(location: cursor, length: start - cursor)) }
            var groups: [String] = []
            for g in 0..<m.numberOfRanges {
                let r = m.range(at: g)
                groups.append(r.location == NSNotFound ? "" : nsString.substring(with: r))
            }
            result += transform(groups)
            cursor = start + len
        }
        if cursor < nsString.length { result += nsString.substring(with: NSRange(location: cursor, length: nsString.length - cursor)) }
        return result
    }
}

/// 把 Page 数组转为模板字典。
public enum TemplateContextBuilder {
    public static func build(config: SiteConfig, pages: [Page], tags: [String: [Page]], categories: [String: [Page]]) -> [String: Any] {
        let site: [String: Any] = [
            "title": config.title,
            "description": config.description,
            "author": config.author,
            "language": config.language,
            "baseURL": config.baseURL,
            "year": Calendar.current.component(.year, from: Date()),
            "url": config.baseURL,
        ]
        var theme: [String: Any] = [:]
        for (k, v) in config.themeConfig { theme[k] = v }
        let posts: [[String: Any]] = pages.filter { $0.kind == .post }.map { pageDict($0) }
        let standalone: [[String: Any]] = pages.filter { $0.kind == .page }.map { pageDict($0) }
        let albums: [[String: Any]] = pages.filter { $0.kind == .album }.map { pageDict($0) }
        var tagMap: [String: [[String: Any]]] = [:]
        for (k, v) in tags { tagMap[k] = v.map { pageDict($0) } }
        var catMap: [String: [[String: Any]]] = [:]
        for (k, v) in categories { catMap[k] = v.map { pageDict($0) } }
        let archives = groupByYear(posts: pages.filter { $0.kind == .post })
        return [
            "site": site,
            "config": site,
            "theme": theme,
            "pages": posts,
            "posts": posts,
            "standalonePages": standalone,
            "albums": albums,
            "tags": tagMap.keys.sorted().map { ["name": $0, "slug": Permalink.slugify($0), "url": Permalink.resolveTag(tag: $0)] },
            "tagMap": tagMap,
            "categories": catMap.keys.sorted().map { ["name": $0, "slug": $0.lowercased().replacingOccurrences(of: " ", with: "-"), "url": Permalink.resolveCategory(category: $0)] },
            "categoryMap": catMap,
            "archives": archives,
            "now": Date(),
        ]
    }

    public static func pageDict(_ p: Page) -> [String: Any] {
        var d: [String: Any] = [
            "title": p.title,
            "date": p.date,
            "isoDate": DateUtil.iso.string(from: p.date),
            "dateString": DateUtil.yyyyMMdd.string(from: p.date),
            "tags": p.tags,
            "categories": p.categories,
            "slug": p.slug,
            "url": p.url,
            "outPath": p.outPath,
            "content": p.contentHTML,
            "excerpt": p.excerpt ?? "",
            "draft": p.draft,
            "layout": p.layout,
            "id": p.id,
        ]
        if let cover = p.cover { d["cover"] = cover } else { d["cover"] = "" }
        let reserved: Set<String> = ["title", "date", "tags", "categories", "slug", "url", "outPath", "content", "excerpt", "draft", "layout", "id", "cover"]
        for (k, v) in p.extra where !reserved.contains(k) { d[k] = v }
        return d
    }

    public static func groupByYear(posts: [Page]) -> [[String: Any]] {
        let groups = Dictionary(grouping: posts) { (p: Page) -> Int in
            Calendar.current.component(.year, from: p.date)
        }
        return groups.keys.sorted(by: >).map { year in
            let items = (groups[year] ?? []).map { pageDict($0) }
            return ["year": year, "posts": items] as [String: Any]
        }
    }
}
