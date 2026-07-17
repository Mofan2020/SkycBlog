import Foundation

// MARK: - Pug 节点类型

public protocol PugNode {}

/// 文字块 (内容是 PugText + 嵌套, 通过 `| text` 或纯文本)
public final class PugText: PugNode {
    public let text: String
    public init(_ text: String) { self.text = text }
}

/// 纯字面量文本 (在 `case` / 文本中)
public final class PugLiteralText: PugNode {
    public let text: String
    public init(_ text: String) { self.text = text }
}

/// 元素标签
public final class PugElement: PugNode {
    public let tag: String                       // "div" / "a" / "span"
    public let attrs: [(String, Any?)]           // 属性列表 (name, value)
    public let attributeBlocks: [String]         // &attributes(expr) 表达式
    public let body: [PugNode]                   // 子节点
    public let selfClosing: Bool                 // (img/) 形式
    public init(tag: String, attrs: [(String, Any?)], attributeBlocks: [String], body: [PugNode], selfClosing: Bool) {
        self.tag = tag
        self.attrs = attrs
        self.attributeBlocks = attributeBlocks
        self.body = body
        self.selfClosing = selfClosing
    }
}

/// 代码: `- var x = 1` / `- if cond`
public final class PugCode: PugNode {
    public let expr: String
    public init(_ expr: String) { self.expr = expr }
}

/// 条件
public final class PugConditional: PugNode {
    public let expr: String
    public let body: [PugNode]
    public let elseBody: [PugNode]?
    public let isUnless: Bool
    public init(expr: String, body: [PugNode], elseBody: [PugNode]?, isUnless: Bool) {
        self.expr = expr
        self.body = body
        self.elseBody = elseBody
        self.isUnless = isUnless
    }
}

/// 循环: `each item in list`
public final class PugEach: PugNode {
    public let varNames: [String]                // ["item"] or ["v", "k"] (for object)
    public let expr: String
    public let body: [PugNode]
    public init(varNames: [String], expr: String, body: [PugNode]) {
        self.varNames = varNames
        self.expr = expr
        self.body = body
    }
}

/// while
public final class PugWhile: PugNode {
    public let expr: String
    public let body: [PugNode]
    public init(expr: String, body: [PugNode]) {
        self.expr = expr
        self.body = body
    }
}

/// case
public final class PugCase: PugNode {
    public let expr: String
    public let whens: [PugWhen]
    public let defaultBody: [PugNode]?
    public init(expr: String, whens: [PugWhen], defaultBody: [PugNode]?) {
        self.expr = expr
        self.whens = whens
        self.defaultBody = defaultBody
    }
}

public final class PugWhen: PugNode {
    public let cond: String                      // 字面量或表达式, 逗号分隔
    public let body: [PugNode]
    public init(cond: String, body: [PugNode]) {
        self.cond = cond
        self.body = body
    }
}

/// include
public final class PugInclude: PugNode {
    public let path: String
    public init(_ path: String) { self.path = path }
}

/// extends
public final class PugExtend: PugNode {
    public let path: String
    public init(_ path: String) { self.path = path }
}

/// block
public final class PugBlock: PugNode {
    public let name: String
    public let body: [PugNode]
    public let appendMode: Bool
    public let prependMode: Bool
    public init(name: String, body: [PugNode], appendMode: Bool, prependMode: Bool) {
        self.name = name
        self.body = body
        self.appendMode = appendMode
        self.prependMode = prependMode
    }
}

/// mixin 定义
public final class PugMixinDef: PugNode {
    public let name: String
    public let paramNames: [String]
    public let hasRest: Bool
    public let body: [PugNode]
    public init(name: String, paramNames: [String], hasRest: Bool, body: [PugNode]) {
        self.name = name
        self.paramNames = paramNames
        self.hasRest = hasRest
        self.body = body
    }
}

/// mixin 调用
public final class PugMixinCall: PugNode {
    public let name: String
    public let args: [Any]                       // String 表达式 或 literal
    public init(name: String, args: [Any]) {
        self.name = name
        self.args = args
    }
}

/// filter: `:markdown-it ...`
public final class PugFilter: PugNode {
    public let name: String
    public let body: [PugNode]
    public init(name: String, body: [PugNode]) {
        self.name = name
        self.body = body
    }
}

/// 序列节点: 包含多个并列子节点
public final class PugSequence: PugNode {
    public let nodes: [PugNode]
    public init(_ nodes: [PugNode]) { self.nodes = nodes }
}

/// 表达式: `= expr` (转义输出) 或 `!= expr` (原始输出)
public final class PugExpression: PugNode {
    public let expr: String
    public let raw: Bool  // true = ! = (不转义), false = = (转义)
    public init(_ expr: String, raw: Bool = false) {
        self.expr = expr
        self.raw = raw
    }
}

/// 属性值中的表达式 (例如 `a(href=post.permalink)`), 在渲染时求值
public struct PugAttrExpr {
    public let expr: String
    public init(_ expr: String) { self.expr = expr }
}

/// 文档类型
public final class PugDoctype: PugNode {
    public let value: String  // "html", "xml", "transitional", 等
    public init(_ value: String) { self.value = value }
}
