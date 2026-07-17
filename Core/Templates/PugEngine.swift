import Foundation

/// Pug (原 Jade) 模板引擎 - Hexo 主题常用子集。
///
/// 支持:
///  - 元素标签: `div`, `a(href=url)`, `span.foo#bar`
///  - 文本: 字面量, `| 文本` (强制文字), `.` (纯文本块)
///  - 插值: `= expr` (转义), `!= expr` (原始), `\#{expr}` 在文本内
///  - 属性: 括号语法 `(href=url, class=['a', 'b'])`, 简写 `&attributes({...})`
///  - 注释: `//`, `//-` (不输出)
///  - 代码: `- var x = 1` (不输出), `+ var x = 1` (不缓冲)
///  - 条件: `if/else if/else/unless`
///  - 循环: `each item in list`, `each val, key in obj`, `while`
///  - case/when/default
///  - include: `include path/to/file`
///  - extends/block/append/prepend (布局)
///  - mixin: `mixin name(args)`, `+name(args)`
///  - filter: `:filterName` (markdown-it, js, css 等)
///  - 嵌套: 通过缩进
public final class PugEngine {
    public let themeRoot: String
    public var warnings: [String] = []
    public var partialCache: [String: String] = [:]
    public var helpers: [String: Any] = [:]
    /// 渲染时主动注入的全局 helper (例如 url_for)
    public var globalHelpers: [String: Any] = [:]

    public init(themeRoot: String) {
        self.themeRoot = themeRoot
    }

    // MARK: - 公共入口

    public func renderFile(relPath: String, context: [String: Any]) -> String {
        warnings = []
        let path = (themeRoot as NSString).appendingPathComponent(relPath)
        guard let text = FSUtil.readText(path) else {
            warnings.append("Pug 模板缺失: \(relPath)")
            return ""
        }
        return render(template: text, context: context, currentPath: relPath)
    }

    /// 简单字符串渲染 (用于 `render(text, 'pug')` helper)
    public func renderString(_ text: String, context: [String: Any]) -> String {
        return render(template: text, context: context, currentPath: "<string>")
    }

    public func render(template: String, context: [String: Any], currentPath: String = "") -> String {
        var ctx = PugContext()
        ctx.userContext = context
        for (k, v) in globalHelpers { ctx.userContext[k] = v }
        for (k, v) in helpers { ctx.userContext[k] = v }
        return renderWithCtx(template: template, ctx: &ctx, currentPath: currentPath)
    }

    private func renderWithCtx(template: String, ctx: inout PugContext, currentPath: String) -> String {
        // 预处理: 处理 extends, 然后渲染
        let parser = PugParser(source: template)
        let nodes = parser.parseTopLevel()
        // 处理 extends
        if let ext = nodes.compactMap({ $0 as? PugExtend }).first {
            // 当前模板必须有 block (用于填充)
            let blocks = extractBlocks(from: nodes)
            // 加载 extends 目标
            var parentText = ""
            if let cached = partialCache[ext.path] {
                parentText = cached
            } else {
                // 尝试 layout/path, layout/path.pug, path, path.pug
                let candidates = [
                    ext.path,
                    "\(ext.path).pug",
                    "layout/\(ext.path)",
                    "layout/\(ext.path).pug"
                ]
                var found = false
                for c in candidates {
                    let p = (themeRoot as NSString).appendingPathComponent(c)
                    if let t = FSUtil.readText(p) {
                        partialCache[ext.path] = t
                        parentText = t
                        found = true
                        break
                    }
                }
                if !found {
                    warnings.append("Pug extends 找不到: \(ext.path)")
                    parentText = ""
                }
            }
            // 渲染 parent, 注入子 block
            ctx.childBlocks = blocks
            var parentCtx = ctx
            let parentParser = PugParser(source: parentText)
            let parentNodes = parentParser.parseTopLevel()
            return renderNodes(parentNodes, ctx: &parentCtx, currentPath: currentPath)
        }
        return renderNodes(nodes, ctx: &ctx, currentPath: currentPath)
    }

    private func extractBlocks(from nodes: [PugNode]) -> [String: PugBlock] {
        var out: [String: PugBlock] = [:]
        for n in nodes {
            if let b = n as? PugBlock { out[b.name] = b }
        }
        return out
    }

    // MARK: - 节点渲染

    private func renderNodes(_ nodes: [PugNode], ctx: inout PugContext, currentPath: String) -> String {
        var out = ""
        for n in nodes {
            out += renderNode(n, ctx: &ctx, currentPath: currentPath)
        }
        return out
    }

    private func renderNode(_ node: PugNode, ctx: inout PugContext, currentPath: String) -> String {
        // 处理全局指令
        if let block = node as? PugBlock {
            // 如果子模板已定义同名 block, 优先用子 block 替换
            if let child = ctx.childBlocks[block.name] {
                if block.appendMode {
                    // append: 在父 block 前插子 block 内容
                    var c2 = ctx
                    let childContent = renderNodes(child.body, ctx: &c2, currentPath: currentPath)
                    var c3 = ctx
                    let parentContent = renderNodes(block.body, ctx: &c3, currentPath: currentPath)
                    return childContent + parentContent
                } else if block.prependMode {
                    var c2 = ctx
                    let childContent = renderNodes(child.body, ctx: &c2, currentPath: currentPath)
                    var c3 = ctx
                    let parentContent = renderNodes(block.body, ctx: &c3, currentPath: currentPath)
                    return parentContent + childContent
                } else {
                    var c2 = ctx
                    return renderNodes(child.body, ctx: &c2, currentPath: currentPath)
                }
            }
            // 否则渲染父 block (sub-template 没 override)
            var c2 = ctx
            return renderNodes(block.body, ctx: &c2, currentPath: currentPath)
        }

        if let ext = node as? PugExtend {
            // extends 已在外面处理, 这里不会执行
            return ""
        }

        if let inc = node as? PugInclude {
            return renderInclude(inc, ctx: &ctx, currentPath: currentPath)
        }

        if let code = node as? PugCode {
            return renderCode(code, ctx: &ctx, currentPath: currentPath)
        }

        if let ce = node as? PugCase {
            return renderCase(ce, ctx: &ctx, currentPath: currentPath)
        }

        if let mixin = node as? PugMixinDef {
            // 定义 mixin: 存到 ctx
            ctx.mixins[mixin.name] = mixin
            return ""
        }

        if let call = node as? PugMixinCall {
            return renderMixinCall(call, ctx: &ctx, currentPath: currentPath)
        }

        if let cond = node as? PugConditional {
            return renderConditional(cond, ctx: &ctx, currentPath: currentPath)
        }

        if let each = node as? PugEach {
            return renderEach(each, ctx: &ctx, currentPath: currentPath)
        }

        if let wh = node as? PugWhile {
            return renderWhile(wh, ctx: &ctx, currentPath: currentPath)
        }

        if let filt = node as? PugFilter {
            return renderFilter(filt, ctx: &ctx, currentPath: currentPath)
        }

        if let txt = node as? PugText {
            return renderText(txt, ctx: &ctx, currentPath: currentPath)
        }

        if let el = node as? PugElement {
            return renderElement(el, ctx: &ctx, currentPath: currentPath)
        }

        if let lit = node as? PugLiteralText {
            return lit.text
        }

        if let seq = node as? PugSequence {
            return renderNodes(seq.nodes, ctx: &ctx, currentPath: currentPath)
        }

        if let dt = node as? PugDoctype {
            switch dt.value.lowercased() {
            case "html": return "<!DOCTYPE html>"
            case "xml": return "<?xml version=\"1.0\" encoding=\"utf-8\" ?>"
            case "transitional": return "<!DOCTYPE html PUBLIC \"-//W3C//DTD XHTML 1.0 Transitional//EN\" \"http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd\">"
            case "strict": return "<!DOCTYPE html PUBLIC \"-//W3C//DTD XHTML 1.0 Strict//EN\" \"http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd\">"
            case "frameset": return "<!DOCTYPE html PUBLIC \"-//W3C//DTD XHTML 1.0 Frameset//EN\" \"http://www.w3.org/TR/xhtml1/DTD/xhtml1-frameset.dtd\">"
            case "basic": return "<!DOCTYPE html PUBLIC \"-//W3C//DTD XHTML 1.1//EN\" \"http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd\">"
            case "1.1": return "<!DOCTYPE html PUBLIC \"-//W3C//DTD XHTML 1.1//EN\" \"http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd\">"
            case "mobile": return "<!DOCTYPE html PUBLIC \"-//WAPFORUM//DTD XHTML Mobile 1.2//EN\" \"http://www.openmobilealliance.org/tech/DTD/xhtml-mobile12.dtd\">"
            case "plist": return "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">"
            default: return "<!DOCTYPE \(dt.value)>"
            }
        }

        if let expr = node as? PugExpression {
            let v = evaluateExpression(expr.expr, ctx: &ctx, currentPath: currentPath)
            let s = stringifyPug(v, ctx: &ctx, currentPath: currentPath)
            return expr.raw ? s : htmlEscapePug(s)
        }

        return ""
    }

    private func renderElement(_ el: PugElement, ctx: inout PugContext, currentPath: String) -> String {
        let tag = el.tag
        let isVoid = Self.isVoidTag(tag)
        // 解析属性 (含 &attributes)
        var attrs: [(String, Any?)] = el.attrs
        for aug in el.attributeBlocks {
            if let dict = evaluateExpression(aug, ctx: &ctx, currentPath: currentPath) as? [String: Any] {
                for (k, v) in dict { attrs.append((k, v)) }
            } else if let dict = evaluateExpression(aug, ctx: &ctx, currentPath: currentPath) as? [String: String] {
                for (k, v) in dict { attrs.append((k, v as Any)) }
            }
        }
        let attrStr = renderAttrs(attrs, ctx: &ctx, currentPath: currentPath)
        let open = attrStr.isEmpty ? "<\(tag)>" : "<\(tag) \(attrStr)>"
        if isVoid { return open }
        let inner = renderNodes(el.body, ctx: &ctx, currentPath: currentPath)
        return open + inner + "</\(tag)>"
    }

    private func renderAttrs(_ attrs: [(String, Any?)], ctx: inout PugContext, currentPath: String) -> String {
        var parts: [String] = []
        for (k, v) in attrs {
            // 布尔属性: true → 只输出名, false/nil → 跳过
            if v == nil { continue }
            if let b = v as? Bool {
                if b { parts.append(k) }
                continue
            }
            // 值转字符串
            let s = stringifyPug(v, ctx: &ctx, currentPath: currentPath)
            // 短形式: class=[a,b] 合并; 多 class 重复
            parts.append("\(k)=\"\(htmlEscapePug(s))\"")
        }
        return parts.joined(separator: " ")
    }

    private func renderText(_ txt: PugText, ctx: inout PugContext, currentPath: String) -> String {
        var s = txt.text
        // 替换 #{} 插值
        s = renderInterpolations(s, ctx: &ctx, currentPath: currentPath)
        return s
    }

    /// 把字符串中的 `\#{expr}` 替换成 eval 后的值
    private func renderInterpolations(_ s: String, ctx: inout PugContext, currentPath: String) -> String {
        var out = ""
        var i = s.startIndex
        while i < s.endIndex {
            if let r = s.range(of: "#{", range: i..<s.endIndex) {
                out += s[i..<r.lowerBound]
                // 找匹配的 }
                guard let close = matchBracePug(s, openIdx: r.upperBound) else {
                    out += s[r.lowerBound..<s.endIndex]
                    return out
                }
                let expr = String(s[r.upperBound..<close]).trimmingCharacters(in: .whitespaces)
                let v = evaluateExpression(expr, ctx: &ctx, currentPath: currentPath)
                out += stringifyPug(v, ctx: &ctx, currentPath: currentPath)
                i = s.index(after: close)
            } else {
                out += s[i..<s.endIndex]
                break
            }
        }
        return out
    }

    private func renderInclude(_ inc: PugInclude, ctx: inout PugContext, currentPath: String) -> String {
        let path = inc.path
        var text = ""
        if let cached = partialCache[path] {
            text = cached
        } else {
            let candidates = [
                path,
                "\(path).pug",
                "layout/\(path)",
                "layout/\(path).pug"
            ]
            var found = false
            for c in candidates {
                let p = (themeRoot as NSString).appendingPathComponent(c)
                if let t = FSUtil.readText(p) {
                    partialCache[path] = t
                    text = t
                    found = true
                    break
                }
            }
            if !found {
                warnings.append("Pug include 找不到: \(path)")
                return ""
            }
        }
        return renderWithCtx(template: text, ctx: &ctx, currentPath: path)
    }

    private func renderCode(_ code: PugCode, ctx: inout PugContext, currentPath: String) -> String {
        // - var x = 1 / - if cond / - each item in list
        // 简化为: 把表达式当 JS-style 表达式求值, 副作用
        let trimmed = code.expr.trimmingCharacters(in: .whitespacesAndNewlines)
        // var / let / const
        var rest = trimmed
        if rest.hasPrefix("var ") || rest.hasPrefix("let ") || rest.hasPrefix("const ") {
            // 简化: var a = expr → 解析 lhs 名字, 求值 rhs
            if let eqIdx = rest.firstIndex(of: "=") {
                let lhs = String(rest[rest.index(after: rest.startIndex)..<eqIdx]).trimmingCharacters(in: .whitespaces)
                let rhs = String(rest[rest.index(after: eqIdx)...]).trimmingCharacters(in: .whitespaces)
                let v = evaluateExpression(rhs, ctx: &ctx, currentPath: currentPath)
                ctx.userContext[lhs] = v ?? NSNull()
            }
            return ""
        }
        // 一般表达式: 求值但丢弃
        _ = evaluateExpression(trimmed, ctx: &ctx, currentPath: currentPath)
        return ""
    }

    private func renderCase(_ ce: PugCase, ctx: inout PugContext, currentPath: String) -> String {
        let v = evaluateExpression(ce.expr, ctx: &ctx, currentPath: currentPath)
        for w in ce.whens {
            // when 表达式支持字面量或逗号分隔
            let conds = w.cond.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            for c in conds {
                let cv = evaluateExpression(c, ctx: &ctx, currentPath: currentPath)
                if deepEqualPug(v, cv) {
                    return renderNodes(w.body, ctx: &ctx, currentPath: currentPath)
                }
            }
        }
        if let def = ce.defaultBody {
            return renderNodes(def, ctx: &ctx, currentPath: currentPath)
        }
        return ""
    }

    private func renderConditional(_ c: PugConditional, ctx: inout PugContext, currentPath: String) -> String {
        let cond = c.isUnless ? !isTruthyPug(evaluateExpression(c.expr, ctx: &ctx, currentPath: currentPath))
                              : isTruthyPug(evaluateExpression(c.expr, ctx: &ctx, currentPath: currentPath))
        if cond { return renderNodes(c.body, ctx: &ctx, currentPath: currentPath) }
        if let e = c.elseBody { return renderNodes(e, ctx: &ctx, currentPath: currentPath) }
        return ""
    }

    private func renderEach(_ each: PugEach, ctx: inout PugContext, currentPath: String) -> String {
        let listVal = evaluateExpression(each.expr, ctx: &ctx, currentPath: currentPath)
        var out = ""
        if let arr = listVal as? [Any] {
            for (idx, item) in arr.enumerated() {
                ctx.pushScope(eachBindings(varNames: each.varNames, value: item, index: idx))
                out += renderNodes(each.body, ctx: &ctx, currentPath: currentPath)
                ctx.popScope()
            }
        } else if let dict = listVal as? [String: Any] {
            for (k, v) in dict {
                ctx.pushScope(eachBindings(varNames: each.varNames, value: v, index: 0, key: k))
                out += renderNodes(each.body, ctx: &ctx, currentPath: currentPath)
                ctx.popScope()
            }
        } else {
            // 数字 → 重复 N 次
            if let n = listVal as? Int, n > 0 {
                for i in 0..<n {
                    ctx.pushScope(eachBindings(varNames: each.varNames, value: i, index: i))
                    out += renderNodes(each.body, ctx: &ctx, currentPath: currentPath)
                    ctx.popScope()
                }
            }
        }
        return out
    }

    private func eachBindings(varNames: [String], value: Any, index: Int, key: String? = nil) -> [String: Any] {
        var scope: [String: Any] = [:]
        if varNames.count == 1 {
            scope[varNames[0]] = value
        } else if varNames.count == 2 {
            scope[varNames[0]] = value
            scope[varNames[1]] = key ?? index
        } else {
            for (i, n) in varNames.enumerated() { scope[n] = i == 0 ? value : (key ?? index) }
        }
        return scope
    }

    private func renderWhile(_ w: PugWhile, ctx: inout PugContext, currentPath: String) -> String {
        var out = ""
        var safety = 0
        while isTruthyPug(evaluateExpression(w.expr, ctx: &ctx, currentPath: currentPath)) {
            out += renderNodes(w.body, ctx: &ctx, currentPath: currentPath)
            safety += 1
            if safety > 10000 { break }  // 防止死循环
        }
        return out
    }

    private func renderFilter(_ f: PugFilter, ctx: inout PugContext, currentPath: String) -> String {
        let text = renderNodes(f.body, ctx: &ctx, currentPath: currentPath)
        switch f.name.lowercased() {
        case "markdown", "markdown-it":
            return MarkdownRenderer.render(text)
        case "js":
            return "<script>\n" + text + "\n</script>"
        case "css", "style":
            return "<style>\n" + text + "\n</style>"
        case "plain", "text":
            return text
        default:
            // 未知 filter: 原样输出
            return text
        }
    }

    private func renderMixinCall(_ c: PugMixinCall, ctx: inout PugContext, currentPath: String) -> String {
        guard let m = ctx.mixins[c.name] else {
            warnings.append("Pug mixin 未定义: \(c.name)")
            return ""
        }
        // 绑定参数
        var scope: [String: Any] = [:]
        for (i, pname) in m.paramNames.enumerated() {
            if i < c.args.count {
                let v = c.args[i]
                if let expr = v as? String {
                    scope[pname] = evaluateExpression(expr, ctx: &ctx, currentPath: currentPath)
                } else {
                    scope[pname] = v
                }
            } else {
                scope[pname] = nil
            }
        }
        // mixin 的 rest 参数
        if m.hasRest {
            let restVals: [Any] = c.args.dropFirst(m.paramNames.count).map { v in
                if let expr = v as? String {
                    return evaluateExpression(expr, ctx: &ctx, currentPath: currentPath) ?? NSNull()
                }
                return v
            }
            scope["arguments"] = restVals
        }
        ctx.pushScope(scope)
        // mixin 还可以通过 block 子节点接受内容
        let inner = renderNodes(m.body, ctx: &ctx, currentPath: currentPath)
        ctx.popScope()
        return inner
    }

    // MARK: - 表达式求值

    private func evaluateExpression(_ expr: String, ctx: inout PugContext, currentPath: String) -> Any? {
        let t = expr.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return nil }
        // 字符串字面量
        if (t.hasPrefix("'") && t.hasSuffix("'") && t.count >= 2) ||
           (t.hasPrefix("\"") && t.hasSuffix("\"") && t.count >= 2) {
            return stripQuotesPug(t)
        }
        if t == "true" { return true }
        if t == "false" { return false }
        if t == "null" || t == "undefined" { return NSNull() }
        if let i = Int(t) { return i }
        if let d = Double(t) { return d }
        // 数组字面量
        if t.hasPrefix("[") && t.hasSuffix("]") {
            return evalArrayPug(t, ctx: &ctx, currentPath: currentPath)
        }
        // 对象字面量
        if t.hasPrefix("{") && t.hasSuffix("}") {
            return evalObjectPug(t, ctx: &ctx, currentPath: currentPath)
        }
        // 简单标识符
        if isIdentifier(t) {
            return ctx.lookup(t)
        }
        // 复合表达式: 尝试用 JS-like 解析
        return evalCompoundPug(t, ctx: &ctx, currentPath: currentPath)
    }

    private func evalArrayPug(_ s: String, ctx: inout PugContext, currentPath: String) -> [Any] {
        let inner = String(s.dropFirst().dropLast())
        if inner.trimmingCharacters(in: .whitespaces).isEmpty { return [] }
        return splitTopLevelCommaPug(inner).map { evaluateExpression($0.trimmingCharacters(in: .whitespaces), ctx: &ctx, currentPath: currentPath) ?? NSNull() }
    }

    private func evalObjectPug(_ s: String, ctx: inout PugContext, currentPath: String) -> [String: Any] {
        let inner = String(s.dropFirst().dropLast())
        var out: [String: Any] = [:]
        for part in splitTopLevelCommaPug(inner) {
            if let colon = part.firstIndex(of: ":") {
                let k = part[..<colon].trimmingCharacters(in: .whitespaces)
                let v = String(part[part.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                let key = stripQuotesPug(k)
                out[key] = evaluateExpression(v, ctx: &ctx, currentPath: currentPath)
            }
        }
        return out
    }

    private func evalCompoundPug(_ s: String, ctx: inout PugContext, currentPath: String) -> Any? {
        // 支持: a.b.c, a(b), a + b, a == b, a || b, a ? b : c
        // 1) ||  (OR) - 短路
        if let r = splitTopLevelPug(s, sep: "||") {
            let l = evaluateExpression(String(s[s.startIndex..<r.lowerBound]).trimmingCharacters(in: .whitespaces), ctx: &ctx, currentPath: currentPath)
            if isTruthyPug(l) { return l }
            return evaluateExpression(String(s[r.upperBound..<s.endIndex]).trimmingCharacters(in: .whitespaces), ctx: &ctx, currentPath: currentPath)
        }
        // 2) 字符串拼接/算术: a + b
        if s.contains("+") && !s.contains("?") {
            if let r = splitTopLevelPug(s, sep: "+") {
                let l = evaluateExpression(String(s[s.startIndex..<r.lowerBound]).trimmingCharacters(in: .whitespaces), ctx: &ctx, currentPath: currentPath)
                let rr = evaluateExpression(String(s[r.upperBound..<s.endIndex]).trimmingCharacters(in: .whitespaces), ctx: &ctx, currentPath: currentPath)
                if let ls = l as? String, let rs = rr as? String { return ls + rs }
                if let ls = l as? Int, let rs = rr as? Int { return ls + rs }
                return stringifyPug(l, ctx: &ctx, currentPath: currentPath) + stringifyPug(rr, ctx: &ctx, currentPath: currentPath)
            }
        }
        // 3) ==
        if s.contains("==") && !s.contains("===") {
            if let r = splitTopLevelPug(s, sep: "==") {
                let l = evaluateExpression(String(s[s.startIndex..<r.lowerBound]).trimmingCharacters(in: .whitespaces), ctx: &ctx, currentPath: currentPath)
                let rr = evaluateExpression(String(s[r.upperBound..<s.endIndex]).trimmingCharacters(in: .whitespaces), ctx: &ctx, currentPath: currentPath)
                return deepEqualPug(l, rr)
            }
        }
        if s.contains("!=") && !s.contains("!==") {
            if let r = splitTopLevelPug(s, sep: "!=") {
                let l = evaluateExpression(String(s[s.startIndex..<r.lowerBound]).trimmingCharacters(in: .whitespaces), ctx: &ctx, currentPath: currentPath)
                let rr = evaluateExpression(String(s[r.upperBound..<s.endIndex]).trimmingCharacters(in: .whitespaces), ctx: &ctx, currentPath: currentPath)
                return !deepEqualPug(l, rr)
            }
        }
        // 4) ?: 三元
        if let r = s.range(of: "?") {
            if let colon = findTopLevelPug(s, ":", after: r.upperBound) {
                let condExpr = String(s[..<r.lowerBound])
                let thenExpr = String(s[r.upperBound..<colon])
                let elseExpr = String(s[s.index(after: colon)...])
                if isTruthyPug(evaluateExpression(condExpr, ctx: &ctx, currentPath: currentPath)) {
                    return evaluateExpression(thenExpr, ctx: &ctx, currentPath: currentPath)
                } else {
                    return evaluateExpression(elseExpr, ctx: &ctx, currentPath: currentPath)
                }
            }
        }
        // 5) 路径 + 方法调用
        if s.contains("(") {
            return evalPugPath(s, ctx: &ctx)
        }
        return evalPugPath(s, ctx: &ctx)
    }

    private func evalPugPath(_ s: String, ctx: inout PugContext) -> Any? {
        // tokenize 类似 EJS: a.b.c
        // 支持: a, a.b, a[b], a.b(), a()()
        // 先取第一段 (key)
        var firstKey = ""
        var i = s.startIndex
        while i < s.endIndex {
            let c = s[i]
            if c == "." || c == "[" || c == "(" { break }
            firstKey.append(c)
            i = s.index(after: i)
        }
        var current: Any? = ctx.lookup(firstKey)
        if firstKey.isEmpty { current = nil }
        // 跳过第一段 (因为 firstKey 已 lookup, tokenize 不会再生成它)
        let tokens = tokenizePugPath(s, skipFirstKey: !firstKey.isEmpty)
        for tk in tokens {
            switch tk {
            case .key(let k):
                if let d = current as? [String: Any] { current = d[k] }
                else { return nil }
            case .index(let i):
                if let arr = current as? [Any], i < arr.count { current = arr[i] }
                else { return nil }
            case .varKey(let v):
                if let d = current as? [String: Any], let k = ctx.lookup(v) as? String { current = d[k] }
                else { return nil }
            case .methodCall(let name, let rawArgs):
                current = applyPugMethod(name: name, on: current, rawArgs: rawArgs, ctx: &ctx)
            }
        }
        return current
    }

    private enum PugPathToken { case key(String); case index(Int); case varKey(String); case methodCall(String, [String]) }

    private func tokenizePugPath(_ s: String, skipFirstKey: Bool = false) -> [PugPathToken] {
        var tokens: [PugPathToken] = []
        var i = s.startIndex
        var current = ""
        var skipped = false
        while i < s.endIndex {
            let c = s[i]
            if c == "." {
                if !current.isEmpty {
                    if !skipFirstKey || skipped {
                        tokens.append(.key(current))
                    } else {
                        skipped = true
                    }
                    current = ""
                }
            } else if c == "(" {
                if !current.isEmpty {
                    if let close = matchBracketPug(s, openIdx: i) {
                        let argStr = String(s[s.index(after: i)..<close])
                        let args = splitTopLevelCommaPug(argStr)
                        if case .key(let kn) = tokens.last {
                            tokens.removeLast()
                            tokens.append(.methodCall(kn, args))
                        } else {
                            tokens.append(.methodCall(current, args))
                        }
                        current = ""
                        i = s.index(after: close)
                        continue
                    }
                }
            } else if c == "[" {
                if !current.isEmpty {
                    if !skipFirstKey || skipped {
                        tokens.append(.key(current))
                    } else {
                        skipped = true
                    }
                    current = ""
                }
                if let close = s[i...].firstIndex(of: "]") {
                    let inner = String(s[s.index(after: i)..<close])
                    if let idx = Int(inner) { tokens.append(.index(idx)) }
                    else if (inner.hasPrefix("'") && inner.hasSuffix("'")) || (inner.hasPrefix("\"") && inner.hasSuffix("\"")) {
                        tokens.append(.key(String(inner.dropFirst().dropLast())))
                    } else {
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
            if !skipFirstKey || skipped {
                tokens.append(.key(current))
            }
            // 否则跳过末尾的 firstKey 副本
        }
        return tokens
    }

    private func applyPugMethod(name: String, on obj: Any?, rawArgs: [String], ctx: inout PugContext) -> Any? {
        var argValues: [Any?] = []
        for r in rawArgs {
            argValues.append(evaluateExpression(r.trimmingCharacters(in: .whitespaces), ctx: &ctx, currentPath: "") ?? NSNull())
        }
        // 复用 EJS 的 helper (url_for 等): 通过 ctx.userContext 查
        if let fn = ctx.userContext[name] as? ([Any?]) -> Any? {
            return fn(argValues)
        }
        if let fn = ctx.userContext[name] as? (Any) -> Any? {
            return fn(argValues.first as Any? ?? NSNull())
        }
        if let arr = obj as? [Any] {
            switch name {
            case "forEach", "each":
                // 静默 - 没有 block 嵌套时, 啥也不做
                return nil
            case "map":
                // 简化: 不可用, 返回原数组
                return arr
            case "length":
                return arr.count
            case "first": return arr.first
            case "last": return arr.last
            case "join":
                let sep = (argValues.first as? String) ?? ","
                return arr.map { stringifyPugStatic($0) }.joined(separator: sep)
            default: break
            }
        }
        if let s = obj as? String {
            switch name {
            case "toUpperCase", "upper": return s.uppercased()
            case "toLowerCase", "lower": return s.lowercased()
            case "length": return s.count
            case "trim": return s.trimmingCharacters(in: .whitespacesAndNewlines)
            case "replace":
                if argValues.count >= 2, let from = argValues[0] as? String, let to = argValues[1] as? String {
                    return s.replacingOccurrences(of: from, with: to)
                }
            case "split":
                let sep = (argValues.first as? String) ?? ","
                return s.components(separatedBy: sep)
            default: break
            }
        }
        if let d = obj as? Date {
            let cal = Calendar.current
            let c = cal.dateComponents([.year, .month, .day], from: d)
            switch name {
            case "year": return c.year ?? 1970
            case "month": return c.month ?? 1
            case "date", "day": return c.day ?? 1
            default: break
            }
        }
        return nil
    }

    // 用 inout 访问 ctx (Swift 不支持, 简单 wrapper)

    // MARK: - 工具

    private static let voidTags: Set<String> = [
        "area", "base", "br", "col", "embed", "hr", "img", "input",
        "link", "meta", "param", "source", "track", "wbr"
    ]

    private static func isVoidTag(_ tag: String) -> Bool {
        voidTags.contains(tag.lowercased())
    }

    private func stringifyPug(_ v: Any?, ctx: inout PugContext, currentPath: String) -> String {
        if v == nil || v is NSNull { return "" }
        // PugAttrExpr: 在 string 时求值
        if let e = v as? PugAttrExpr {
            let r = evaluateExpression(e.expr, ctx: &ctx, currentPath: currentPath)
            return stringifyPug(r, ctx: &ctx, currentPath: currentPath)
        }
        if let b = v as? Bool { return b ? "true" : "false" }
        if let i = v as? Int { return String(i) }
        if let d = v as? Double { return String(d) }
        if let s = v as? String { return s }
        if let arr = v as? [Any] {
            return arr.map { stringifyPug($0, ctx: &ctx, currentPath: currentPath) }.joined(separator: ",")
        }
        if let d = v as? Date {
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
            return fmt.string(from: d)
        }
        return String(describing: v as Any)
    }

    private func stringifyPugStatic(_ v: Any?) -> String {
        if v == nil || v is NSNull { return "" }
        if let s = v as? String { return s }
        if let i = v as? Int { return String(i) }
        if let b = v as? Bool { return b ? "true" : "false" }
        return String(describing: v as Any)
    }

    private func isTruthyPug(_ v: Any?) -> Bool {
        if v == nil || v is NSNull { return false }
        if let b = v as? Bool { return b }
        if let i = v as? Int { return i != 0 }
        if let s = v as? String { return !s.isEmpty }
        if let arr = v as? [Any] { return !arr.isEmpty }
        if let d = v as? [String: Any] { return !d.isEmpty }
        return true
    }

    private func deepEqualPug(_ a: Any?, _ b: Any?) -> Bool {
        if a == nil && b == nil { return true }
        if let an = a as? NSNull, b is NSNull { return true }
        if let bn = b as? NSNull, a is NSNull { return true }
        if let sa = a as? String, let sb = b as? String { return sa == sb }
        if let ia = a as? Int, let ib = b as? Int { return ia == ib }
        if let ba = a as? Bool, let bb = b as? Bool { return ba == bb }
        return false
    }

    private func htmlEscapePug(_ s: String) -> String {
        var out = s
        out = out.replacingOccurrences(of: "&", with: "&amp;")
        out = out.replacingOccurrences(of: "<", with: "&lt;")
        out = out.replacingOccurrences(of: ">", with: "&gt;")
        out = out.replacingOccurrences(of: "\"", with: "&quot;")
        return out
    }

    private func stripQuotesPug(_ s: String) -> String {
        if (s.hasPrefix("'") && s.hasSuffix("'") && s.count >= 2) ||
           (s.hasPrefix("\"") && s.hasSuffix("\"") && s.count >= 2) {
            return String(s.dropFirst().dropLast())
        }
        return s
    }

    private func isIdentifier(_ s: String) -> Bool {
        guard let f = s.first else { return false }
        if f.isLetter || f == "_" || f == "$" {
            for c in s.dropFirst() { if !(c.isLetter || c.isNumber || c == "_" || c == "$") { return false } }
            return true
        }
        return false
    }

    private func matchBracePug(_ s: String, openIdx: String.Index) -> String.Index? {
        var depth = 1
        var i = s.index(after: openIdx)
        while i < s.endIndex {
            if s[i] == "{" { depth += 1 }
            else if s[i] == "}" { depth -= 1; if depth == 0 { return i } }
            i = s.index(after: i)
        }
        return nil
    }

    private func matchBracketPug(_ s: String, openIdx: String.Index) -> String.Index? {
        var depth = 1
        var inStr: Character? = nil
        var i = s.index(after: openIdx)
        while i < s.endIndex {
            let c = s[i]
            if let q = inStr { if c == q { inStr = nil } }
            else {
                if c == "'" || c == "\"" { inStr = c }
                else if c == "(" { depth += 1 }
                else if c == ")" { depth -= 1; if depth == 0 { return i } }
            }
            i = s.index(after: i)
        }
        return nil
    }

    private func splitTopLevelPug(_ s: String, sep: String) -> Range<String.Index>? {
        var depth = 0
        var inStr: Character? = nil
        var i = s.startIndex
        while i < s.endIndex {
            let c = s[i]
            if let q = inStr { if c == q { inStr = nil } }
            else {
                if c == "'" || c == "\"" { inStr = c }
                else if c == "(" || c == "[" || c == "{" { depth += 1 }
                else if c == ")" || c == "]" || c == "}" { depth -= 1 }
                else if depth == 0 {
                    // 检查 sep
                    let remaining = s[i..<s.endIndex]
                    if remaining.hasPrefix(sep) {
                        return i..<s.index(i, offsetBy: sep.count, limitedBy: s.endIndex)!
                    }
                }
            }
            i = s.index(after: i)
        }
        return nil
    }

    private func splitTopLevelCommaPug(_ s: String) -> [String] {
        var out: [String] = []
        var depth = 0
        var inStr: Character? = nil
        var start = s.startIndex
        for i in s.indices {
            let c = s[i]
            if let q = inStr { if c == q { inStr = nil } }
            else {
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

    private func findTopLevelPug(_ s: String, _ target: Character, after: String.Index) -> String.Index? {
        var depth = 0
        var inStr: Character? = nil
        var i = after
        while i < s.endIndex {
            let c = s[i]
            if let q = inStr { if c == q { inStr = nil } }
            else {
                if c == "'" || c == "\"" { inStr = c }
                else if c == "(" || c == "[" || c == "{" { depth += 1 }
                else if c == ")" || c == "]" || c == "}" { depth -= 1 }
                else if c == target && depth == 0 { return i }
            }
            i = s.index(after: i)
        }
        return nil
    }
}

// MARK: - Context

public final class PugContext {
    public var userContext: [String: Any] = [:]
    public var stack: [[String: Any]] = []
    public var mixins: [String: PugMixinDef] = [:]
    public var childBlocks: [String: PugBlock] = [:]

    public init() {}

    public func pushScope(_ d: [String: Any]) { stack.append(d) }
    public func popScope() { if !stack.isEmpty { stack.removeLast() } }

    public func merged() -> [String: Any] {
        var out = userContext
        for s in stack { for (k, v) in s { out[k] = v } }
        return out
    }

    public func lookup(_ key: String) -> Any? {
        for s in stack.reversed() { if let v = s[key] { return v } }
        return userContext[key]
    }

    public func lookupRoot(_ key: String) -> Any? {
        // 类似 EJS 起步, 优先在 userContext 顶层
        return userContext[key]
    }
}
