import Foundation

/// Pug 解析器 - 缩进式语法
public final class PugParser {
    private let lines: [String]
    private var pos: Int = 0

    public init(source: String) {
        // 标准化行, 移除 BOM, 处理 CRLF
        var s = source
        if s.hasPrefix("\u{FEFF}") { s = String(s.dropFirst()) }
        s = s.replacingOccurrences(of: "\r\n", with: "\n")
        s = s.replacingOccurrences(of: "\r", with: "\n")
        self.lines = s.components(separatedBy: "\n")
    }

    // MARK: - 顶层

    public func parseTopLevel() -> [PugNode] {
        return parseBlockAtIndent(-1)
    }

    /// 解析从当前位置开始, 缩进 > minIndent 的块 (作为上一节点的子)
    private func parseBlockAtIndent(_ minIndent: Int) -> [PugNode] {
        var out: [PugNode] = []
        while pos < lines.count {
            // 计算当前行缩进
            let raw = lines[pos]
            let stripped = raw.trimmingCharacters(in: .init(charactersIn: " "))
            // 空行 / 纯缩进 → 跳过
            if stripped.isEmpty { pos += 1; continue }
            let indent = leadingSpaces(raw)
            // 缩进 <= 父级: 此块结束, 留给上一层
            if indent <= minIndent { break }
            // 解析当前行
            let node = parseLine(indent: indent)
            if let n = node { out.append(n) }
        }
        return out
    }

    private func parseLine(indent: Int) -> PugNode? {
        let raw = lines[pos]
        let trimmed = raw.trimmingCharacters(in: .init(charactersIn: " "))
        pos += 1

        // 注释: // (输出)  /  //- (不输出)
        if trimmed.hasPrefix("//-") {
            return nil
        }
        if trimmed.hasPrefix("//") {
            return nil
        }

        // doctype
        if trimmed == "doctype" || trimmed.hasPrefix("doctype ") {
            let rest = trimmed == "doctype" ? "html" : String(trimmed.dropFirst("doctype".count)).trimmingCharacters(in: .whitespaces)
            return PugDoctype(rest)
        }

        // extends
        if trimmed.hasPrefix("extends ") {
            let p = String(trimmed.dropFirst("extends ".count)).trimmingCharacters(in: .whitespaces)
            return PugExtend(p)
        }

        // include
        if trimmed.hasPrefix("include ") {
            let p = String(trimmed.dropFirst("include ".count)).trimmingCharacters(in: .whitespaces)
            // 去除末尾可能的冒号等
            return PugInclude(p)
        }

        // block (含 append/prepend)
        if trimmed.hasPrefix("block ") {
            return parseBlockLine(trimmed, mode: .normal)
        }
        if trimmed.hasPrefix("prepend ") {
            let name = String(trimmed.dropFirst("prepend ".count)).trimmingCharacters(in: .whitespaces)
            let body = parseBlockAtIndent(indent + 1)
            return PugBlock(name: name, body: body, appendMode: false, prependMode: true)
        }
        if trimmed.hasPrefix("append ") {
            let name = String(trimmed.dropFirst("append ".count)).trimmingCharacters(in: .whitespaces)
            let body = parseBlockAtIndent(indent + 1)
            return PugBlock(name: name, body: body, appendMode: true, prependMode: false)
        }

        // mixin 定义
        if trimmed.hasPrefix("mixin ") {
            return parseMixinDef(trimmed, indent: indent)
        }

        // 元素标签 (含 . / # / &attributes)
        if isElementStart(trimmed) {
            return parseElement(trimmed, indent: indent)
        }

        // 纯文本 (无标签) → 用 PugText
        // 包含 = expr / != expr / =/ 各种前导
        if let n = parsePlainLine(trimmed, indent: indent) {
            return n
        }

        // 默认: 当文本节点
        return PugLiteralText(trimmed)
    }

    private enum BlockMode { case normal }

    private func parseBlockLine(_ s: String, mode: BlockMode) -> PugNode {
        let name = String(s.dropFirst("block ".count)).trimmingCharacters(in: .whitespaces)
        let body = parseBlockAtIndent(leadingSpaces(lines[pos - 1]) + 1)
        return PugBlock(name: name, body: body, appendMode: false, prependMode: false)
    }

    private func parseMixinDef(_ s: String, indent: Int) -> PugNode {
        // mixin name(arg1, arg2, ...rest)
        let after = String(s.dropFirst("mixin ".count)).trimmingCharacters(in: .whitespaces)
        var name = ""
        var i = after.startIndex
        while i < after.endIndex {
            let c = after[i]
            if c == "(" || c == " " { break }
            name.append(c)
            i = after.index(after: i)
        }
        // 解析参数
        var params: [String] = []
        var hasRest = false
        if i < after.endIndex && after[i] == "(" {
            if let close = matchBracket(after, openIdx: i) {
                let pstr = String(after[after.index(after: i)..<close])
                for part in splitTopLevelComma(pstr) {
                    let t = part.trimmingCharacters(in: .whitespaces)
                    if t.hasPrefix("...") { hasRest = true; continue }
                    if t.hasPrefix("&") { continue }  // block 参数
                    if !t.isEmpty { params.append(t) }
                }
            }
        }
        let body = parseBlockAtIndent(indent + 1)
        return PugMixinDef(name: name, paramNames: params, hasRest: hasRest, body: body)
    }

    private func parseElement(_ s: String, indent: Int) -> PugNode? {
        // 标签形式: tag.class#id(attr=val)...(text)  /  .class / #id / 单独
        // 也支持 &attributes({...}) 在属性后追加
        var rest = s
        var tag = "div"
        // 解析 tag
        if let first = rest.first {
            if first.isLetter {
                var name = ""
                var i = rest.startIndex
                while i < rest.endIndex {
                    let c = rest[i]
                    if c.isLetter || c.isNumber || c == "-" || c == "_" {
                        name.append(c)
                        i = rest.index(after: i)
                    } else { break }
                }
                tag = name
                rest = String(rest[i...])
            } else {
                // .class / #id, tag 保持 div
            }
        }

        // 收集 class / id / 普通 attr
        var attrs: [(String, Any?)] = []
        var attributeBlocks: [String] = []
        var consumed = ""
        var colonIdxAfterAttrs: String.Index? = nil  // `:` 位置 (如果有)
        var assignIdxAfterAttrs: String.Index? = nil  // `=` 位置 (如果有, 用于 inline `= expr`)
        var bangAssignIdx: String.Index? = nil  // `!=` 位置
        var sawAssign = false  // 是否遇到 `=`
        var i = rest.startIndex
        while i < rest.endIndex {
            let c = rest[i]
            if c == "." {
                // class (可能有 chain: .a.b.c)
                i = rest.index(after: i)
                var cls = ""
                while i < rest.endIndex {
                    let cc = rest[i]
                    if cc == "." || cc == "#" || cc == "(" || cc == " " || cc == "=" || cc == "!" { break }
                    cls.append(cc)
                    i = rest.index(after: i)
                }
                // 合并现有 class
                if let idx = attrs.firstIndex(where: { $0.0 == "class" }) {
                    if let old = attrs[idx].1 as? String { attrs[idx] = ("class", "\(old) \(cls)") }
                } else {
                    attrs.append(("class", cls))
                }
            } else if c == "#" {
                i = rest.index(after: i)
                var id = ""
                while i < rest.endIndex {
                    let cc = rest[i]
                    if cc == "." || cc == "#" || cc == "(" || cc == " " || cc == "=" || cc == "!" { break }
                    id.append(cc)
                    i = rest.index(after: i)
                }
                attrs.append(("id", id))
            } else if c == "(" {
                // 属性块
                if let close = matchBracket(rest, openIdx: i) {
                    let attrStr = String(rest[rest.index(after: i)..<close])
                    parseAttrs(attrStr, into: &attrs, attributeBlocks: &attributeBlocks)
                    i = rest.index(after: close)
                } else {
                    break
                }
            } else if c == "&" {
                // &attributes({...})
                if rest[i...].hasPrefix("&attributes(") {
                    if let close = matchBracket(rest, openIdx: rest.index(i, offsetBy: 12)) {
                        let arg = String(rest[rest.index(i, offsetBy: 13)..<close])
                        attributeBlocks.append(arg)
                        i = rest.index(after: close)
                    } else { break }
                } else { break }
            } else if c == "!" {
                // != 表达式 - 必须是 != 后跟空格或字符串结尾
                if rest[i...].hasPrefix("!=") {
                    // 验证下一个是空格, 或这是表达式的开始
                    let nextIdx = rest.index(i, offsetBy: 2)
                    if nextIdx >= rest.endIndex || rest[nextIdx] == " " || rest[nextIdx] == "\t" {
                        bangAssignIdx = i
                        break
                    } else {
                        consumed.append(c)
                        i = rest.index(after: i)
                    }
                } else {
                    consumed.append(c)
                    i = rest.index(after: i)
                }
            } else if c == "=" {
                // = 表达式
                assignIdxAfterAttrs = i
                i = rest.index(after: i)
                break
            } else if c == ":" {
                // 冒号语法: `li: a(href=...)` - 记录位置, 跳出
                colonIdxAfterAttrs = i
                i = rest.index(after: i)
                break
            } else if c == " " || c == "\t" {
                // 可能是行内文本 (简化为: 仅处理纯 tag, 文本节点另行处理)
                break
            } else {
                consumed.append(c)
                i = rest.index(after: i)
            }
        }

        // 行内文本 (例如 `p hello` 或 `p= expr`)
        var inlineText: String? = nil
        var inlineExpr: PugExpression? = nil
        var colonChild: String? = nil  // `:` 后面的内容 (例如 `a(href=...) Home`)
        // 从 i 开始 (剩余 rest)
        if let cIdx = colonIdxAfterAttrs {
            // 冒号语法: 冒号后全部是 child 元素规格
            let afterColon = String(rest[rest.index(after: cIdx)...]).trimmingCharacters(in: .init(charactersIn: " "))
            if !afterColon.isEmpty {
                colonChild = afterColon
            }
        } else if let aIdx = assignIdxAfterAttrs {
            // = 表达式: `title= page.title` → 表达式
            let afterEq = String(rest[rest.index(after: aIdx)...]).trimmingCharacters(in: .whitespaces)
            inlineExpr = PugExpression(afterEq, raw: false)
        } else if let bIdx = bangAssignIdx {
            // != 表达式: `title!= page.title` → 原始表达式
            let afterBang = String(rest[rest.index(after: bIdx)...]).trimmingCharacters(in: .whitespaces)
            // 跳过可选的 '=' 后跟空格
            let expr: String
            if afterBang.hasPrefix("=") {
                expr = String(afterBang.dropFirst()).trimmingCharacters(in: .whitespaces)
            } else {
                expr = afterBang
            }
            inlineExpr = PugExpression(expr, raw: true)
        } else if i < rest.endIndex {
            let after = String(rest[i...])
            let t = after.trimmingCharacters(in: .init(charactersIn: " "))
            if !t.isEmpty {
                inlineText = t
            }
        }

        // 解析缩进 body
        var body: [PugNode] = []
        var selfClosing = false
        // (img/) 形式 - 不支持行尾斜杠, 跳过
        body = parseBlockAtIndent(indent + 1)

        // 处理 colon 语法: `li: a(href="/") Home` → li 包含 a + text
        if let childSpec = colonChild {
            let (childEl, trailingText) = parseColonChild(childSpec, parentIndent: indent)
            if let child = childEl {
                body.append(child)
                if let txt = trailingText, !txt.isEmpty {
                    body.append(PugText(txt))
                }
            }
        }

        let el = PugElement(tag: tag, attrs: attrs, attributeBlocks: attributeBlocks, body: body, selfClosing: selfClosing)

        // 包装行内表达式/文本: inlineExpr/inlineText 应该作为 el 的 body 内容, 不是 sibling
        if let e = inlineExpr {
            var newBody = body
            newBody.append(e)
            return PugElement(tag: tag, attrs: attrs, attributeBlocks: attributeBlocks, body: newBody, selfClosing: selfClosing)
        }
        if let t = inlineText, !t.isEmpty {
            // 把 inlineText 作为 el 的 body 第一个元素 (而不是兄弟)
            var newBody = body
            newBody.insert(PugText(t), at: 0)
            return PugElement(tag: tag, attrs: attrs, attributeBlocks: attributeBlocks, body: newBody, selfClosing: selfClosing)
        }
        return el
    }

    /// 解析 `:` 后面的子元素规格: `a(href=...) Home` 或 `a(href=...)` 或 `a(href=...)= expr`
    private func parseColonChild(_ s: String, parentIndent: Int) -> (PugNode?, String?) {
        // 把 s 当作 Pug 元素行解析
        // 简化: 找到第一个空格 (不在括号内), 分割为 element-spec 和 trailing
        var depth = 0
        var splitIdx: String.Index? = nil
        for i in s.indices {
            let c = s[i]
            if c == "(" { depth += 1 }
            else if c == ")" { depth -= 1 }
            else if c == " " && depth == 0 {
                splitIdx = i
                break
            }
        }
        var elementSpec: String
        var trailing: String?
        if let idx = splitIdx {
            elementSpec = String(s[..<idx])
            trailing = String(s[s.index(after: idx)...])
            // 如果 elementSpec 末尾是 `=` 或 `!=`, 把它们合并到 trailing (这是 inline = expr)
            if elementSpec.hasSuffix("=") && !elementSpec.hasSuffix("==") {
                trailing = "= " + (trailing ?? "")
                elementSpec = String(elementSpec.dropLast())
            } else if elementSpec.hasSuffix("!=") {
                trailing = "!= " + (trailing ?? "")
                elementSpec = String(elementSpec.dropLast(2))
            }
        } else {
            elementSpec = s
            trailing = nil
        }
        // 解析为 element
        guard isElementStart(elementSpec) else { return (nil, trailing) }
        let child = parseElementFromString(elementSpec, indent: parentIndent)
        // 如果 trailing 以 `=` 或 `!=` 开头, 这是 child 的 inline = expr
        if let t = trailing {
            let tTrim = t.trimmingCharacters(in: .init(charactersIn: " "))
            if tTrim == "=" {
                return (child, nil)
            } else if tTrim.hasPrefix("= ") {
                let expr = String(tTrim.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                if let el = child as? PugElement {
                    var newBody = el.body
                    newBody.append(PugExpression(expr, raw: false))
                    let newChild = PugElement(tag: el.tag, attrs: el.attrs, attributeBlocks: el.attributeBlocks, body: newBody, selfClosing: el.selfClosing)
                    return (newChild, nil)
                }
            } else if tTrim == "!=" {
                return (child, nil)
            } else if tTrim.hasPrefix("!= ") {
                let expr = String(tTrim.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                if let el = child as? PugElement {
                    var newBody = el.body
                    newBody.append(PugExpression(expr, raw: true))
                    let newChild = PugElement(tag: el.tag, attrs: el.attrs, attributeBlocks: el.attributeBlocks, body: newBody, selfClosing: el.selfClosing)
                    return (newChild, nil)
                }
            }
        }
        return (child, trailing)
    }

    /// 从字符串解析元素, 不依赖 pos/lines. 仅用于冒号语法.
    private func parseElementFromString(_ s: String, indent: Int) -> PugNode? {
        var rest = s
        var tag = "div"
        if let first = rest.first, first.isLetter {
            var name = ""
            var i = rest.startIndex
            while i < rest.endIndex {
                let c = rest[i]
                if c.isLetter || c.isNumber || c == "-" || c == "_" {
                    name.append(c)
                    i = rest.index(after: i)
                } else { break }
            }
            tag = name
            rest = String(rest[i...])
        }
        // 解析属性
        var attrs: [(String, Any?)] = []
        var attributeBlocks: [String] = []
        var i = rest.startIndex
        while i < rest.endIndex {
            let c = rest[i]
            if c == "." {
                i = rest.index(after: i)
                var cls = ""
                while i < rest.endIndex {
                    let cc = rest[i]
                    if cc == "." || cc == "#" || cc == "(" || cc == " " || cc == "=" { break }
                    cls.append(cc)
                    i = rest.index(after: i)
                }
                if let idx = attrs.firstIndex(where: { $0.0 == "class" }) {
                    if let old = attrs[idx].1 as? String { attrs[idx] = ("class", "\(old) \(cls)") }
                } else {
                    attrs.append(("class", cls))
                }
            } else if c == "#" {
                i = rest.index(after: i)
                var id = ""
                while i < rest.endIndex {
                    let cc = rest[i]
                    if cc == "." || cc == "#" || cc == "(" || cc == " " || cc == "=" { break }
                    id.append(cc)
                    i = rest.index(after: i)
                }
                attrs.append(("id", id))
            } else if c == "(" {
                if let close = matchBracket(rest, openIdx: i) {
                    let attrStr = String(rest[rest.index(after: i)..<close])
                    parseAttrs(attrStr, into: &attrs, attributeBlocks: &attributeBlocks)
                    i = rest.index(after: close)
                } else { break }
            } else if c == "&" {
                if rest[i...].hasPrefix("&attributes(") {
                    if let close = matchBracket(rest, openIdx: rest.index(i, offsetBy: 12)) {
                        let arg = String(rest[rest.index(i, offsetBy: 13)..<close])
                        attributeBlocks.append(arg)
                        i = rest.index(after: close)
                    } else { break }
                } else { break }
            } else if c == " " || c == "\t" {
                break
            } else {
                i = rest.index(after: i)
            }
        }
        return PugElement(tag: tag, attrs: attrs, attributeBlocks: attributeBlocks, body: [], selfClosing: false)
    }

    private func parseAttrs(_ s: String, into attrs: inout [(String, Any?)], attributeBlocks: inout [String]) {
        // (a=1, b=2, c, class=['a', 'b'], &attributes({...}))
        // 简化: 按顶层逗号分隔
        let parts = splitTopLevelComma(s)
        for p in parts {
            let t = p.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { continue }
            if t.hasPrefix("&attributes(") {
                if let open = t.firstIndex(of: "(") {
                    if let close = matchBracket(t, openIdx: open) {
                        attributeBlocks.append(String(t[t.index(after: open)..<close]))
                    }
                }
                continue
            }
            if let eq = t.firstIndex(of: "=") {
                let k = String(t[..<eq]).trimmingCharacters(in: .whitespaces)
                let v = String(t[t.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
                attrs.append((k, parseAttrValue(v)))
            } else {
                // 布尔属性
                attrs.append((t, true))
            }
        }
    }

    private func parseAttrValue(_ s: String) -> Any {
        let t = s.trimmingCharacters(in: .whitespaces)
        if (t.hasPrefix("'") && t.hasSuffix("'")) || (t.hasPrefix("\"") && t.hasSuffix("\"")) {
            return String(t.dropFirst().dropLast())
        }
        if t == "true" { return true }
        if t == "false" { return false }
        if t == "null" { return NSNull() }
        if let i = Int(t) { return i }
        if let d = Double(t) { return d }
        // 其它 (表达式) - 用 PugAttrExpr 包装, 渲染时求值
        return PugAttrExpr(t)
    }

    /// 文本行: `| text` / `= expr` / `!= expr` / `.` / 纯文本块
    private func parsePlainLine(_ s: String, indent: Int) -> PugNode? {
        if s == "." {
            // . 纯文本块: 后面所有行作为文本直到缩进变化
            return parseDotTextBlock(indent: indent)
        }
        if s.hasPrefix("| ") || s == "|" {
            let text = s == "|" ? "" : String(s.dropFirst(2))
            return PugText(text)
        }
        if s.hasPrefix("= ") || s == "=" {
            let expr = s == "=" ? "" : String(s.dropFirst(2))
            return PugExpression(expr.trimmingCharacters(in: .whitespaces), raw: false)
        }
        if s.hasPrefix("!= ") || s == "!=" {
            let expr = s == "!=" ? "" : String(s.dropFirst(3))
            return PugExpression(expr.trimmingCharacters(in: .whitespaces), raw: true)
        }
        // if / else if / else
        if s == "if" || s.hasPrefix("if ") {
            let cond = String(s.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            // 去掉尾部可能的 " {"
            let cond2: String
            if let brace = cond.firstIndex(of: "{") { cond2 = String(cond[..<brace]).trimmingCharacters(in: .whitespaces) }
            else { cond2 = cond }
            let body = parseBlockAtIndent(indent + 1)
            let (elseBody, _) = parseElseChain(indent: indent, stopBlock: false)
            return PugConditional(expr: cond2, body: body, elseBody: elseBody, isUnless: false)
        }
        if s == "unless" || s.hasPrefix("unless ") {
            let cond = String(s.dropFirst("unless".count)).trimmingCharacters(in: .whitespaces)
            let cond2: String
            if let brace = cond.firstIndex(of: "{") { cond2 = String(cond[..<brace]).trimmingCharacters(in: .whitespaces) }
            else { cond2 = cond }
            let body = parseBlockAtIndent(indent + 1)
            let (elseBody, _) = parseElseChain(indent: indent, stopBlock: false)
            return PugConditional(expr: cond2, body: body, elseBody: elseBody, isUnless: true)
        }
        if s == "else" || s == "else {" {
            // 不应该独立出现; 忽略
            return nil
        }
        if s.hasPrefix("else if ") {
            // 不应该独立出现; 忽略
            return nil
        }
        // each item in list  /  each val, key in obj
        if s == "each" || s.hasPrefix("each ") {
            return parseEach(s, indent: indent)
        }
        // while
        if s == "while" || s.hasPrefix("while ") {
            let expr = String(s.dropFirst("while".count)).trimmingCharacters(in: .whitespaces)
            let expr2: String
            if let brace = expr.firstIndex(of: "{") { expr2 = String(expr[..<brace]).trimmingCharacters(in: .whitespaces) }
            else { expr2 = expr }
            let body = parseBlockAtIndent(indent + 1)
            return PugWhile(expr: expr2, body: body)
        }
        // case
        if s == "case" || s.hasPrefix("case ") {
            return parseCase(s, indent: indent)
        }
        if s == "when" || s.hasPrefix("when ") {
            // 不应该独立出现
            return nil
        }
        if s == "default" {
            return nil
        }
        // mixin 调用: +name(args)
        if s.hasPrefix("+") {
            return parseMixinCall(s, indent: indent)
        }
        // filter: :name
        if s.hasPrefix(":") {
            return parseFilter(s, indent: indent)
        }
        return nil
    }

    private func parseElseChain(indent: Int, stopBlock: Bool) -> ([PugNode]?, Bool) {
        // 偷看下一行, 如果是 else / else if, 解析; 否则返回 (nil, false)
        guard pos < lines.count else { return (nil, false) }
        let nextRaw = lines[pos]
        let nextTrim = nextRaw.trimmingCharacters(in: .init(charactersIn: " "))
        if nextTrim.isEmpty { return (nil, false) }
        let nextIndent = leadingSpaces(nextRaw)
        if nextIndent != indent { return (nil, false) }
        if nextTrim == "else" || nextTrim == "else {" {
            pos += 1
            let body = parseBlockAtIndent(indent + 1)
            return (body, false)
        }
        if nextTrim.hasPrefix("else if ") || nextTrim.hasPrefix("else if(") {
            pos += 1
            // 把 else if 当作新的 conditional
            let cond = String(nextTrim.dropFirst("else if".count)).trimmingCharacters(in: .whitespaces)
            let cond2: String
            if let brace = cond.firstIndex(of: "{") { cond2 = String(cond[..<brace]).trimmingCharacters(in: .whitespaces) }
            else { cond2 = cond }
            let body = parseBlockAtIndent(indent + 1)
            let (elseBody2, _) = parseElseChain(indent: indent, stopBlock: false)
            // 嵌套为 single conditional
            let nested = PugConditional(expr: cond2, body: body, elseBody: elseBody2, isUnless: false)
            return ([nested], false)
        }
        return (nil, false)
    }

    private func parseEach(_ s: String, indent: Int) -> PugNode? {
        // each item in list  /  each val, key in obj
        let after = String(s.dropFirst("each".count)).trimmingCharacters(in: .whitespaces)
        if let inRange = after.range(of: " in ") {
            let lhs = String(after[..<inRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            let expr = String(after[inRange.upperBound...]).trimmingCharacters(in: .whitespaces)
            let expr2: String
            if let brace = expr.firstIndex(of: "{") { expr2 = String(expr[..<brace]).trimmingCharacters(in: .whitespaces) }
            else { expr2 = expr }
            let varNames = lhs.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            let body = parseBlockAtIndent(indent + 1)
            return PugEach(varNames: varNames, expr: expr2, body: body)
        }
        return nil
    }

    private func parseCase(_ s: String, indent: Int) -> PugNode? {
        let after = String(s.dropFirst("case".count)).trimmingCharacters(in: .whitespaces)
        let body = parseCaseBlock(indent: indent)
        return PugCase(expr: after, whens: body.whens, defaultBody: body.defaultBody)
    }

    private func parseCaseBlock(indent: Int) -> (whens: [PugWhen], defaultBody: [PugNode]?) {
        var whens: [PugWhen] = []
        var defaultBody: [PugNode]? = nil
        while pos < lines.count {
            let raw = lines[pos]
            let trimmed = raw.trimmingCharacters(in: .init(charactersIn: " "))
            if trimmed.isEmpty { pos += 1; continue }
            let ind = leadingSpaces(raw)
            if ind <= indent { break }
            if ind != indent + 1 { break }
            if trimmed == "default" {
                pos += 1
                defaultBody = parseBlockAtIndent(ind + 1)
                break
            }
            if trimmed.hasPrefix("when ") {
                pos += 1
                let cond = String(trimmed.dropFirst("when".count)).trimmingCharacters(in: .whitespaces)
                let body = parseBlockAtIndent(ind + 1)
                whens.append(PugWhen(cond: cond, body: body))
                continue
            }
            break
        }
        return (whens, defaultBody)
    }

    private func parseMixinCall(_ s: String, indent: Int) -> PugNode? {
        // +name(arg1, arg2)
        let after = String(s.dropFirst()).trimmingCharacters(in: .whitespaces)
        var name = ""
        var i = after.startIndex
        while i < after.endIndex {
            let c = after[i]
            if c == "(" || c == " " || c == "\t" { break }
            name.append(c)
            i = after.index(after: i)
        }
        var args: [Any] = []
        if i < after.endIndex && after[i] == "(" {
            if let close = matchBracket(after, openIdx: i) {
                let argStr = String(after[after.index(after: i)..<close])
                for part in splitTopLevelComma(argStr) {
                    let t = part.trimmingCharacters(in: .whitespaces)
                    if t.isEmpty { continue }
                    // 字面量
                    if (t.hasPrefix("'") && t.hasSuffix("'")) || (t.hasPrefix("\"") && t.hasSuffix("\"")) {
                        args.append(String(t.dropFirst().dropLast()))
                    } else if let i = Int(t) {
                        args.append(i)
                    } else if t == "true" { args.append(true) }
                    else if t == "false" { args.append(false) }
                    else if t == "null" { args.append(NSNull()) }
                    else { args.append(t) }  // 表达式
                }
            }
        }
        return PugMixinCall(name: name, args: args)
    }

    private func parseFilter(_ s: String, indent: Int) -> PugNode? {
        let name = String(s.dropFirst()).trimmingCharacters(in: .whitespaces)
        let body = parseBlockAtIndent(indent + 1)
        return PugFilter(name: name, body: body)
    }

    private func parseDotTextBlock(indent: Int) -> PugNode? {
        // . 标记纯文本块, 直到缩进变小
        var out: [PugNode] = []
        while pos < lines.count {
            let raw = lines[pos]
            let trimmed = raw.trimmingCharacters(in: .init(charactersIn: " "))
            if trimmed.isEmpty { pos += 1; continue }
            let ind = leadingSpaces(raw)
            if ind <= indent { break }
            out.append(PugLiteralText(trimmed))
            pos += 1
        }
        // 合并为单个 PugText
        let text = out.map { ($0 as? PugLiteralText)?.text ?? "" }.joined(separator: "\n")
        return PugText(text)
    }

    // MARK: - 工具

    private func isElementStart(_ s: String) -> Bool {
        // 以字母 / . / # 开头, 且不是纯文本指令
        guard let f = s.first else { return false }
        if f.isLetter {
            // 关键字指令前缀不应是元素
            let keywords = ["if", "else", "elseif", "elif", "unless", "each", "while", "case", "when", "default", "block", "extends", "include", "mixin", "append", "prepend"]
            for kw in keywords {
                if s == kw { return false }
                if s.hasPrefix(kw + " ") { return false }
            }
            return true
        }
        return f == "." || f == "#"
    }

    private func leadingSpaces(_ s: String) -> Int {
        var n = 0
        for c in s {
            if c == " " { n += 1 } else { break }
        }
        return n
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
                else if c == ")" { depth -= 1; if depth == 0 { return i } }
            }
            i = s.index(after: i)
        }
        return nil
    }

    private func splitTopLevelComma(_ s: String) -> [String] {
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
}
