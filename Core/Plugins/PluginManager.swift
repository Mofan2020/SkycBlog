import Foundation
import JavaScriptCore

/// 插件系统：基于 JavaScriptCore 加载 scripts/*.js。
public final class PluginManager {
    public let projectRoot: String
    public private(set) var loaded: [String] = []
    public private(set) var errors: [(file: String, message: String)] = []
    public var site: [String: Any] = [:]
    public var pages: [Page] = []
    public var context: [String: [[String: Any]]] = [:]   // 每个页面的渲染上下文

    private var contextJS: JSContext!
    public var contextJSValue: Any? { contextJS.objectForKeyedSubscript("site")?.toObject() as? [String: Any] }
    private var hookCallbacks: [String: [JSValue]] = [:]

    public init(projectRoot: String) {
        self.projectRoot = projectRoot
        self.contextJS = JSContext()!
        setupBridge()
    }

    public func loadAll() {
        let dir = (projectRoot as NSString).appendingPathComponent("scripts")
        guard FileManager.default.fileExists(atPath: dir) else { return }
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
        for f in files where f.hasSuffix(".js") && !f.hasSuffix(".disabled") {
            let path = (dir as NSString).appendingPathComponent(f)
            if let src = try? String(contentsOfFile: path, encoding: .utf8) {
                contextJS.exceptionHandler = { [weak self] ctx, exc in
                    let msg = exc?.toString() ?? "未知错误"
                    self?.errors.append((file: f, message: msg))
                    Log.warn("插件 \(f) 错误：\(msg)")
                }
                contextJS.evaluateScript(src)
                loaded.append(f)
            }
        }
    }

    private func setupBridge() {
        // site 全局
        let siteProxy: @convention(block) () -> [String: Any] = { [weak self] in self?.site ?? [:] }
        contextJS.setObject(unsafeBitCast(siteProxy, to: AnyObject.self), forKeyedSubscript: "site" as NSString)
        // hook
        let hookFn: @convention(block) (String, JSValue) -> Void = { [weak self] (name, cb) in
            guard let self = self else { return }
            self.hookCallbacks[name, default: []].append(cb)
        }
        contextJS.setObject(unsafeBitCast(hookFn, to: AnyObject.self), forKeyedSubscript: "hook" as NSString)
        // log
        let logFn: @convention(block) (String) -> Void = { msg in Log.info("[plugin] \(msg)") }
        contextJS.setObject(unsafeBitCast(logFn, to: AnyObject.self), forKeyedSubscript: "log" as NSString)
        // readFile
        let readFn: @convention(block) (String) -> String? = { [weak self] p in
            guard let root = self?.projectRoot else { return nil }
            let abs = (p.hasPrefix("/") ? p : (root as NSString).appendingPathComponent(p))
            return try? String(contentsOfFile: abs, encoding: .utf8)
        }
        contextJS.setObject(unsafeBitCast(readFn, to: AnyObject.self), forKeyedSubscript: "readFile" as NSString)
        // writeFile
        let writeFn: @convention(block) (String, String) -> Bool = { [weak self] (p, content) in
            guard let root = self?.projectRoot else { return false }
            let abs = (p.hasPrefix("/") ? p : (root as NSString).appendingPathComponent(p))
            return FSUtil.writeText(content, to: abs)
        }
        contextJS.setObject(unsafeBitCast(writeFn, to: AnyObject.self), forKeyedSubscript: "writeFile" as NSString)
    }

    /// 触发钩子。callback 参数为 (site) 或 (site, pages) 或 (site, page, context)
    public func fire(_ name: String, args: [Any] = []) {
        for cb in hookCallbacks[name] ?? [] {
            var jsArgs: [Any] = []
            jsArgs.append(convertToJS(site))
            for a in args { jsArgs.append(convertToJS(a)) }
            _ = cb.call(withArguments: jsArgs)
            // 把 site 写回
            if let s = contextJS.objectForKeyedSubscript("site")?.toObject() as? [String: Any] {
                site = s
            }
        }
    }

    private func convertToJS(_ value: Any) -> Any {
        if let s = value as? String { return s }
        if let i = value as? Int { return i }
        if let d = value as? Double { return d }
        if let b = value as? Bool { return b }
        if value is NSNull { return NSNull() }
        if let date = value as? Date { return DateUtil.iso.string(from: date) }
        if let dict = value as? [String: Any] {
            // JSON 不接受 Date；先把 Date 转 String
            var clean: [String: Any] = [:]
            for (k, v) in dict { clean[k] = normalizeForJSON(v) }
            if let data = try? JSONSerialization.data(withJSONObject: clean, options: [.fragmentsAllowed]),
               let str = String(data: data, encoding: .utf8) {
                return contextJS.evaluateScript("(\(str))") ?? NSNull()
            }
            return NSNull()
        }
        if let arr = value as? [Any] {
            let clean = arr.map { normalizeForJSON($0) }
            if let data = try? JSONSerialization.data(withJSONObject: clean, options: [.fragmentsAllowed]),
               let str = String(data: data, encoding: .utf8) {
                return contextJS.evaluateScript("(\(str))") ?? NSNull()
            }
            return NSNull()
        }
        return String(describing: value)
    }

    private func normalizeForJSON(_ v: Any) -> Any {
        if let d = v as? Date { return DateUtil.iso.string(from: d) }
        if let dict = v as? [String: Any] {
            var out: [String: Any] = [:]
            for (k, val) in dict { out[k] = self.normalizeForJSON(val) }
            return out
        }
        if let arr = v as? [Any] { return arr.map { self.normalizeForJSON($0) } }
        return v
    }

    public func resetErrors() { errors.removeAll() }
}
