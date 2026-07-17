import Foundation
#if canImport(CommonCrypto)
import CommonCrypto
#endif

/// EJS (Embedded JavaScript) 核心子集解析器。
/// 覆盖 Hexo 主题常用语法, 故意不做完整 JS 求值 (Hexo 主题用到的部分)。
///  - `<% code %>`         脚本块, 不输出
///  - `<%= expr %>`        转义输出
///  - `<%- expr %>`        原始 (不转义) 输出
///  - `<%# comment %>`     注释
///  - `<% include("path") %>` 引入子模板 (Hexo 风格)
///  - `<% layout("name") %>`   使用 layout 布局
///  - `<%- partial("name", {vars}) %>` Hexo 7.x partial
///  - `<% if/else %>`, `<% for %>`, `<% while %>`, `<% switch/case %>`
///  - 变量: 简单 `locals.xxx`、context 注入
///  - 字符串/数字/布尔字面量、数组字面量
public final class EJSEngine {
    public let themeRoot: String
    public var warnings: [String] = []
    public var partialCache: [String: String] = [:]
    /// 注入给模板的额外 helper (例如 `url_for`, `full_url`, `theme.config.x`)
    public var helpers: [String: Any] = [:]

    public init(themeRoot: String) {
        self.themeRoot = themeRoot
    }

    public func renderFile(relPath: String, context: [String: Any]) -> String {
        let path = (themeRoot as NSString).appendingPathComponent(relPath)
        guard let text = FSUtil.readText(path) else {
            warnings.append("EJS 模板缺失: \(relPath)")
            return ""
        }
        return render(template: text, context: context, currentPath: relPath)
    }

    public func render(template: String, context: [String: Any], currentPath: String = "") -> String {
        let blocks = tokenize(template)
        var ctx = EJSContext()
        ctx.userContext = context
        for (k, v) in helpers { ctx.userContext[k] = v }
        return runStatements(blocks, ctx: &ctx, currentPath: currentPath)
    }

    // MARK: - Tokenize

    /// 解析 `<%...%>` 标签, 把模板切成 [(text, tagType, code)] 序列。
    /// text 为输出字面量; tagType 为 "code" / "=" / "-" / "#", code 为 % 内的源码。
    public struct Block {
        public let text: String
        public let tagType: String
        public let code: String
        public init(text: String, tagType: String, code: String) {
            self.text = text
            self.tagType = tagType
            self.code = code
        }
    }

    public func tokenize(_ src: String) -> [Block] {
        var blocks: [Block] = []
        var i = src.startIndex
        var textStart = i
        while i < src.endIndex {
            if let open = src.range(of: "<%", range: i..<src.endIndex) {
                let textLiteral = String(src[textStart..<open.lowerBound])
                if let close = src.range(of: "%>", range: open.upperBound..<src.endIndex) {
                    var code = String(src[open.upperBound..<close.lowerBound])
                    var tagType = "code"
                    if let first = code.first {
                        if first == "=" || first == "-" {
                            tagType = String(first)
                            code = String(code.dropFirst())
                        } else if first == "#" {
                            tagType = "#"
                            code = String(code.dropFirst())
                        }
                    }
                    code = code.trimmingCharacters(in: .whitespacesAndNewlines)
                    blocks.append(Block(text: textLiteral, tagType: tagType, code: code))
                    i = close.upperBound
                    textStart = i
                } else {
                    // 没有找到 %>, 把剩余全部作为字面量
                    var rest = String(src[textStart..<open.lowerBound])
                    rest += "<%"
                    rest += String(src[open.upperBound..<src.endIndex])
                    blocks.append(Block(text: rest, tagType: "code", code: ""))
                    return blocks
                }
            } else {
                blocks.append(Block(text: String(src[textStart..<src.endIndex]), tagType: "code", code: ""))
                return blocks
            }
        }
        return blocks
    }

    // MARK: - Context

    /// 模板执行环境
    public final class EJSContext {
        public var userContext: [String: Any] = [:]
        public var stack: [[String: Any]] = []
        public var pendingLayout: String? = nil
        public var pendingBody: String = ""

        public init() {}

        public func pushScope(_ d: [String: Any]) { stack.append(d) }
        public func popScope() { if !stack.isEmpty { stack.removeLast() } }
        public func top() -> [String: Any] { stack.last ?? userContext }
        public func mergedTop() -> [String: Any] {
            // 把 userContext 与 stack 合并 (stack 优先)
            var out = userContext
            for s in stack {
                for (k, v) in s { out[k] = v }
            }
            return out
        }
    }

    // MARK: - 主循环

    public func runStatements(_ blocks: [Block], ctx: inout EJSContext, currentPath: String) -> String {
        var output = ""
        var i = 0
        while i < blocks.count {
            let b = blocks[i]
            output += b.text
            if b.tagType == "#" { i += 1; continue }
            if b.tagType == "=" {
                let expr = b.code
                let v = eval(expr, ctx: &ctx)
                output += htmlEscape(stringify(v))
                i += 1
                continue
            }
            if b.tagType == "-" {
                // 也可能是 partial / include 调用 (Hexo 常用 <%- partial(...) %>)
                let trimRaw = b.code.trimmingCharacters(in: .whitespacesAndNewlines)
                if let parts = matchCallWithObject(name: "partial", raw: trimRaw) {
                    let incPath = stripQuotes(parts.0)
                    let resolved = resolveIncludePath(incPath, from: currentPath)
                    let extra = evalObjectLiteral(parts.1, ctx: &ctx)
                    output += renderPartial(path: resolved, with: extra, currentPath: resolved, ctx: &ctx)
                    i += 1
                    continue
                }
                if let incPath = matchCall(name: "partial", raw: trimRaw) {
                    let path = stripQuotes(incPath)
                    let resolved = resolveIncludePath(path, from: currentPath)
                    output += renderInclude(path: resolved, currentPath: resolved, ctx: &ctx)
                    i += 1
                    continue
                }
                if let incPath = matchCall(name: "include", raw: trimRaw) {
                    let path = stripQuotes(incPath)
                    let resolved = resolveIncludePath(path, from: currentPath)
                    output += renderInclude(path: resolved, currentPath: resolved, ctx: &ctx)
                    i += 1
                    continue
                }
                let expr = b.code
                let v = eval(expr, ctx: &ctx)
                output += stringify(v)
                i += 1
                continue
            }
            // 脚本块: 识别 if / for / while / include / partial / layout / 一般表达式
            let trim = b.code.trimmingCharacters(in: .whitespacesAndNewlines)
            // include('path')
            if let incPath = matchCall(name: "include", raw: trim) {
                let path = stripQuotes(incPath)
                let resolved = resolveIncludePath(path, from: currentPath)
                output += renderInclude(path: resolved, currentPath: resolved, ctx: &ctx)
                i += 1
                continue
            }
            // partial('name', {...})
            if let parts = matchCallWithObject(name: "partial", raw: trim) {
                let incPath = stripQuotes(parts.0)
                let resolved = resolveIncludePath(incPath, from: currentPath)
                let extra = evalObjectLiteral(parts.1, ctx: &ctx)
                output += renderPartial(path: resolved, with: extra, currentPath: resolved, ctx: &ctx)
                i += 1
                continue
            }
            // partial('name')  (无第二参数)
            if let incPath = matchCall(name: "partial", raw: trim) {
                let path = stripQuotes(incPath)
                let resolved = resolveIncludePath(path, from: currentPath)
                output += renderInclude(path: resolved, currentPath: resolved, ctx: &ctx)
                i += 1
                continue
            }
            // layout('name')
            if let p = matchCall(name: "layout", raw: trim) {
                let layoutName = stripQuotes(p)
                ctx.pendingLayout = layoutName
                ctx.pendingBody = output
                output = ""
                i += 1
                continue
            }
            // 块结构: if / for / while
            if isBlockStart(trim, keyword: "if") {
                guard let range = consumeIfRange(blocks, start: i) else {
                    warnings.append("if 未闭合: \(trim)")
                    i += 1
                    continue
                }
                output += renderIf(blocks: blocks, range: range, ctx: &ctx, currentPath: currentPath)
                i = range.endif + 1
                continue
            }
            if isBlockStart(trim, keyword: "for") {
                guard let range = consumeBlockRange(blocks, start: i, keyword: "for", endKeyword: "endfor") else {
                    warnings.append("for 未闭合: \(trim)")
                    i += 1
                    continue
                }
                output += renderFor(blocks: blocks, range: range, ctx: &ctx, currentPath: currentPath)
                i = range.endIndex
                continue
            }
            if isBlockStart(trim, keyword: "while") {
                guard let range = consumeBlockRange(blocks, start: i, keyword: "while", endKeyword: "endwhile") else {
                    warnings.append("while 未闭合: \(trim)")
                    i += 1
                    continue
                }
                output += renderWhile(blocks: blocks, range: range, ctx: &ctx, currentPath: currentPath)
                i = range.endIndex
                continue
            }
            // Hexo 风格的块级 each/forEach: <% page.posts.each(function(post){ %> ... <% }) %>
            if let eachInfo = parseEachBlock(trim) {
                guard let endIdx = consumeEachBlockEnd(blocks, start: i) else {
                    warnings.append("each 未闭合: \(trim)")
                    i += 1
                    continue
                }
                let innerBlocks = Array(blocks[(i + 1)..<endIdx])
                let arr = eval(eachInfo.arrayExpr, ctx: &ctx) as? [Any] ?? []
                for (idx, item) in arr.enumerated() {
                    var scope: [String: Any] = ["i": idx, "index": idx]
                    for name in eachInfo.varNames {
                        if eachInfo.varNames.count == 1 {
                            scope[name] = item
                        }
                    }
                    if let d = item as? [String: Any] {
                        for (k, v) in d { scope[k] = v }
                        // 第一个 varName 默认取 item
                        if let first = eachInfo.varNames.first {
                            scope[first] = item
                        }
                    } else if let first = eachInfo.varNames.first {
                        scope[first] = item
                    }
                    ctx.pushScope(scope)
                    output += runStatements(innerBlocks, ctx: &ctx, currentPath: currentPath)
                    ctx.popScope()
                }
                i = endIdx + 1
                continue
            }
            // 一般表达式 / 赋值
            _ = eval(trim, ctx: &ctx)
            i += 1
        }
        if let layoutName = ctx.pendingLayout, !layoutName.isEmpty {
            let body = ctx.pendingBody + output
            ctx.pendingLayout = nil
            ctx.pendingBody = ""
            return renderLayout(name: layoutName, body: body, ctx: &ctx, currentPath: currentPath)
        }
        return output
    }

    // MARK: - 块级 each/forEach 解析 (Hexo 风格)

    private struct EachBlockInfo {
        let arrayExpr: String      // 例: "page.posts"
        let varNames: [String]     // 例: ["post", "i"] 或 ["post"]
    }

    /// 解析 `*.each(function(a, b){` / `*.forEach(function(a, b){` 形式
    private func parseEachBlock(_ code: String) -> EachBlockInfo? {
        let t = code.trimmingCharacters(in: .whitespacesAndNewlines)
        // 必须在结尾有 `{`
        guard t.hasSuffix("{") else { return nil }
        let body = String(t.dropLast()).trimmingCharacters(in: .whitespaces)
        // 检测 .each( 或 .forEach(
        guard let range = body.range(of: ".each(") ?? body.range(of: ".forEach(") else { return nil }
        let arrayExpr = String(body[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
        // 截取 each(...) 内的内容
        let after = String(body[range.upperBound..<body.endIndex])
        // 提取 function(args) 或 (args)=> 的 args
        // 用 matchBracket 找与第一个 ( 匹配的 )
        guard let openParen = after.firstIndex(of: "(") else { return nil }
        guard let closeParen = matchBracket(after, openIdx: openParen) else { return nil }
        let argsStr = String(after[after.index(after: openParen)..<closeParen])
        let varNames = argsStr.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if varNames.isEmpty { return nil }
        return EachBlockInfo(arrayExpr: arrayExpr, varNames: varNames)
    }

    /// 找块级 each 的结束位置 `<% }) %>`, 支持嵌套
    private func consumeEachBlockEnd(_ blocks: [Block], start: Int) -> Int? {
        var depth = 1
        var i = start + 1
        while i < blocks.count {
            let b = blocks[i]
            let t = b.code.trimmingCharacters(in: .whitespacesAndNewlines)
            if parseEachBlock(t) != nil { depth += 1 }
            // 结束标记: `})` 或 `} %)` 之类
            if t == "})" || t == "});" || t == "}" {
                depth -= 1
                if depth == 0 { return i }
            }
            i += 1
        }
        return nil
    }

    // MARK: - 块范围解析

    private struct IfRange {
        let ifStart: Int          // <% if (cond) { %>
        let headEnd: Int          // 同上, 单一 if 行
        var elseStart: Int = -1   // <% } else { %> 或 <% } else if (...) { %>
        var elifConds: [String] = []
        var elifStarts: [Int] = []
        var endif: Int = -1       // <% } %> 或 <% } endif { %>
    }

    private struct BlockRange {
        let head: Int
        let bodyStart: Int
        let bodyEnd: Int
        let endIndex: Int
    }

    private func isBlockStart(_ trim: String, keyword: String) -> Bool {
        if trim == keyword { return true }
        if trim.hasPrefix("\(keyword) ") { return true }
        if trim.hasPrefix("\(keyword)(") { return true }
        if trim.hasPrefix("\(keyword) (") { return true }
        return false
    }

    private func consumeIfRange(_ blocks: [Block], start: Int) -> IfRange? {
        var r = IfRange(ifStart: start, headEnd: start)
        var depth = 1
        var i = start + 1
        while i < blocks.count {
            let t = blocks[i].code.trimmingCharacters(in: .whitespacesAndNewlines)
            if isBlockStart(t, keyword: "if") {
                depth += 1
            } else if isBlockStart(t, keyword: "for") {
                depth += 1
            } else if isBlockStart(t, keyword: "while") {
                depth += 1
            } else if parseEachBlock(t) != nil {
                // Hexo 风格的块级 each/forEach: 跳到匹配的 `})`
                depth += 1
            } else if depth == 1 {
                // 分支: <% } else { %>  /  <% } else if (cond) { %>  /  <% } else { %>
                if t.hasPrefix("} else") || t.hasPrefix("}else") {
                    // 拆分: `} else if (...) {`  /  `} else {`
                    if t.contains("else if") || t.contains("elseif") {
                        r.elifStarts.append(i)
                        // 提取 cond
                        let cond: String
                        if let r1 = t.range(of: "else if") {
                            cond = String(t[r1.upperBound...]).trimmingCharacters(in: .whitespaces)
                        } else if let r1 = t.range(of: "elseif") {
                            cond = String(t[r1.upperBound...]).trimmingCharacters(in: .whitespaces)
                        } else { cond = "true" }
                        // 去掉首尾的 "(...)"  和结尾可能的 "{"
                        var c = cond
                        if let brace = c.firstIndex(of: "{") { c = String(c[..<brace]) }
                        c = c.trimmingCharacters(in: .whitespaces)
                        if c.hasPrefix("(") && c.hasSuffix(")") { c = String(c.dropFirst().dropLast()) }
                        else if c.hasPrefix("(") { c = String(c.dropFirst()) }
                        else if c.hasSuffix(")") { c = String(c.dropLast()) }
                        r.elifConds.append(c.trimmingCharacters(in: .whitespaces))
                    } else {
                        // 普通 else
                        r.elseStart = i
                    }
                } else if t == "else" || t.hasPrefix("else {") {
                    r.elseStart = i
                } else if t.hasPrefix("else if") || t.hasPrefix("else if(") || t.hasPrefix("elif") {
                    r.elifStarts.append(i)
                    let condStart = t.hasPrefix("else") ? t.index(t.startIndex, offsetBy: 7) : t.index(t.startIndex, offsetBy: 4)
                    let cond = String(t[condStart...]).trimmingCharacters(in: .whitespaces)
                    r.elifConds.append(cond)
                } else if t == "endif" || t == "}" || t == "} " || t == "})" || t == "}else" {
                    r.endif = i
                    return r
                }
            } else {
                if t == "endif" || t == "}" || t == "})" {
                    depth -= 1
                }
            }
            i += 1
        }
        return nil
    }

    private func consumeBlockRange(_ blocks: [Block], start: Int, keyword: String, endKeyword: String) -> BlockRange? {
        var depth = 1
        var i = start + 1
        while i < blocks.count {
            let t = blocks[i].code.trimmingCharacters(in: .whitespacesAndNewlines)
            if isBlockStart(t, keyword: "if") {
                depth += 1
            } else if isBlockStart(t, keyword: "for") {
                depth += 1
            } else if isBlockStart(t, keyword: "while") {
                depth += 1
            } else if parseEachBlock(t) != nil {
                depth += 1
            } else if t == endKeyword || t == "}" || t == "})" {
                depth -= 1
                if depth == 0 {
                    return BlockRange(head: start, bodyStart: start + 1, bodyEnd: i, endIndex: i + 1)
                }
            }
            i += 1
        }
        return nil
    }

    // MARK: - 块渲染

    private func renderIf(blocks: [Block], range: IfRange, ctx: inout EJSContext, currentPath: String) -> String {
        let head = blocks[range.headEnd].code
        let cond = stripIfHead(head)
        let condVal = eval(cond, ctx: &ctx)
        if isTruthy(condVal) {
            // if 满足: body 范围 headEnd+1 ... elseStart-1 (如果有 else) 或 endif-1
            // 还要把 endif 块的 text 算上
            let bodyEnd = (range.elseStart >= 0) ? range.elseStart - 1 : range.endif - 1
            let out1 = runSlice(blocks, from: range.headEnd + 1, to: bodyEnd, ctx: &ctx, currentPath: currentPath)
            return out1 + blocks[range.endif].text
        }
        // 逐个 elif 判断
        let totalElif = range.elifStarts.count
        for k in 0..<totalElif {
            let idx = range.elifStarts[k]
            let condStr = (k < range.elifConds.count) ? range.elifConds[k] : "true"
            let elifVal = eval(condStr, ctx: &ctx)
            if isTruthy(elifVal) {
                // 上一分支的 text (= `} else if (cond) {` 块的 text) 属于前一个分支, 在此我们用前一分支已经在它的路径里追加过
                // 实际: 块 i = `} else if (...) {` 的 text 在 i-1 之后. 所以 elif 块 (i=k) 的 body 范围 = i+1 ... (elseStart-1 或 endif-1 或 next elif-1)
                let bodyEnd: Int
                if k + 1 < totalElif {
                    bodyEnd = range.elifStarts[k + 1] - 1
                } else if range.elseStart >= 0 {
                    bodyEnd = range.elseStart - 1
                } else {
                    bodyEnd = range.endif - 1
                }
                let out1 = runSlice(blocks, from: idx + 1, to: bodyEnd, ctx: &ctx, currentPath: currentPath)
                return out1 + blocks[range.endif].text
            }
        }
        // else
        if range.elseStart >= 0 {
            // body 范围 = elseStart+1 ... endif-1, endif 块 text 属于 else
            let bodyOut = runSlice(blocks, from: range.elseStart + 1, to: range.endif - 1, ctx: &ctx, currentPath: currentPath)
            return bodyOut + blocks[range.endif].text
        }
        return ""
    }

    private func runSlice(_ blocks: [Block], from: Int, to: Int, ctx: inout EJSContext, currentPath: String) -> String {
        if from > to { return "" }
        let slice = Array(blocks[from...to])
        return runStatements(slice, ctx: &ctx, currentPath: currentPath)
    }

    private func renderFor(blocks: [Block], range: BlockRange, ctx: inout EJSContext, currentPath: String) -> String {
        let head = blocks[range.head].code
        let expr = stripForHead(head)
        let parsed = parseForHeader(expr)
        guard !parsed.varName.isEmpty, !parsed.listExpr.isEmpty else {
            warnings.append("for 头解析失败: \(head)")
            return ""
        }
        let list = evalList(parsed.listExpr, ctx: &ctx)
        var out = ""
        for (idx, item) in list.enumerated() {
            var scope: [String: Any] = [parsed.varName: item]
            if let v = item as? [String: Any] {
                for (k, val) in v { scope[k] = val }
            }
            scope["\(parsed.varName)_index"] = idx
            ctx.pushScope(scope)
            let bodyOut = runSlice(blocks, from: range.bodyStart, to: range.bodyEnd - 1, ctx: &ctx, currentPath: currentPath)
            // endfor 块的 text 属于 body
            out += bodyOut + blocks[range.endIndex - 1].text
            ctx.popScope()
        }
        return out
    }

    private func renderWhile(blocks: [Block], range: BlockRange, ctx: inout EJSContext, currentPath: String) -> String {
        let head = blocks[range.head].code
        let expr = stripWhileHead(head)
        var out = ""
        var safety = 0
        while isTruthy(eval(expr, ctx: &ctx)), safety < 10000 {
            let bodyOut = runSlice(blocks, from: range.bodyStart, to: range.bodyEnd - 1, ctx: &ctx, currentPath: currentPath)
            out += bodyOut + blocks[range.endIndex - 1].text
            safety += 1
        }
        if safety >= 10000 { warnings.append("while 循环次数超限") }
        return out
    }

    // MARK: - include / partial / layout

    private func renderInclude(path: String, currentPath: String, ctx: inout EJSContext) -> String {
        if let cached = partialCache[path] {
            return runTemplateText(cached, path: path, ctx: &ctx)
        }
        let abs = (themeRoot as NSString).appendingPathComponent(path)
        guard let text = FSUtil.readText(abs) else {
            warnings.append("include 失败: \(path)")
            return ""
        }
        partialCache[path] = text
        return runTemplateText(text, path: path, ctx: &ctx)
    }

    private func renderPartial(path: String, with extra: [String: Any], currentPath: String, ctx: inout EJSContext) -> String {
        // partial cache 按 path + extra 隔离
        let cacheKey = path + "|" + partialCacheKey(extra: extra)
        if let cached = partialCache[cacheKey] {
            var merged = ctx.mergedTop()
            for (k, v) in extra { merged[k] = v }
            var newCtx = EJSContext()
            newCtx.userContext = merged
            for (k, v) in helpers { newCtx.userContext[k] = v }
            return runTemplateText(cached, path: path, ctx: &newCtx)
        }
        let abs = (themeRoot as NSString).appendingPathComponent(path)
        guard let text = FSUtil.readText(abs) else {
            warnings.append("partial 失败: \(path)")
            return ""
        }
        partialCache[cacheKey] = text
        var merged = ctx.mergedTop()
        for (k, v) in extra { merged[k] = v }
        var newCtx = EJSContext()
        newCtx.userContext = merged
        for (k, v) in helpers { newCtx.userContext[k] = v }
        return runTemplateText(text, path: path, ctx: &newCtx)
    }

    private func partialCacheKey(extra: [String: Any]) -> String {
        if extra.isEmpty { return "_" }
        // JSONSerialization 不支持 Date, 用 stringify 序列化
        let parts = extra.map { k, v -> String in
            return k + "=" + stringify(v)
        }.sorted()
        return parts.joined(separator: "&")
    }

    private func renderLayout(name: String, body: String, ctx: inout EJSContext, currentPath: String) -> String {
        let candidates = [
            "layout/\(name).ejs",
            "layout/_partial/\(name).ejs",
            "layout/\(name).html",
            "layout/_partial/\(name).html",
        ]
        for c in candidates {
            let abs = (themeRoot as NSString).appendingPathComponent(c)
            if let text = FSUtil.readText(abs) {
                var merged = ctx.mergedTop()
                merged["body"] = body
                merged["content"] = body
                var layoutCtx = EJSContext()
                layoutCtx.userContext = merged
                for (k, v) in helpers { layoutCtx.userContext[k] = v }
                return runTemplateText(text, path: c, ctx: &layoutCtx)
            }
        }
        warnings.append("layout 模板未找到: \(name)")
        return body
    }

    private func runTemplateText(_ text: String, path: String, ctx: inout EJSContext) -> String {
        let blocks = tokenize(text)
        return runStatements(blocks, ctx: &ctx, currentPath: path)
    }

    private func resolveIncludePath(_ p: String, from current: String) -> String {
        // Hexo landscape 风格: '_partial/header' / 'partial/header' → layout/_partial/header.ejs
        // 'header' / 任意短名 → layout/_partial/header.ejs
        // 'post/date' / '_partial/post/date' → layout/_partial/post/date.ejs
        // 已经带 .ejs / .html 直接返回
        if p.hasSuffix(".ejs") || p.hasSuffix(".html") { return p }
        if p.hasPrefix("/") { return String(p.dropFirst()) + ".ejs" }
        let parts = p.split(separator: "/")
        if parts.first == "_partial" {
            return "layout/" + p + ".ejs"
        }
        if parts.first == "partial" {
            // partial/header → layout/_partial/header.ejs
            return "layout/_partial/" + parts.dropFirst().joined(separator: "/") + ".ejs"
        }
        // 'post/date' (无前缀) 默认看作 _partial 子目录
        if parts.count > 1 {
            return "layout/_partial/" + p + ".ejs"
        }
        // 默认: 假设是 _partial/xxx
        return "layout/_partial/" + p + ".ejs"
    }

    // MARK: - call matching

    /// 匹配: name('arg') 或 name("arg")
    private func matchCall(name: String, raw: String) -> String? {
        let pattern = "^\(name)\\(\\s*['\"]([^'\"]*)['\"]\\s*\\)\\s*$"
        guard let r = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = raw as NSString
        let range = NSRange(location: 0, length: ns.length)
        if let m = r.firstMatch(in: raw, range: range) {
            return ns.substring(with: m.range(at: 1))
        }
        return nil
    }

    /// 匹配: name('arg', { ... })  注: { ... } 内部可含括号
    private func matchCallWithObject(name: String, raw: String) -> (String, String)? {
        // 找到 name( 然后定位第一个 "{" 与对应的 "}"
        guard raw.hasPrefix("\(name)(") else { return nil }
        let innerStart = raw.index(raw.startIndex, offsetBy: name.count + 1)  // 跳过 "name("
        // 在 innerStart 之后找第一个 "{" 前的字符串(可能含 'name' 或 "name")
        guard let brace = raw[innerStart...].firstIndex(of: "{") else { return nil }
        // 在 brace 之前的部分 找 '...' 或 "..."
        let beforeBrace = String(raw[innerStart..<brace])
        // 切分: 第一个字符串字面量 + 逗号 + 空白
        let pattern = "^\\s*['\"]([^'\"]*)['\"]\\s*,\\s*$"
        guard let r = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = beforeBrace as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let m = r.firstMatch(in: beforeBrace, range: range) else { return nil }
        let nameStr = ns.substring(with: m.range(at: 1))
        // 找匹配的 "}"
        if let close = matchObjectClose(raw, openAt: brace) {
            let objStr = String(raw[brace...close])
            return (nameStr, objStr)
        }
        return nil
    }

    private func matchObjectClose(_ s: String, openAt: String.Index) -> String.Index? {
        var depth = 1
        var inStr: Character? = nil
        var i = s.index(after: openAt)
        while i < s.endIndex {
            let c = s[i]
            if let q = inStr {
                if c == q { inStr = nil }
            } else {
                if c == "'" || c == "\"" { inStr = c }
                else if c == "{" { depth += 1 }
                else if c == "}" {
                    depth -= 1
                    if depth == 0 { return i }
                }
            }
            i = s.index(after: i)
        }
        return nil
    }

    private func stripQuotes(_ s: String) -> String {
        if s.count >= 2, (s.first == "'" || s.first == "\""), s.last == s.first {
            return String(s.dropFirst().dropLast())
        }
        return s
    }

    private func stripIfHead(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("if ") { t = String(t.dropFirst(3)) }
        else if t.hasPrefix("if(") {
            t = String(t.dropFirst(3))
            if t.hasSuffix(")") { t = String(t.dropLast()) }
        } else if t == "if" { return "true" }
        // 去掉结尾可能的 " {"
        if let brace = t.firstIndex(of: "{") {
            t = String(t[..<brace])
        }
        return t.trimmingCharacters(in: .whitespaces)
    }

    /// 从 `function(a,b){...}` / `(a,b)=>...` 中提取函数体
    private func stripFnBody(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        // 去掉前缀 `function...{`
        if t.hasPrefix("function") {
            if let brace = t.firstIndex(of: "{") {
                t = String(t[brace...])
            }
        }
        // 去掉 `=>` 箭头
        if let arrow = t.range(of: "=>") {
            t = String(t[arrow.upperBound...])
        }
        // 去掉包裹的 () (无参)
        if t.hasPrefix("()") { t = String(t.dropFirst(2)) }
        // 提取 {...} - 取首个 { 到 最后一个 }
        if t.hasPrefix("{") {
            // 找匹配最深层的 }
            if let close = matchBracket(t, openIdx: t.startIndex) {
                t = String(t[t.index(after: t.startIndex)..<close])
            }
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 在数组上跑 callback (支持 item, i, arr 参数)
    private func runCallbackOnArray(arr: [Any], body: String, ctx: inout EJSContext, currentPath: String) {
        for (idx, item) in arr.enumerated() {
            var scope: [String: Any] = ["item": item, "i": idx, "index": idx, "post": item, "widget": item]
            // 如果 item 是 dict, 展开
            if let d = item as? [String: Any] {
                for (k, v) in d { scope[k] = v }
            }
            ctx.pushScope(scope)
            // 包裹 body 成合法的 EJS 文本, 然后用 runStatements
            let wrapped = wrapAsEJSScript(body)
            _ = runInlineStatements(wrapped, ctx: &ctx, currentPath: currentPath)
            ctx.popScope()
        }
    }

    /// 把函数体包裹成合法的 EJS 脚本, 让 tokenize 能识别 include/partial 等
    /// 例如 `% include 'x' %` → `<% include 'x' %>`
    /// 例如 `var x = 1` → `<% var x = 1 %>`
    private func wrapAsEJSScript(_ body: String) -> String {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        // 已经有完整 EJS 标记, 不处理
        if trimmed.contains("<%") { return body }
        // 如果整段是单条 EJS 表达式 (用 %...% 包裹), 直接补全
        if trimmed.hasPrefix("%") && trimmed.hasSuffix("%") {
            // 可能是 % include 'x' % 或 %= value % 等
            let inner = String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
            if inner.hasPrefix("=") || inner.hasPrefix("include") || inner.hasPrefix("partial") || inner.hasPrefix("if") || inner.hasPrefix("for") || inner.hasPrefix("var") || inner.hasPrefix("let") || inner.hasPrefix("const") || inner.hasPrefix("layout") {
                return "<% \(inner) %>"
            }
            return "<% \(inner) %>"
        }
        // 多行: 简单 wrap 为 EJS 脚本
        return "<% " + body + " %>"
    }

    /// 内联语句执行 (forEach callback body, 类似 EJS 顶层但没有 layout/include 引用)
    private func runInlineStatements(_ text: String, ctx: inout EJSContext, currentPath: String) -> String {
        let blocks = tokenize(text)
        return runStatements(blocks, ctx: &ctx, currentPath: currentPath)
    }

    private func stripForHead(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("for ") { t = String(t.dropFirst(4)) }
        else if t.hasPrefix("for(") {
            t = String(t.dropFirst(4))
            if t.hasSuffix(")") { t = String(t.dropLast()) }
        }
        if let brace = t.firstIndex(of: "{") {
            t = String(t[..<brace])
        }
        return t.trimmingCharacters(in: .whitespaces)
    }

    private func stripWhileHead(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("while ") { t = String(t.dropFirst(6)) }
        else if t.hasPrefix("while(") {
            t = String(t.dropFirst(6))
            if t.hasSuffix(")") { t = String(t.dropLast()) }
        }
        if let brace = t.firstIndex(of: "{") {
            t = String(t[..<brace])
        }
        return t.trimmingCharacters(in: .whitespaces)
    }

    private struct ForHeader {
        let varName: String
        let listExpr: String
    }

    private func parseForHeader(_ s: String) -> ForHeader {
        // 形如: post of page.posts   /   post in posts   /   (post of page.posts)   /   var post in posts
        var t = s.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("(") && t.hasSuffix(")") { t = String(t.dropFirst().dropLast()) }
        t = t.trimmingCharacters(in: .whitespaces)
        // 找 in / of
        let parts = t.split(whereSeparator: { $0 == " " }).map(String.init)
        var idx = -1
        for (i, p) in parts.enumerated() {
            if p == "in" || p == "of" { idx = i; break }
        }
        guard idx > 0, idx < parts.count - 1 else { return ForHeader(varName: "", listExpr: "") }
        // varName 可能在 idx-1 (排除 let/var/const)
        var varIdx = idx - 1
        while varIdx >= 0 {
            let p = parts[varIdx]
            if p != "let" && p != "var" && p != "const" { break }
            varIdx -= 1
        }
        guard varIdx >= 0 else { return ForHeader(varName: "", listExpr: "") }
        let varName = parts[varIdx]
        let listExpr = parts[(idx + 1)...].joined(separator: " ")
        return ForHeader(varName: varName, listExpr: listExpr)
    }

    // MARK: - Expression evaluation

    public func eval(_ expr: String, ctx: inout EJSContext) -> Any? {
        var s = expr.trimmingCharacters(in: .whitespaces)
        // view 过滤器链: expr | filter1 | filter2(arg) ...  (仅当不在字符串/括号/对象内部时切分)
        let filterSplit = splitTopLevelPipe(s)
        if filterSplit.count > 1 {
            // 第一段: 切到第一个 `|` 之前
            let head = String(filterSplit[0]).trimmingCharacters(in: .whitespaces)
            var val: Any? = eval(head, ctx: &ctx)
            for piece in filterSplit.dropFirst() {
                let p = String(piece).trimmingCharacters(in: .whitespaces)
                if p.isEmpty { continue }
                // 支持 filter / filter(arg)
                if let r = p.range(of: "(") {
                    let fn = String(p[..<r.lowerBound]).trimmingCharacters(in: .whitespaces)
                    if let close = matchBracket(p, openIdx: r.lowerBound) {
                        let argStr = String(p[r.upperBound..<close]).trimmingCharacters(in: .whitespaces)
                        // 包装 value 为第一个参数
                        let allArgs = splitCommaTopLevel(argStr)
                        var newArgs: [String] = [encodeArgForCall(val)]
                        for a in allArgs { newArgs.append(a) }
                        val = callFunction(name: fn, argString: newArgs.joined(separator: ", "), ctx: &ctx)
                    }
                } else {
                    val = callFunctionSingleArg(name: p, value: val, ctx: &ctx)
                }
            }
            return val
        }
        // 括号包裹: (expr)
        if s.hasPrefix("(") && s.hasSuffix(")") {
            var depth = 0
            var balanced = true
            var inStr: Character? = nil
            for (idx, c) in s.enumerated() {
                if let q = inStr {
                    if c == q { inStr = nil }
                } else {
                    if c == "'" || c == "\"" { inStr = c }
                    else if c == "(" { depth += 1 }
                    else if c == ")" { depth -= 1; if depth == 0 && idx < s.count - 1 { balanced = false; break } }
                }
            }
            if balanced {
                let inner = String(s.dropFirst().dropLast())
                return eval(inner, ctx: &ctx)
            }
        }
        if s.isEmpty { return nil }
        // 字面量
        if s == "true" { return true }
        if s == "false" { return false }
        if s == "null" || s == "undefined" { return nil }
        if let i = Int(s) { return i }
        if let d = Double(s) { return d }
        // 纯字符串字面量: 以 ' 或 " 包裹, 且内部不包含顶层运算符/函数调用
        if (s.hasPrefix("'") && s.hasSuffix("'") && s.count >= 2) ||
           (s.hasPrefix("\"") && s.hasSuffix("\"") && s.count >= 2) {
            // 检查内部是否包含顶层运算符/标识符
            if !s.contains("+") && !s.contains("(") && !s.contains("?") {
                return stripQuotes(s)
            }
            // 包含运算符: 走 evalComplex (例如 'foo' + bar)
        }
        if s.hasPrefix("[") { return evalArrayLiteral(s, ctx: &ctx) }
        if s.hasPrefix("{") { return evalObjectLiteral(s, ctx: &ctx) }
        // 优先尝试简单 path (a.b.c)
        if !s.contains("(") && !s.contains("+") && !s.contains("==") && !s.contains("!=") && !s.contains("?") && !s.contains("&&") && !s.contains("||") {
            return evalPath(s, ctx: &ctx)
        }
        // path + 方法调用链: a.b().c()[0]  →  委托给 evalPath (tokenizePath 已处理 methodCall)
        if s.contains("(") && !s.contains("==") && !s.contains("!=") && !s.contains("?") && !s.contains("&&") && !s.contains("||") && !s.contains("+") {
            // 找第一个非方法调用的 top-level 函数调用 (即名字在 " / 字母 起始且无 '...' 包裹)
            // 简单判断: 第一个 '(' 前是 identifier (没有 ' or " or [ or {), 那这就是函数调用
            // 但如果名字包含 '.', 那就是 path+method, 走 evalPath
            if let r = s.range(of: "(") {
                let before = String(s[s.startIndex..<r.lowerBound])
                if before.contains(".") {
                    return evalPath(s, ctx: &ctx)
                }
            }
        }
        return evalComplex(s, ctx: &ctx)
    }

    private func evalComplex(_ expr: String, ctx: inout EJSContext) -> Any? {
        var s = expr.trimmingCharacters(in: .whitespaces)
        // 三元 ? :
        if let r = splitTopLevel(s, sep: "?") {
            let condStr = String(s[s.startIndex..<r.lowerBound]).trimmingCharacters(in: .whitespaces)
            let cond = evalComplex(condStr, ctx: &ctx)
            if isTruthy(cond) {
                let right = String(s[r.upperBound..<s.endIndex]).trimmingCharacters(in: .whitespaces)
                // 在 right 里找顶层的 ":"
                if let colon = splitTopLevel(right, sep: ":") {
                    return evalComplex(String(right[right.startIndex..<colon.lowerBound]).trimmingCharacters(in: .whitespaces), ctx: &ctx)
                }
                return evalComplex(right, ctx: &ctx)
            } else {
                let right = String(s[r.upperBound..<s.endIndex]).trimmingCharacters(in: .whitespaces)
                if let colon = splitTopLevel(right, sep: ":") {
                    return evalComplex(String(right[colon.upperBound..<right.endIndex]).trimmingCharacters(in: .whitespaces), ctx: &ctx)
                }
                return nil
            }
        }
        // ||
        if let r = splitTopLevel(s, sep: "||") {
            let l = evalComplex(String(s[s.startIndex..<r.lowerBound]).trimmingCharacters(in: .whitespaces), ctx: &ctx)
            if isTruthy(l) { return l }
            return evalComplex(String(s[r.upperBound..<s.endIndex]).trimmingCharacters(in: .whitespaces), ctx: &ctx)
        }
        // &&
        if let r = splitTopLevel(s, sep: "&&") {
            let l = evalComplex(String(s[s.startIndex..<r.lowerBound]).trimmingCharacters(in: .whitespaces), ctx: &ctx)
            if !isTruthy(l) { return l }
            return evalComplex(String(s[r.upperBound..<s.endIndex]).trimmingCharacters(in: .whitespaces), ctx: &ctx)
        }
        // 比较运算符 (>=, <=, >, <) - 必须在 == 之前匹配
        if let r = splitTopLevel(s, sep: ">=") {
            let l = evalComplex(String(s[s.startIndex..<r.lowerBound]).trimmingCharacters(in: .whitespaces), ctx: &ctx)
            let rr = evalComplex(String(s[r.upperBound..<s.endIndex]).trimmingCharacters(in: .whitespaces), ctx: &ctx)
            return numberize(l) >= numberize(rr)
        }
        if let r = splitTopLevel(s, sep: "<=") {
            let l = evalComplex(String(s[s.startIndex..<r.lowerBound]).trimmingCharacters(in: .whitespaces), ctx: &ctx)
            let rr = evalComplex(String(s[r.upperBound..<s.endIndex]).trimmingCharacters(in: .whitespaces), ctx: &ctx)
            return numberize(l) <= numberize(rr)
        }
        if let r = splitTopLevel(s, sep: ">") {
            // 确保不是 => (arrow) 或 >= (已处理), 但 splitTopLevel 会找到第一个 >, 所以这里只匹配纯 >
            // 检查这个 > 前面不是 =
            let before = s.index(before: r.lowerBound)
            if before >= s.startIndex && s[before] != "=" {
                let l = evalComplex(String(s[s.startIndex..<r.lowerBound]).trimmingCharacters(in: .whitespaces), ctx: &ctx)
                let rr = evalComplex(String(s[r.upperBound..<s.endIndex]).trimmingCharacters(in: .whitespaces), ctx: &ctx)
                return numberize(l) > numberize(rr)
            }
        }
        if let r = splitTopLevel(s, sep: "<") {
            // splitTopLevel 会找到第一个 <, 但要注意 < 不应与 =/< 冲突
            let l = evalComplex(String(s[s.startIndex..<r.lowerBound]).trimmingCharacters(in: .whitespaces), ctx: &ctx)
            let rr = evalComplex(String(s[r.upperBound..<s.endIndex]).trimmingCharacters(in: .whitespaces), ctx: &ctx)
            return numberize(l) < numberize(rr)
        }
        // ===
        if let r = splitTopLevel(s, sep: "===") {
            let l = evalComplex(String(s[s.startIndex..<r.lowerBound]).trimmingCharacters(in: .whitespaces), ctx: &ctx)
            let rr = evalComplex(String(s[r.upperBound..<s.endIndex]).trimmingCharacters(in: .whitespaces), ctx: &ctx)
            return deepEqual(l, rr)
        }
        // ==
        if let r = splitTopLevel(s, sep: "==") {
            let l = evalComplex(String(s[s.startIndex..<r.lowerBound]).trimmingCharacters(in: .whitespaces), ctx: &ctx)
            let rr = evalComplex(String(s[r.upperBound..<s.endIndex]).trimmingCharacters(in: .whitespaces), ctx: &ctx)
            return deepEqual(l, rr)
        }
        // !==
        if let r = splitTopLevel(s, sep: "!==") {
            let l = evalComplex(String(s[s.startIndex..<r.lowerBound]).trimmingCharacters(in: .whitespaces), ctx: &ctx)
            let rr = evalComplex(String(s[r.upperBound..<s.endIndex]).trimmingCharacters(in: .whitespaces), ctx: &ctx)
            return !deepEqual(l, rr)
        }
        // !=
        if let r = splitTopLevel(s, sep: "!=") {
            let l = evalComplex(String(s[s.startIndex..<r.lowerBound]).trimmingCharacters(in: .whitespaces), ctx: &ctx)
            let rr = evalComplex(String(s[r.upperBound..<s.endIndex]).trimmingCharacters(in: .whitespaces), ctx: &ctx)
            return !deepEqual(l, rr)
        }
        // +
        if let r = splitTopLevel(s, sep: "+") {
            // 用 eval (而非 evalComplex) 递归, 让字符串字面量快路径生效
            let l = eval(String(s[s.startIndex..<r.lowerBound]).trimmingCharacters(in: .whitespaces), ctx: &ctx)
            let rr = eval(String(s[r.upperBound..<s.endIndex]).trimmingCharacters(in: .whitespaces), ctx: &ctx)
            if let ls = l as? String, let rs = rr as? String { return ls + rs }
            if let ls = l as? Int, let rs = rr as? Int { return ls + rs }
            return stringify(l) + stringify(rr)
        }
        // ! (前缀)
        if s.hasPrefix("!") {
            return !isTruthy(evalComplex(String(s.dropFirst()).trimmingCharacters(in: .whitespaces), ctx: &ctx))
        }
        // 函数调用
        if let r = s.range(of: "(") {
            // 找匹配的 )
            if let close = matchBracket(s, openIdx: r.lowerBound) {
                let fn = String(s[s.startIndex..<r.lowerBound]).trimmingCharacters(in: .whitespaces)
                let argStr = String(s[r.upperBound..<close]).trimmingCharacters(in: .whitespaces)
                return callFunction(name: fn, argString: argStr, ctx: &ctx)
            }
        }
        return evalPath(s, ctx: &ctx)
    }

    private func splitTopLevel(_ s: String, sep: String) -> Range<String.Index>? {
        var depth = 0
        var inStr: Character? = nil
        let chars = Array(s)
        var k = 0
        while k < chars.count {
            let c = chars[k]
            if let q = inStr {
                if c == q { inStr = nil }
            } else {
                if c == "'" || c == "\"" { inStr = c }
                else if c == "(" || c == "[" || c == "{" { depth += 1 }
                else if c == ")" || c == "]" || c == "}" { depth -= 1 }
                else if depth == 0 {
                    let sIdx = s.index(s.startIndex, offsetBy: k)
                    if s.distance(from: sIdx, to: s.endIndex) >= sep.count {
                        let endIdx = s.index(sIdx, offsetBy: sep.count)
                        if String(s[sIdx..<endIdx]) == sep {
                            return sIdx..<endIdx
                        }
                    }
                }
            }
            k += 1
        }
        return nil
    }

    private func matchBracket(_ s: String, openIdx: String.Index) -> String.Index? {
        var depth = 1
        var inStr: Character? = nil
        var i = s.index(after: openIdx)
        while i < s.endIndex {
            let c = s[i]
            if let q = inStr {
                if c == q { inStr = nil }
            } else {
                if c == "'" || c == "\"" { inStr = c }
                else if c == "(" { depth += 1 }
                else if c == ")" {
                    depth -= 1
                    if depth == 0 { return i }
                }
            }
            i = s.index(after: i)
        }
        return nil
    }

    /// 按顶层 `|` 切分(忽略字符串内/括号内的)
    private func splitTopLevelPipe(_ s: String) -> [Substring] {
        var out: [Substring] = []
        var depth = 0
        var inStr: Character? = nil
        var start = s.startIndex
        for i in s.indices {
            let c = s[i]
            if let q = inStr {
                if c == q { inStr = nil }
            } else {
                if c == "'" || c == "\"" { inStr = c }
                else if c == "(" || c == "[" || c == "{" { depth += 1 }
                else if c == ")" || c == "]" || c == "}" { depth -= 1 }
                else if c == "|" && depth == 0 {
                    out.append(s[start..<i])
                    start = s.index(after: i)
                }
            }
        }
        if start <= s.endIndex { out.append(s[start..<s.endIndex]) }
        return out
    }

    private func evalPath(_ s: String, ctx: inout EJSContext) -> Any? {
        let path = s.trimmingCharacters(in: .whitespaces)
        if path.isEmpty { return nil }
        // 全局 this / locals (alias)
        if path == "this" || path == "locals" { return ctx.mergedTop() }
        var current: Any? = ctx.mergedTop()
        // 用正则 / 简单字符切分, 支持 a.b.c[0].d.e[1]
        let tokens = tokenizePath(path)
        for tk in tokens {
            switch tk {
            case .key(let k):
                if k == "length" {
                    // .length 属性: 数组/字符串/字典的长度
                    if let s = current as? String { current = s.count }
                    else if let a = current as? [Any] { current = a.count }
                    else if let a = current as? [Any?] { current = a.count }
                    else if let a = current as? [String] { current = a.count }
                    else if let d = current as? [String: Any] { current = d.count }
                    else if let d = current as? [String: String] { current = d.count }
                    else { current = 0 }
                } else if let d = current as? [String: Any] {
                    current = d[k]
                } else if let d = current as? [String: String] {
                    current = d[k]
                } else if let a = current as? [Any], let idx = Int(k), idx >= 0, idx < a.count {
                    current = a[idx]
                } else if current == nil {
                    return nil
                } else {
                    return nil
                }
            case .index(let i):
                if let a = current as? [Any] {
                    if i >= 0 && i < a.count { current = a[i] } else { return nil }
                } else if let a = current as? [Any?] {
                    if i >= 0 && i < a.count { current = a[i] } else { return nil }
                } else {
                    return nil
                }
            case .methodCall(let name, let rawArgs):
                // 数组/字典/字符串/Date 上的 JS-like 方法调用
                let argValues: [Any?] = rawArgs.map { a in
                    return eval(a.trimmingCharacters(in: .whitespaces), ctx: &ctx) ?? NSNull()
                }
                if let arr = current as? [Any] {
                    switch name {
                    case "forEach", "each":
                        // forEach(callback(item, i, arr))  /  each(function(item){...})
                        if let cb = argValues.first as? String {
                            let body = stripFnBody(cb)
                            runCallbackOnArray(arr: arr, body: body, ctx: &ctx, currentPath: "")
                        }
                        current = nil
                    case "map":
                        if let cb = argValues.first as? String {
                            let body = stripFnBody(cb)
                            current = arr.map { item -> Any in
                                var c2 = ctx
                                c2.pushScope(["item": item])
                                let v = eval(body, ctx: &c2)
                                c2.popScope()
                                return v ?? NSNull()
                            }
                        } else { current = arr }
                    case "filter":
                        if let cb = argValues.first as? String {
                            let body = stripFnBody(cb)
                            current = arr.filter { item in
                                var c2 = ctx
                                c2.pushScope(["item": item])
                                let v = eval(body, ctx: &c2)
                                c2.popScope()
                                return isTruthy(v)
                            }
                        } else { current = arr }
                    case "indexOf":
                        if let target = argValues.first {
                            if let s = target as? String {
                                if let arr2 = arr as? [String] { return arr2.firstIndex(of: s) ?? -1 }
                            }
                            for (idx, it) in arr.enumerated() {
                                if deepEqual(it, target) { return idx }
                            }
                        }
                        return -1
                    case "sort":
                        // sort() 按字符串排序, sort(fn) 用 fn 比较
                        if let cb = argValues.first as? String {
                            let body = stripFnBody(cb)
                            current = arr.sorted { a, b in
                                var c2 = ctx
                                c2.pushScope(["a": a, "b": b])
                                let v = eval(body, ctx: &c2)
                                c2.popScope()
                                if let n = v as? Int { return n < 0 }
                                if let n = v as? Double { return n < 0 }
                                return false
                            }
                        } else {
                            current = arr.sorted { (a, b) in stringify(a) < stringify(b) }
                        }
                    case "slice":
                        let start = (argValues.first as? Int) ?? 0
                        let end = (argValues.count > 1 ? (argValues[1] as? Int) : nil) ?? arr.count
                        current = Array(arr[start..<min(end, arr.count)])
                    case "join":
                        let sep = (argValues.first as? String) ?? ","
                        current = arr.map { stringify($0) }.joined(separator: sep)
                    case "concat":
                        if let other = argValues.first as? [Any] {
                            current = arr + other
                        } else { current = arr }
                    case "first":
                        current = arr.first
                    case "last":
                        current = arr.last
                    default:
                        return nil
                    }
                } else if let s = current as? String {
                    switch name {
                    case "toUpperCase", "upper":
                        current = s.uppercased()
                    case "toLowerCase", "lower":
                        current = s.lowercased()
                    case "trim":
                        current = s.trimmingCharacters(in: .whitespacesAndNewlines)
                    case "length":
                        current = s.count
                    case "replace":
                        if argValues.count >= 2, let from = argValues[0] as? String, let to = argValues[1] as? String {
                            current = s.replacingOccurrences(of: from, with: to)
                        }
                    case "split":
                        let sep = (argValues.first as? String) ?? ","
                        current = s.components(separatedBy: sep)
                    case "indexOf":
                        if let target = argValues.first as? String {
                            if let i = s.range(of: target) { return s.distance(from: s.startIndex, to: i.lowerBound) }
                        }
                        return -1
                    case "substring", "substr":
                        let start = (argValues.first as? Int) ?? 0
                        if argValues.count > 1, let len = argValues[1] as? Int {
                            let i = s.index(s.startIndex, offsetBy: max(0, start))
                            let j = s.index(i, offsetBy: min(len, s.count - start))
                            current = String(s[i..<j])
                        } else {
                            let i = s.index(s.startIndex, offsetBy: max(0, start))
                            current = String(s[i...])
                        }
                    default:
                        return nil
                    }
                } else if let d = current as? Date {
                    let cal = Calendar.current
                    let comps = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: d)
                    switch name {
                    case "year": current = comps.year ?? 1970
                    case "month": current = comps.month ?? 1
                    case "date", "day": current = comps.day ?? 1
                    case "hour": current = comps.hour ?? 0
                    case "minute": current = comps.minute ?? 0
                    case "second": current = comps.second ?? 0
                    default: return nil
                    }
                } else {
                    return nil
                }
            case .varKey(let vname):
                // 变量作为索引: 查 ctx (优先 stack, 后 userContext)
                if let key = ctx.userContext[vname] as? String {
                    if let d = current as? [String: Any] { current = d[key] }
                    else if let d = current as? [String: String] { current = d[key] }
                    else { return nil }
                } else if let key = ctx.userContext[vname] as? Int {
                    if let a = current as? [Any] {
                        if key >= 0 && key < a.count { current = a[key] } else { return nil }
                    } else { return nil }
                } else {
                    // 查 stack
                    var found: Any? = nil
                    for s in ctx.stack.reversed() {
                        if let v = s[vname] { found = v; break }
                    }
                    if let key = found as? String {
                        if let d = current as? [String: Any] { current = d[key] }
                        else if let d = current as? [String: String] { current = d[key] }
                        else { return nil }
                    } else {
                        return nil
                    }
                }
            }
        }
        return current
    }

    private enum PathToken {
        case key(String)
        case index(Int)
        case varKey(String)
        case methodCall(String, [String])  // name, rawArgs
    }

    private func tokenizePath(_ s: String) -> [PathToken] {
        var tokens: [PathToken] = []
        var i = s.startIndex
        var current = ""
        while i < s.endIndex {
            let c = s[i]
            if c == "." {
                if !current.isEmpty {
                    tokens.append(.key(current))
                    current = ""
                }
            } else if c == "(" {
                // 方法调用: 在前一个 token 上附加 methodCall
                if !current.isEmpty {
                    // 找匹配的 )
                    if let close = matchBracket(s, openIdx: i) {
                        let argStr = String(s[s.index(after: i)..<close])
                        let args = splitCommaTopLevel(argStr)
                        // 把当前累积的名字视为 method name
                        // 实际是: 前面有 .key(name), 然后 (args)
                        // 把上一个 .key 改为 methodCall
                        if case .key(let kn) = tokens.last {
                            tokens.removeLast()
                            tokens.append(.methodCall(kn, args))
                        } else {
                            // 直接是 methodName(args) — receiver 是顶层
                            tokens.append(.methodCall(current, args))
                        }
                        current = ""
                        i = s.index(after: close)
                        continue
                    }
                }
            } else if c == "[" {
                if !current.isEmpty {
                    tokens.append(.key(current))
                    current = ""
                }
                // 找匹配的 ]
                if let close = s[i...].firstIndex(of: "]") {
                    let inner = String(s[s.index(after: i)..<close])
                    if let idx = Int(inner) {
                        tokens.append(.index(idx))
                    } else if (inner.hasPrefix("'") && inner.hasSuffix("'")) || (inner.hasPrefix("\"") && inner.hasSuffix("\"")) {
                        let k = String(inner.dropFirst().dropLast())
                        tokens.append(.key(k))
                    } else {
                        // 变量: 标记为 varIndex, 之后单独解析
                        tokens.append(.varKey(inner))
                    }
                    i = s.index(after: close)
                    continue
                }
            } else {
                current.append(c)
            }
            i = s.index(after: i)
        }
        if !current.isEmpty {
            tokens.append(.key(current))
        }
        return tokens
    }

    private func evalArrayLiteral(_ s: String, ctx: inout EJSContext) -> [Any] {
        var inner = s.trimmingCharacters(in: .whitespaces)
        if inner.hasPrefix("[") { inner = String(inner.dropFirst()) }
        if inner.hasSuffix("]") { inner = String(inner.dropLast()) }
        let parts = splitCommaTopLevel(inner)
        return parts.map { p -> Any in
            let v = eval(p.trimmingCharacters(in: .whitespaces), ctx: &ctx)
            return v ?? NSNull()
        }
    }

    public func evalObjectLiteral(_ s: String, ctx: inout EJSContext) -> [String: Any] {
        var inner = s.trimmingCharacters(in: .whitespaces)
        if inner.hasPrefix("{") { inner = String(inner.dropFirst()) }
        if inner.hasSuffix("}") { inner = String(inner.dropLast()) }
        let parts = splitCommaTopLevel(inner)
        var out: [String: Any] = [:]
        for p in parts {
            // 形如 key: value 或 'key': value
            if let r = p.range(of: ":") {
                var k = String(p[..<r.lowerBound]).trimmingCharacters(in: .whitespaces)
                if (k.hasPrefix("'") && k.hasSuffix("'")) || (k.hasPrefix("\"") && k.hasSuffix("\"")) {
                    k = stripQuotes(k)
                }
                let v = eval(String(p[r.upperBound...]).trimmingCharacters(in: .whitespaces), ctx: &ctx)
                out[k] = v ?? NSNull()
            }
        }
        return out
    }

    private func splitCommaTopLevel(_ s: String) -> [String] {
        var out: [String] = []
        var depth = 0
        var inStr: Character? = nil
        var start = s.startIndex
        for i in s.indices {
            let c = s[i]
            if let q = inStr {
                if c == q { inStr = nil }
            } else {
                if c == "'" || c == "\"" { inStr = c }
                else if c == "(" || c == "[" || c == "{" { depth += 1 }
                else if c == ")" || c == "]" || c == "}" { depth -= 1 }
                else if c == "," && depth == 0 {
                    out.append(String(s[start..<i]))
                    start = s.index(after: i)
                }
            }
        }
        if start < s.endIndex { out.append(String(s[start..<s.endIndex])) }
        return out
    }

    private func evalList(_ expr: String, ctx: inout EJSContext) -> [Any] {
        let v = eval(expr, ctx: &ctx)
        if let a = v as? [Any] { return a }
        if let a = v as? [Any?] { return a.compactMap { $0 } }
        if let a = v as? [String] { return a }
        if let a = v as? [String: Any] { return a.map { $0.key } }
        if let a = v as? [String: String] { return a.map { $0.key } }
        if let a = v as? [String: AnyHashable] { return a.map { $0.key } }
        if let a = v as? [String: Int] { return a.map { $0.key } }
        if let s = v as? String { return [s] }
        return []
    }

    // MARK: - callFunction

    /// 把 Any 值编码为可被 callFunction 解析的字符串
    private func encodeArgForCall(_ v: Any?) -> String {
        if v == nil { return "null" }
        if v is NSNull { return "null" }
        if let date = v as? Date {
            let fmt = ISO8601DateFormatter()
            return "__date_" + fmt.string(from: date) + "__"
        }
        if let b = v as? Bool { return b ? "true" : "false" }
        if let i = v as? Int { return String(i) }
        if let d = v as? Double { return String(d) }
        // 字符串: 用单引号包裹 (内部 ' 转义为 \')
        if let s = v as? String {
            let escaped = s.replacingOccurrences(of: "'", with: "\\'")
            return "'" + escaped + "'"
        }
        return stringify(v)
    }

    /// 直接传一个 value 作为第一个参数给函数(避免 stringify 丢失 Date 等)
    private func callFunctionSingleArg(name: String, value: Any?, ctx: inout EJSContext) -> Any? {
        let argString = encodeArgForCall(value)
        return callFunction(name: name, argString: argString, ctx: &ctx)
    }

    private func callFunction(name: String, argString: String, ctx: inout EJSContext) -> Any? {
        let args: [Any?] = splitCommaTopLevel(argString).map { arg in
            let trimmed = arg.trimmingCharacters(in: .whitespaces)
            // __date_<iso>__  → Date 反序列化 (view filter 链)
            if trimmed.hasPrefix("__date_") && trimmed.hasSuffix("__") {
                let inner = String(trimmed.dropFirst(7).dropLast(2))
                if let d = parseDateString(inner) { return d }
            }
            return self.eval(trimmed, ctx: &ctx)
        }
        switch name {
        // Hexo helpers
        case "css":
            if let s = args.first as? String { return "<link rel=\"stylesheet\" href=\"\(normalizeURL(s))\">" }
            return ""
        case "js":
            if let s = args.first as? String { return "<script src=\"\(normalizeURL(s))\"></script>" }
            return ""
        case "image_tag":
            if let s = args.first as? String { return "<img src=\"\(normalizeURL(s))\" alt=\"\(s)\">" }
            return ""
        case "link_to":
            if let path = args.first as? String {
                let text = (args.count > 1 ? (args[1] as? String ?? path) : path)
                return "<a href=\"\(normalizeURL(path))\">\(htmlEscape(text))</a>"
            }
            return ""
        case "is_home":
            return (ctx.userContext["__type__"] as? String) == "index"
        case "is_post":
            return (ctx.userContext["__type__"] as? String) == "post"
        case "is_page":
            return (ctx.userContext["__type__"] as? String) == "page"
        case "is_archive":
            return (ctx.userContext["__type__"] as? String) == "archive"
        case "is_tag":
            return (ctx.userContext["__type__"] as? String) == "tag"
        case "is_category":
            return (ctx.userContext["__type__"] as? String) == "category"
        case "is_home_or_archive":
            let t = ctx.userContext["__type__"] as? String ?? ""
            return t == "index" || t == "archive"
        case "date":
            // date(value, format) - 支持多参数
            let fmt = (args.count > 1 ? (args[1] as? String) : nil) ?? "yyyy-MM-dd HH:mm:ss"
            let formatter = DateFormatter()
            formatter.dateFormat = fmt
            formatter.locale = Locale(identifier: "en_US_POSIX")
            if let d = args.first as? Date {
                return formatter.string(from: d)
            }
            if let s = args.first as? String {
                if let d = parseDateString(s) { return formatter.string(from: d) }
            }
            return ""
        case "date_xml":
            // date_xml(d) - 返回 ISO8601 格式
            if let d = args.first as? Date {
                let fmt = ISO8601DateFormatter()
                return fmt.string(from: d)
            }
            if let s = args.first as? String {
                if let d = parseDateString(s) {
                    let fmt = ISO8601DateFormatter()
                    return fmt.string(from: d)
                }
            }
            return ""
        case "__":
            // i18n: __(key) - 从 __i18n__ 取对应翻译
            if let key = args.first as? String {
                if let i18n = ctx.userContext["__i18n__"] as? [String: Any],
                   let val = i18n[key] as? String {
                    return val
                }
                return key  // fallback 到原 key
            }
            return ""
        case "time_tag":
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            let s = (args.first as? String) ?? ""
            if let d = parseDateString(s) {
                let f2 = DateFormatter()
                f2.dateFormat = "yyyy-MM-dd"
                return "<time datetime=\"\(s)\">\(f2.string(from: d))</time>"
            }
            // 已经是 yyyy-MM-dd 形式
            let prefix = s.count >= 10 ? String(s.prefix(10)) : s
            return "<time datetime=\"\(prefix)\">\(prefix)</time>"
        case "strip_html":
            if let s = args.first as? String {
                return s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            }
            return ""
        case "truncate":
            if let s = args.first as? String {
                let len = (args.count > 1 ? (args[1] as? Int) : nil) ?? 150
                if s.count <= len { return s }
                return String(s.prefix(len)) + "…"
            }
            return ""
        case "word_count":
            if let s = args.first as? String {
                return s.split(whereSeparator: { $0.isWhitespace }).count
            }
            return 0
        // Hexo view filters
        case "upper":
            if let s = args.first as? String { return s.uppercased() }
            return stringify(args.first)
        case "lower":
            if let s = args.first as? String { return s.lowercased() }
            return stringify(args.first)
        case "titlecase":
            if let s = args.first as? String {
                return s.capitalized
            }
            return stringify(args.first)
        case "trim":
            if let s = args.first as? String { return s.trimmingCharacters(in: .whitespacesAndNewlines) }
            return stringify(args.first)
        case "length":
            if let s = args.first as? String { return s.count }
            if let a = args.first as? [Any] { return a.count }
            if let d = args.first as? [String: Any] { return d.count }
            return 0
        case "reverse":
            if let s = args.first as? String { return String(s.reversed()) }
            if let a = args.first as? [Any] { return a.reversed() }
            return args.first ?? NSNull()
        case "join":
            if let a = args.first as? [Any] {
                let sep = (args.count > 1 ? (args[1] as? String) : nil) ?? ","
                return a.map { stringify($0) }.joined(separator: sep)
            }
            return ""
        case "replace":
            if let s = args.first as? String {
                let from = (args.count > 1 ? (args[1] as? String) : nil) ?? ""
                let to = (args.count > 2 ? (args[2] as? String) : nil) ?? ""
                if from.isEmpty { return s }
                return s.replacingOccurrences(of: from, with: to)
            }
            return ""
        case "prepend":
            if let s = args.first as? String {
                let pre = (args.count > 1 ? (args[1] as? String) : nil) ?? ""
                return pre + s
            }
            return ""
        case "append":
            if let s = args.first as? String {
                let suf = (args.count > 1 ? (args[1] as? String) : nil) ?? ""
                return s + suf
            }
            return ""
        case "default":
            if args.first is NSNull || args.first == nil { return args.count > 1 ? stringify(args[1]) : "" }
            return stringify(args.first)
        case "escape":
            if let s = args.first as? String { return htmlEscape(s) }
            return stringify(args.first)
        case "e":
            if let s = args.first as? String { return htmlEscape(s) }
            return stringify(args.first)
        case "safe":
            // Hexo safe filter: 标记为安全(我们不做区分, 直接返回)
            return stringify(args.first)
        case "render":
            // 跳过 markdown 重新渲染(我们 content 已经是 HTML)
            if let s = args.first as? String, s.hasPrefix("&lt;") || s.contains("<") {
                return s  // 已经是 HTML
            }
            return stringify(args.first)
        case "markdown":
            // 已是 HTML, 直接返回
            return stringify(args.first)
        case "noControlChars":
            if let s = args.first as? String {
                return s.unicodeScalars.filter { $0.value > 31 || $0.value == 9 || $0.value == 10 || $0.value == 13 }.map { String($0) }.joined()
            }
            return stringify(args.first)
        case "slugify":
            if let s = args.first as? String { return Permalink.slugify(s) }
            return stringify(args.first)
        case "array":
            if let s = args.first as? String { return [s] }
            if let a = args.first as? [Any] { return a }
            return [stringify(args.first)]
        case "first":
            if let a = args.first as? [Any] { return a.first ?? NSNull() }
            if let s = args.first as? String { return String(s.first ?? " ") }
            return NSNull()
        case "last":
            if let a = args.first as? [Any] { return a.last ?? NSNull() }
            if let s = args.first as? String { return String(s.last ?? " ") }
            return NSNull()
        case "md5":
            if let s = args.first as? String {
                return md5Hex(s)
            }
            return ""
        case "list_categories":
            return renderListCategories(ctx: &ctx)
        case "list_tags":
            return renderListTags(ctx: &ctx)
        case "paginator":
            return renderPaginator(ctx: &ctx)
        case "tagcloud":
            return renderTagCloud(ctx: &ctx)
        case "getPosts":
            return ctx.userContext["posts"] ?? []
        case "escapeHTML":
            if let s = args.first as? String { return htmlEscape(s) }
            return ""
        case "url_for":
            if let s = args.first as? String { return normalizeURL(s) }
            return ""
        case "full_url":
            if let s = args.first as? String {
                let base = (ctx.userContext["url"] as? String) ?? (ctx.userContext["baseURL"] as? String) ?? ""
                return joinURL(base: base, path: s)
            }
            return ""
        case "trim":
            if let s = args.first as? String { return s.trimmingCharacters(in: .whitespacesAndNewlines) }
            return args.first ?? NSNull()
        case "String":
            if let s = args.first as? String { return s }
            return stringify(args.first)
        case "Number":
            if let s = args.first as? String, let n = Double(s) { return n }
            return args.first ?? NSNull()
        case "Array":
            return args
        case "JSON.stringify":
            if let v = args.first {
                if v is NSNull { return "null" }
                let opts: JSONSerialization.WritingOptions = [.fragmentsAllowed]
                if let data = try? JSONSerialization.data(withJSONObject: v, options: opts),
                   let str = String(data: data, encoding: .utf8) { return str }
            }
            return ""
        case "Date":
            return Date()
        case "getYear":
            return Calendar.current.component(.year, from: Date())
        case "escape":
            if let s = args.first as? String { return htmlEscape(s) }
            return ""
        case "list_tags":
            // list_tags(tags, options)  /  list_tags(options)
            return renderListTagsHelper(args: args, ctx: &ctx)
        case "list_categories":
            return renderListCategoriesHelper(args: args, ctx: &ctx)
        case "list_archives":
            return renderListArchivesHelper(args: args, ctx: &ctx)
        case "paginator":
            return renderPaginatorHelper(args: args, ctx: &ctx)
        case "tagcloud":
            return renderTagcloudHelper(ctx: &ctx)
        case "search_form":
            return renderSearchFormHelper(args: args, ctx: &ctx)
        case "open_graph":
            return renderOpenGraphHelper(args: args, ctx: &ctx)
        case "feed_tag":
            return renderFeedTagHelper(args: args, ctx: &ctx)
        case "favicon_tag":
            return renderFaviconTagHelper(args: args, ctx: &ctx)
        default:
            // 已知主题里的 helper 走 helpers dict
            if let fn = ctx.userContext[name] as? ([Any?]) -> Any {
                return fn(args)
            }
            warnings.append("未知函数: \(name)")
            return nil
        }
    }

    public func normalizeURLPublic(_ s: String) -> String { normalizeURL(s) }
    public func renderPlainText(_ s: String) -> String { s }
    private func normalizeURL(_ s: String) -> String {
        if s.hasPrefix("http") || s.hasPrefix("/") { return s }
        return "/" + s
    }

    private func joinURL(base: String, path: String) -> String {
        if path.hasPrefix("http") { return path }
        if path.hasPrefix("/") { return base + path }
        if base.hasSuffix("/") { return base + path }
        return base + "/" + path
    }

    // MARK: - Hexo helper 渲染

    private func renderListCategories(ctx: inout EJSContext) -> String {
        guard let cats = ctx.userContext["categories"] as? [[String: Any]] else { return "" }
        var out = "<ul class=\"category-list\">"
        for c in cats {
            let name = (c["name"] as? String) ?? ""
            let slug = (c["slug"] as? String) ?? name
            out += "<li><a href=\"/categories/\(slug)/\">\(htmlEscape(name))</a></li>"
        }
        out += "</ul>"
        return out
    }

    private func renderListTags(ctx: inout EJSContext) -> String {
        guard let tags = ctx.userContext["tags"] as? [[String: Any]] else { return "" }
        var out = "<ul class=\"tag-list\">"
        for t in tags {
            let name = (t["name"] as? String) ?? ""
            let slug = (t["slug"] as? String) ?? name
            out += "<li><a href=\"/tags/\(slug)/\">\(htmlEscape(name))</a></li>"
        }
        out += "</ul>"
        return out
    }

    private func renderPaginator(ctx: inout EJSContext) -> String {
        guard let p = ctx.userContext["pagination"] as? [String: Any] else { return "" }
        let total = (p["total"] as? Int) ?? 1
        let current = (p["page"] as? Int) ?? 1
        let prev = p["prev"] as? String
        let next = p["next"] as? String
        let base = (ctx.userContext["path"] as? String) ?? "/"
        var out = "<nav class=\"pagination\">"
        if let prevPath = prev {
            out += "<a class=\"prev\" href=\"\(normalizeURL("\(base == "/" ? "" : base)/\(prevPath)/"))\">←</a>"
        }
        out += "<span class=\"page-number\">\(current) / \(total)</span>"
        if let nextPath = next {
            out += "<a class=\"next\" href=\"\(normalizeURL("\(base == "/" ? "" : base)/\(nextPath)/"))\">→</a>"
        }
        out += "</nav>"
        return out
    }

    private func renderTagCloud(ctx: inout EJSContext) -> String {
        guard let tags = ctx.userContext["tags"] as? [[String: Any]] else { return "" }
        var out = "<div class=\"tag-cloud\">"
        for t in tags {
            let name = (t["name"] as? String) ?? ""
            let slug = (t["slug"] as? String) ?? name
            out += "<a href=\"/tags/\(slug)/\">\(htmlEscape(name))</a>"
        }
        out += "</div>"
        return out
    }

    // MARK: - Hexo 风格 helper (带参数)

    private func renderListTagsHelper(args: [Any?], ctx: inout EJSContext) -> String {
        // list_tags(tags, options) 或 list_tags(options)
        let tagsList: [String]
        let opts: [String: Any]
        if let a = args.first as? [String] {
            tagsList = a
            opts = (args.count > 1 ? (args[1] as? [String: Any]) : nil) ?? [:]
        } else if let a = args.first as? [Any] {
            tagsList = a.compactMap { $0 as? String }
            opts = (args.count > 1 ? (args[1] as? [String: Any]) : nil) ?? [:]
        } else {
            // 没有传 tag 列表, 用 site 全局 tags
            let site = (ctx.userContext["site"] as? [String: Any]) ?? [:]
            tagsList = (site["tags"] as? [String]) ?? []
            opts = [:]
        }
        let showCount = (opts["show_count"] as? Bool) ?? false
        let style = (opts["style"] as? String) ?? "list"
        let separator = (opts["separator"] as? String) ?? ", "
        let suffix = (opts["suffix"] as? String) ?? ""
        let transform = (opts["transform"] as? String)
        let amount = (opts["amount"] as? Int) ?? 0
        var limited = tagsList
        if amount > 0 && amount < limited.count { limited = Array(limited.prefix(amount)) }
        if style == "list" {
            var out = "<ul class=\"tag-list\">"
            for t in limited {
                let slug = Permalink.slugify(t)
                let count = showCount ? getTagCount(tag: t, ctx: ctx) : 0
                let cnt = showCount ? " (\(count))" : ""
                out += "<li><a href=\"/tags/\(slug)/\(suffix)\">\(htmlEscape(t))\(cnt)</a></li>"
            }
            out += "</ul>"
            return out
        } else {
            return limited.map { t in
                let slug = Permalink.slugify(t)
                return "<a href=\"/tags/\(slug)/\(suffix)\">\(htmlEscape(t))</a>"
            }.joined(separator: separator)
        }
    }

    private func renderListCategoriesHelper(args: [Any?], ctx: inout EJSContext) -> String {
        // list_categories(categories, options) 或 list_categories(options)
        var catsList: [String]
        let opts: [String: Any]
        if let a = args.first as? [String] {
            catsList = a
            opts = (args.count > 1 ? (args[1] as? [String: Any]) : nil) ?? [:]
        } else if let a = args.first as? [Any] {
            catsList = a.compactMap { $0 as? String }
            opts = (args.count > 1 ? (args[1] as? [String: Any]) : nil) ?? [:]
        } else {
            catsList = []
            opts = [:]
        }
        let showCount = (opts["show_count"] as? Bool) ?? false
        let style = (opts["style"] as? String) ?? "list"
        let separator = (opts["separator"] as? String) ?? ", "
        if style == "list" {
            var out = "<ul class=\"category-list\">"
            for c in catsList {
                let slug = Permalink.slugify(c)
                let cnt = showCount ? " (\(getCategoryCount(cat: c, ctx: ctx)))" : ""
                out += "<li><a href=\"/categories/\(slug)/\">\(htmlEscape(c))\(cnt)</a></li>"
            }
            out += "</ul>"
            return out
        } else {
            return catsList.map { c in
                let slug = Permalink.slugify(c)
                return "<a href=\"/categories/\(slug)/\">\(htmlEscape(c))</a>"
            }.joined(separator: separator)
        }
    }

    private func renderListArchivesHelper(args: [Any?], ctx: inout EJSContext) -> String {
        // list_archives(options) - 简单按年分组
        let opts = (args.first as? [String: Any]) ?? [:]
        let style = (opts["style"] as? String) ?? "list"
        let showCount = (opts["show_count"] as? Bool) ?? false
        let site = (ctx.userContext["site"] as? [String: Any]) ?? [:]
        let posts = (site["posts"] as? [[String: Any]]) ?? []
        if style == "list" {
            var out = "<ul class=\"archive-list\">"
            for p in posts {
                let title = (p["title"] as? String) ?? ""
                let path = (p["path"] as? String) ?? "#"
                let date = (p["date"] as? Date) ?? Date()
                let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
                let cnt = showCount ? "" : ""
                out += "<li><a href=\"\(normalizeURL(path))\">\(htmlEscape(title))</a><span>\(fmt.string(from: date))</span></li>"
            }
            out += "</ul>"
            return out
        }
        return ""
    }

    private func renderPaginatorHelper(args: [Any?], ctx: inout EJSContext) -> String {
        // paginator(options) - 从 options 取数据, 或从 ctx.userContext.pagination
        let opts = (args.first as? [String: Any]) ?? ctx.userContext["pagination"] as? [String: Any] ?? [:]
        let total = (opts["total"] as? Int) ?? 1
        let current = (opts["current"] as? Int) ?? (opts["page"] as? Int) ?? 1
        let prev = opts["prev"] as? String
        let next = opts["next"] as? String
        let base = (opts["base"] as? String) ?? (ctx.userContext["path"] as? String) ?? "/"
        let escape = (opts["escape"] as? Bool) ?? true
        var out = "<nav class=\"pagination\">"
        let esc: (String) -> String = escape ? htmlEscape : { $0 }
        if let prevPath = prev {
            let url = "\(base == "/" ? "" : base)/\(prevPath)/"
            let prev_text = (opts["prev_text"] as? String) ?? "Prev"
            out += "<a class=\"prev\" href=\"\(normalizeURL(url))\">\(esc(prev_text))</a>"
        }
        out += "<span class=\"page-number\">\(current) / \(total)</span>"
        if let nextPath = next {
            let url = "\(base == "/" ? "" : base)/\(nextPath)/"
            let next_text = (opts["next_text"] as? String) ?? "Next"
            out += "<a class=\"next\" href=\"\(normalizeURL(url))\">\(esc(next_text))</a>"
        }
        out += "</nav>"
        return out
    }

    private func renderTagcloudHelper(ctx: inout EJSContext) -> String {
        let site = (ctx.userContext["site"] as? [String: Any]) ?? [:]
        let tags = (site["tags"] as? [[String: Any]]) ?? []
        var out = "<div class=\"tag-cloud\">"
        for t in tags {
            let name = (t["name"] as? String) ?? ""
            let slug = (t["slug"] as? String) ?? name
            let count = (t["count"] as? Int) ?? 0
            out += "<a href=\"/tags/\(slug)/\" data-count=\"\(count)\">\(htmlEscape(name))</a> "
        }
        out += "</div>"
        return out
    }

    private func renderSearchFormHelper(args: [Any?], ctx: inout EJSContext) -> String {
        let opts = (args.first as? [String: Any]) ?? [:]
        let button = (opts["button"] as? String) ?? "Search"
        let text = (opts["text"] as? String) ?? "Search"
        return "<form class=\"search\" role=\"search\"><input type=\"search\" name=\"q\" placeholder=\"\(htmlEscape(text))\" /><button type=\"submit\">\(htmlEscape(button))</button></form>"
    }

    private func renderOpenGraphHelper(args: [Any?], ctx: inout EJSContext) -> String {
        let opts = (args.first as? [String: Any]) ?? [:]
        let site = (ctx.userContext["site"] as? [String: Any]) ?? [:]
        let page = (ctx.userContext["page"] as? [String: Any]) ?? [:]
        let title = (opts["title"] as? String) ?? (page["title"] as? String) ?? (site["title"] as? String) ?? ""
        let desc = (opts["description"] as? String) ?? (site["description"] as? String) ?? ""
        let url = (opts["url"] as? String) ?? (site["url"] as? String) ?? ""
        let image = (opts["image"] as? String) ?? (page["cover"] as? String) ?? ""
        let site_name = (opts["site_name"] as? String) ?? (site["title"] as? String) ?? ""
        let type = (opts["type"] as? String) ?? (page["layout"] as? String) ?? "website"
        var out = ""
        out += "<meta property=\"og:type\" content=\"\(htmlEscape(type))\" />\n"
        out += "<meta property=\"og:title\" content=\"\(htmlEscape(title))\" />\n"
        out += "<meta property=\"og:url\" content=\"\(htmlEscape(url))\" />\n"
        if !site_name.isEmpty { out += "<meta property=\"og:site_name\" content=\"\(htmlEscape(site_name))\" />\n" }
        if !desc.isEmpty { out += "<meta property=\"og:description\" content=\"\(htmlEscape(desc))\" />\n" }
        if !image.isEmpty { out += "<meta property=\"og:image\" content=\"\(htmlEscape(image))\" />\n" }
        return out
    }

    private func renderFeedTagHelper(args: [Any?], ctx: inout EJSContext) -> String {
        // feed_tag() 或 feed_tag(path)
        let path = (args.first as? String) ?? "/atom.xml"
        let siteDict = (ctx.userContext["site"] as? [String: Any]) ?? [:]
        let title = (siteDict["title"] as? String) ?? "RSS"
        let url = normalizeURL(path)
        let esc = htmlEscape(title)
        return "<link rel=\"alternate\" href=\"\(url)\" title=\"\(esc)\" type=\"application/atom+xml\" />"
    }

    private func renderFaviconTagHelper(args: [Any?], ctx: inout EJSContext) -> String {
        let path = (args.first as? String) ?? "/favicon.ico"
        return "<link rel=\"icon\" href=\"\(normalizeURL(path))\" />"
    }

    private func getTagCount(tag: String, ctx: EJSContext) -> Int {
        let site = (ctx.userContext["site"] as? [String: Any]) ?? [:]
        if let tags = site["tags"] as? [[String: Any]] {
            for t in tags {
                if (t["name"] as? String) == tag { return (t["count"] as? Int) ?? 0 }
            }
        }
        return 0
    }

    private func getCategoryCount(cat: String, ctx: EJSContext) -> Int {
        let site = (ctx.userContext["site"] as? [String: Any]) ?? [:]
        if let cats = site["categories"] as? [[String: Any]] {
            for c in cats {
                if (c["name"] as? String) == cat { return (c["count"] as? Int) ?? 0 }
            }
        }
        return 0
    }

    private func md5Hex(_ s: String) -> String {
        let data = s.data(using: .utf8) ?? Data()
        return Self.md5(data).map { String(format: "%02x", $0) }.joined()
    }

    private static func md5(_ data: Data) -> [UInt8] {
        #if canImport(CommonCrypto)
        var digest = [UInt8](repeating: 0, count: 16)
        data.withUnsafeBytes { ptr in
            _ = CC_MD5(ptr.baseAddress, CC_LONG(data.count), &digest)
        }
        return digest
        #else
        // 极简 fallback: FNV-1a 64-bit 扩展到 16 字节
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in data {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        var bytes: [UInt8] = []
        for i in 0..<16 {
            let shift = (15 - i) * 4
            let nibble = (hash >> shift) & 0xF
            let s2: UInt64 = UInt64(bitPattern: Int64(hash & 0xFFFF)) ^ UInt64(i &+ 0xA5)
            let v = UInt8((nibble ^ (s2 & 0xF)) & 0xF)
            bytes.append(v)
        }
        return bytes
        #endif
    }

    private func parseDateString(_ s: String) -> Date? {
        let formats = [
            "yyyy-MM-dd'T'HH:mm:ssZZZZZ",
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd",
            "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
            "yyyy/MM/dd HH:mm:ss",
        ]
        for fmt in formats {
            let f = DateFormatter()
            f.dateFormat = fmt
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone.current
            if let d = f.date(from: s) { return d }
        }
        let iso = ISO8601DateFormatter()
        return iso.date(from: s)
    }

    // MARK: - stringify / truthy / deepEqual

    public func stringify(_ v: Any?) -> String {
        if v == nil { return "" }
        if let n = v as? NSNull { return "" }
        if let s = v as? String { return s }
        if let b = v as? Bool { return b ? "true" : "false" }
        if let i = v as? Int { return String(i) }
        if let d = v as? Double { return String(d) }
        if let date = v as? Date {
            let fmt = ISO8601DateFormatter()
            return fmt.string(from: date)
        }
        if let a = v as? [Any] { return a.map { stringify($0) }.joined(separator: ", ") }
        if let d = v as? [String: Any] {
            // 不能直接 JSONSerialization (可能含 Date), 走自实现
            return jsonString(d)
        }
        return String(describing: v!)
    }

    private func jsonString(_ d: [String: Any]) -> String {
        var parts: [String] = []
        for (k, v) in d.sorted(by: { $0.key < $1.key }) {
            parts.append("\"" + k.replacingOccurrences(of: "\"", with: "\\\"") + "\":" + jsonValue(v))
        }
        return "{" + parts.joined(separator: ",") + "}"
    }

    private func jsonValue(_ v: Any?) -> String {
        if v == nil { return "null" }
        if let n = v as? NSNull { return "null" }
        if let s = v as? String { return "\"" + s.replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: "\\n") + "\"" }
        if let b = v as? Bool { return b ? "true" : "false" }
        if let i = v as? Int { return String(i) }
        if let d = v as? Double { return String(d) }
        if let date = v as? Date { return "\"" + ISO8601DateFormatter().string(from: date) + "\"" }
        if let a = v as? [Any] { return "[" + a.map { jsonValue($0) }.joined(separator: ",") + "]" }
        if let d = v as? [String: Any] { return jsonString(d) }
        return "null"
    }

    public func isTruthy(_ v: Any?) -> Bool {
        if v == nil { return false }
        if let n = v as? NSNull { return false }
        if let b = v as? Bool { return b }
        if let i = v as? Int { return i != 0 }
        if let s = v as? String { return !s.isEmpty }
        if let a = v as? [Any] { return !a.isEmpty }
        if let d = v as? [String: Any] { return !d.isEmpty }
        return true
    }

    /// 将任意值转为 Double 用于比较运算。
    /// 支持 Int/Double/String(可解析数字)/Bool(Date 等不支持, 返回 0)
    public func numberize(_ v: Any?) -> Double {
        if v == nil { return 0 }
        if let n = v as? NSNull { return 0 }
        if let i = v as? Int { return Double(i) }
        if let d = v as? Double { return d }
        if let f = v as? Float { return Double(f) }
        if let b = v as? Bool { return b ? 1 : 0 }
        if let s = v as? String {
            if let d = Double(s) { return d }
            // 长度字符串当 0
            return 0
        }
        if let _ = v as? Date { return 0 }
        return 0
    }

    public func deepEqual(_ a: Any?, _ b: Any?) -> Bool {
        if a == nil && b == nil { return true }
        if a == nil || b == nil { return false }
        if let s = a as? String, let ss = b as? String { return s == ss }
        if let i = a as? Int, let ii = b as? Int { return i == ii }
        if let d = a as? Double, let dd = b as? Double { return d == dd }
        if let b1 = a as? Bool, let b2 = b as? Bool { return b1 == b2 }
        if a is NSNull && b is NSNull { return true }
        return false
    }

    public func htmlEscape(_ s: String) -> String {
        var out = s
        out = out.replacingOccurrences(of: "&", with: "&amp;")
        out = out.replacingOccurrences(of: "<", with: "&lt;")
        out = out.replacingOccurrences(of: ">", with: "&gt;")
        out = out.replacingOccurrences(of: "\"", with: "&quot;")
        out = out.replacingOccurrences(of: "'", with: "&#39;")
        return out
    }
}
