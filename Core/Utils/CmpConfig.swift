import Foundation

/// 用于主题配置编辑器的"保顺序 + 注释保留"配置数据模型.
/// 与 [String: Any] 不同, 这里:
///   1. 顶层/嵌套 dict 都用 CmpMapping, 保留 key 插入顺序
///   2. 每条 key 都附 leadingComments (上方注释行数组) + inlineComment (同行尾注释)
///   3. 列表项也可以带注释
public enum CmpValue {
    case scalar(Any)          // 字符串/数字/布尔/NSNull
    case mapping(CmpMapping)
    case list([CmpListItem])
}

public struct CmpListItem {
    public var value: CmpValue
    public var leadingComments: [String] = []
    public var inlineComment: String? = nil

    public init(value: CmpValue, leadingComments: [String] = [], inlineComment: String? = nil) {
        self.value = value
        self.leadingComments = leadingComments
        self.inlineComment = inlineComment
    }
}

public struct CmpEntry {
    public var key: String
    public var value: CmpValue
    public var leadingComments: [String] = []
    public var inlineComment: String? = nil

    public init(key: String, value: CmpValue, leadingComments: [String] = [], inlineComment: String? = nil) {
        self.key = key
        self.value = value
        self.leadingComments = leadingComments
        self.inlineComment = inlineComment
    }
}

public struct CmpMapping {
    public var entries: [CmpEntry] = []
    /// 没有挂在任何 key 上方的"游离"注释行 (YAML 中常见文件头部大段说明)
    public var leadingComments: [String] = []

    public init(entries: [CmpEntry] = [], leadingComments: [String] = []) {
        self.entries = entries
        self.leadingComments = leadingComments
    }

    public var keys: [String] { entries.map { $0.key } }

    public func entry(forKey key: String) -> CmpEntry? {
        entries.first(where: { $0.key == key })
    }

    public mutating func set(_ key: String, value: CmpValue) {
        if let i = entries.firstIndex(where: { $0.key == key }) {
            entries[i].value = value
        } else {
            entries.append(CmpEntry(key: key, value: value))
        }
    }

    public mutating func remove(_ key: String) {
        entries.removeAll(where: { $0.key == key })
    }

    /// 转化为 [String: Any] (扁平化, 注释丢弃, 用于不关心注释的旧代码)
    public func toDict() -> [String: Any] {
        var d: [String: Any] = [:]
        for e in entries {
            d[e.key] = CmpValue.toAny(e.value)
        }
        return d
    }
}

extension CmpValue {
    public static func toAny(_ v: CmpValue) -> Any {
        switch v {
        case .scalar(let s): return s
        case .mapping(let m): return m.toDict()
        case .list(let items): return items.map { toAny($0.value) }
        }
    }
}

extension CmpMapping {
    /// 从 [String: Any] 构造 (无注释, 顺序按字典序)
    public static func from(_ dict: [String: Any]) -> CmpMapping {
        var m = CmpMapping()
        for k in dict.keys.sorted() {
            m.entries.append(CmpEntry(key: k, value: CmpValue.from(dict[k])))
        }
        return m
    }
}

extension CmpValue {
    public static func from(_ any: Any?) -> CmpValue {
        guard let v = any else { return .scalar(NSNull()) }
        if let m = v as? [String: Any] { return .mapping(CmpMapping.from(m)) }
        if let arr = v as? [Any] {
            return .list(arr.map { CmpListItem(value: CmpValue.from($0)) })
        }
        return .scalar(v)
    }
}
