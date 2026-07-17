import Foundation

/// 主题种类
public enum ThemeKind: String, Codable, CaseIterable {
    case skyc   // SkycBlog 原生主题
    case hexo   // Hexo 主题（EJS/Swig/Pug 由 HexoThemeAdapter 接管构建）
    case hugo   // Hugo 主题（Go template 由 HugoThemeAdapter 接管构建）
    case unknown

    public var displayName: String {
        switch self {
        case .skyc:    return "SkycBlog"
        case .hexo:    return "Hexo"
        case .hugo:    return "Hugo"
        case .unknown: return "未知"
        }
    }

    public var systemImage: String {
        switch self {
        case .skyc:    return "paintbrush.fill"
        case .hexo:    return "leaf.fill"
        case .hugo:    return "bolt.fill"
        case .unknown: return "questionmark.circle"
        }
    }

    /// 是否在 SkycBlog 构建流程中真正参与构建。
    /// 现在 hexo/hugo 都已被对应 Adapter 完整接管, 不再是"识别但不参与"。
    public var supportsBuild: Bool {
        switch self {
        case .skyc, .hexo, .hugo:
            return true
        case .unknown:
            return false
        }
    }

    /// 简短的副标题 (UI 上用作"已支持 X"提示)
    public var buildCapability: String {
        switch self {
        case .skyc:  return "SkycBlog 原生模板"
        case .hexo:  return "EJS / Swig / Pug"
        case .hugo:  return "Go template"
        case .unknown: return "未识别"
        }
    }
}

/// 主题元信息（探测结果）
public struct ThemeInfo: Identifiable, Equatable {
    public let name: String
    public let kind: ThemeKind
    public let root: String
    public let configPath: String?       // theme.yaml / _config.yml
    public let templatesDir: String?     // SkycBlog 的 templates/、Hexo 的 layout/、Hugo 的 layouts/
    public let staticDir: String?
    public let description: String?
    public let version: String?
    public let author: String?

    public var id: String { name }
    public var isActive: Bool { false } // 由调用方（AppState）比较

    public static func == (lhs: ThemeInfo, rhs: ThemeInfo) -> Bool {
        lhs.name == rhs.name && lhs.kind == rhs.kind
    }
}

/// 主题管理：扫描、识别、列出。
public enum ThemeManager {
    public static func themeRoot(projectRoot: String, themeName: String) -> String {
        let p = (projectRoot as NSString).appendingPathComponent("themes/\(themeName)")
        return p
    }

    /// 如果用户项目缺主题目录，从内置数据展开默认主题。
    public static func copyDefaultIfMissing(projectRoot: String, themeName: String) {
        // 只对默认主题名 'default' 展开, 其他名字的用户主题不强制覆盖
        guard themeName == "default" else { return }
        let dst = (projectRoot as NSString).appendingPathComponent("themes/\(themeName)")
        if FileManager.default.fileExists(atPath: (dst as NSString).appendingPathComponent("theme.yaml")) {
            return
        }
        FSUtil.ensureDirectory(dst)
        EmbeddedTheme.materialize(targetDirectory: dst)
    }

    public static func bundleResourcePath(named: String) -> String? {
        let candidates = [
            Bundle.main.url(forResource: named, withExtension: nil),
            Bundle.main.resourceURL?.appendingPathComponent(named),
        ]
        for c in candidates {
            if let url = c, FileManager.default.fileExists(atPath: url.path) { return url.path }
        }
        let core = Bundle(identifier: "com.skyc8266.skycblog.SkycBlogCore")
        if let url = core?.url(forResource: named, withExtension: nil) {
            return url.path
        }
        for b in Bundle.allFrameworks + Bundle.allBundles {
            if let url = b.url(forResource: named, withExtension: nil) {
                return url.path
            }
        }
        return nil
    }

    /// 列出 themes/ 目录所有主题
    public static func listThemeNames(projectRoot: String) -> [String] {
        let dir = (projectRoot as NSString).appendingPathComponent("themes")
        guard FileManager.default.fileExists(atPath: dir) else { return [] }
        return (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
    }

    /// 列出所有主题详细信息，按 kind 分类
    public static func listThemes(projectRoot: String) -> [ThemeInfo] {
        let dir = (projectRoot as NSString).appendingPathComponent("themes")
        guard FileManager.default.fileExists(atPath: dir) else { return [] }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
        return names
            .filter { !$0.hasPrefix(".") }
            .map { name in
                let root = (dir as NSString).appendingPathComponent(name)
                return detectTheme(at: root, name: name)
            }
            .sorted { a, b in
                if a.kind == b.kind { return a.name < b.name }
                return a.kind.rawValue < b.kind.rawValue
            }
    }

    /// 根据签名文件判断主题类型
    public static func detectTheme(at root: String, name: String) -> ThemeInfo {
        let fm = FileManager.default
        let skycCfg = (root as NSString).appendingPathComponent("theme.yaml")
        let skycTpl = (root as NSString).appendingPathComponent("templates")
        let skycStatic = (root as NSString).appendingPathComponent("static")

        let hexoCfg = (root as NSString).appendingPathComponent("_config.yml")
        let hexoLayout = (root as NSString).appendingPathComponent("layout")
        let hexoSource = (root as NSString).appendingPathComponent("source")
        let hexoEJS = (root as NSString).appendingPathComponent("layout/index.ejs")
        let hexoSwig = (root as NSString).appendingPathComponent("layout/index.swig")
        let hexoPug = (root as NSString).appendingPathComponent("layout/index.pug")

        let hugoCfg = (root as NSString).appendingPathComponent("theme.toml")
        let hugoCfg2 = (root as NSString).appendingPathComponent("hugo.toml")
        let hugoLayouts = (root as NSString).appendingPathComponent("layouts")
        let hugoStatic = (root as NSString).appendingPathComponent("static")

        // 扫描 layout/ 里是否有 EJS / SWIG / Pug 模板
        func hasHexoTemplates() -> Bool {
            if fm.fileExists(atPath: hexoEJS) || fm.fileExists(atPath: hexoSwig) || fm.fileExists(atPath: hexoPug) { return true }
            // 扫描 layout/ 找任意 .ejs / .swig / .pug
            guard let items = try? fm.contentsOfDirectory(atPath: hexoLayout) else { return false }
            for it in items {
                let low = (it as NSString).pathExtension.lowercased()
                if low == "ejs" || low == "swig" || low == "pug" { return true }
                var isDir: ObjCBool = false
                let p = (hexoLayout as NSString).appendingPathComponent(it)
                fm.fileExists(atPath: p, isDirectory: &isDir)
                if isDir.boolValue {
                    if let sub = try? fm.contentsOfDirectory(atPath: p) {
                        for s in sub {
                            let l2 = (s as NSString).pathExtension.lowercased()
                            if l2 == "ejs" || l2 == "swig" || l2 == "pug" { return true }
                        }
                    }
                }
            }
            return false
        }

        // 优先级: Hexo(layout/*.ejs / .swig) > SkycBlog(theme.yaml) > Hugo(layouts/) > Hexo(纯 _config.yml)
        // 重要: layout/*.ejs 是 Hexo landscape 的明确签名, 比 theme.yaml 优先
        if hasHexoTemplates() {
            return ThemeInfo(
                name: name, kind: .hexo, root: root,
                configPath: fm.fileExists(atPath: hexoCfg) ? hexoCfg : nil,
                templatesDir: fm.fileExists(atPath: hexoLayout) ? hexoLayout : nil,
                staticDir: fm.fileExists(atPath: hexoSource) ? hexoSource : nil,
                description: readYAMLStringField(hexoCfg, "description"),
                version: readYAMLStringField(hexoCfg, "version"),
                author: readYAMLStringField(hexoCfg, "author")
            )
        }
        if fm.fileExists(atPath: skycCfg) || fm.fileExists(atPath: (skycTpl as NSString).appendingPathComponent("index.html")) {
            return ThemeInfo(
                name: name, kind: .skyc, root: root,
                configPath: fm.fileExists(atPath: skycCfg) ? skycCfg : nil,
                templatesDir: fm.fileExists(atPath: skycTpl) ? skycTpl : nil,
                staticDir: fm.fileExists(atPath: skycStatic) ? skycStatic : nil,
                description: readStringField(skycCfg, "description"),
                version: readStringField(skycCfg, "version"),
                author: readStringField(skycCfg, "author")
            )
        }
        // Hugo: layouts/ 是核心签名 (Hugo 主题必有)
        if fm.fileExists(atPath: hugoLayouts) || fm.fileExists(atPath: hugoCfg) || fm.fileExists(atPath: hugoCfg2) {
            return ThemeInfo(
                name: name, kind: .hugo, root: root,
                configPath: fm.fileExists(atPath: hugoCfg) ? hugoCfg : (fm.fileExists(atPath: hugoCfg2) ? hugoCfg2 : nil),
                templatesDir: fm.fileExists(atPath: hugoLayouts) ? hugoLayouts : nil,
                staticDir: fm.fileExists(atPath: hugoStatic) ? hugoStatic : nil,
                description: readTOMLStringField(fm.fileExists(atPath: hugoCfg) ? hugoCfg : (fm.fileExists(atPath: hugoCfg2) ? hugoCfg2 : ""), "description"),
                version: nil,
                author: nil
            )
        }
        // Hexo fallback: 仅有 _config.yml 或 layout/(无 .ejs) 仍然算 hexo (主题有 index.swig)
        if fm.fileExists(atPath: hexoCfg) || fm.fileExists(atPath: hexoLayout) {
            return ThemeInfo(
                name: name, kind: .hexo, root: root,
                configPath: fm.fileExists(atPath: hexoCfg) ? hexoCfg : nil,
                templatesDir: fm.fileExists(atPath: hexoLayout) ? hexoLayout : nil,
                staticDir: fm.fileExists(atPath: hexoSource) ? hexoSource : nil,
                description: readYAMLStringField(hexoCfg, "description"),
                version: readYAMLStringField(hexoCfg, "version"),
                author: readYAMLStringField(hexoCfg, "author")
            )
        }
        return ThemeInfo(
            name: name, kind: .unknown, root: root,
            configPath: nil, templatesDir: nil, staticDir: nil,
            description: nil, version: nil, author: nil
        )
    }

    /// 简化读取 SkycBlog theme.yaml 顶层 string
    private static func readStringField(_ path: String, _ key: String) -> String? {
        guard FileManager.default.fileExists(atPath: path),
              let text = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("\(key):") {
                var v = String(trimmed.dropFirst(key.count + 1)).trimmingCharacters(in: .whitespaces)
                if v.hasPrefix("\"") && v.hasSuffix("\"") { v = String(v.dropFirst().dropLast()) }
                if v.hasPrefix("'") && v.hasSuffix("'")  { v = String(v.dropFirst().dropLast()) }
                return v.isEmpty ? nil : v
            }
        }
        return nil
    }

    /// 读 Hexo _config.yml 顶层（Hexo 用 YAML 嵌套）
    private static func readYAMLStringField(_ path: String, _ key: String) -> String? {
        readStringField(path, key)
    }

    /// 读 Hugo theme.toml 顶层
    private static func readTOMLStringField(_ path: String, _ key: String) -> String? {
        guard !path.isEmpty,
              FileManager.default.fileExists(atPath: path),
              let text = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("\(key) ") || trimmed.hasPrefix("\(key)=") {
                guard let eqRange = trimmed.range(of: "=") else { continue }
                var v = String(trimmed[eqRange.upperBound...]).trimmingCharacters(in: .whitespaces)
                if v.hasPrefix("\"") && v.hasSuffix("\"") { v = String(v.dropFirst().dropLast()) }
                if v.hasPrefix("'") && v.hasSuffix("'")  { v = String(v.dropFirst().dropLast()) }
                return v.isEmpty ? nil : v
            }
        }
        return nil
    }

    // MARK: - 主题配置读写（让 UI 能直接修改 _config.yml / theme.yaml / theme.toml）

    /// 主题配置文件元信息
    public struct ThemeConfigFile {
        public let themeName: String
        public let themeKind: ThemeKind
        /// 配置文件相对 themes/<name>/ 的路径（例如 "_config.yml"）
        public let relativePath: String
        /// "yaml" / "toml" / "json"
        public let format: String
        /// 配置文件磁盘上的完整路径
        public let absolutePath: String
        /// 保留顺序 + 注释的配置树 (YAML 用 CmpMapping; TOML 在加载时构造一个等价的 CmpMapping
        /// —— 但没有精确注释保留, 仍是注释丢失的"兼容版").
        /// 始终非空: 加载失败时为空 CmpMapping.
        public var cmap: CmpMapping
        /// 原始文件全文（用于高级模式, 始终代表最近一次 save 或加载时的内容）
        public var rawText: String
        /// 便利: 旧 API 需要的扁平 dict (不带顺序/注释)
        public var dict: [String: Any] { cmap.toDict() }
    }

    /// 定位一个主题的配置文件. Hexo → themes/<name>/_config.yml (YAML),
    /// Hugo → themes/<name>/theme.toml 或 theme.yaml 或 hugo.toml, SkycBlog → themes/<name>/theme.yaml.
    /// 若文件不存在, 仍然返回一个 .rawText == "" 的 record (让 UI 可以创建默认内容).
    public static func locateThemeConfig(themeName: String, projectRoot: String) -> ThemeConfigFile? {
        let fm = FileManager.default
        let themeDir = (projectRoot as NSString).appendingPathComponent("themes/\(themeName)")
        guard fm.fileExists(atPath: themeDir) else { return nil }

        let theme = listThemes(projectRoot: projectRoot).first { $0.name == themeName }
        let kind = theme?.kind ?? .unknown

        // 按主题类型找配置文件
        let candidates: [(path: String, format: String)]
        switch kind {
        case .hexo:
            candidates = [("_config.yml", "yaml")]
        case .hugo:
            candidates = [("theme.toml", "toml"), ("theme.yaml", "yaml")]
        case .skyc:
            candidates = [("theme.yaml", "yaml"), ("theme.yml", "yaml")]
        case .unknown:
            // 兜底: 按文件存在顺序
            candidates = [
                ("_config.yml", "yaml"),
                ("theme.yaml", "yaml"),
                ("theme.yml", "yaml"),
                ("theme.toml", "toml"),
                ("hugo.toml", "toml"),
            ]
        }

        for (rel, fmt) in candidates {
            let abs = (themeDir as NSString).appendingPathComponent(rel)
            if fm.fileExists(atPath: abs) {
                let text = (try? String(contentsOfFile: abs, encoding: .utf8)) ?? ""
                let cmap: CmpMapping
                switch fmt {
                case "yaml":
                    // 使用保顺序 + 注释的解析
                    cmap = MiniYAML.loadAnnotated(text)
                case "toml":
                    // TOML 暂无注释保留; 退回到 [String:Any] 再转 CmpMapping
                    let flat = TOMLParser.parse(text)
                    cmap = CmpMapping.from(flat)
                default:
                    cmap = CmpMapping()
                }
                return ThemeConfigFile(themeName: themeName, themeKind: kind,
                                       relativePath: rel, format: fmt,
                                       absolutePath: abs, cmap: cmap, rawText: text)
            }
        }

        // 没有任何配置文件 — 仍然返回空 record, UI 可让用户新建
        let (rel, fmt) = candidates.first ?? ("theme.yaml", "yaml")
        let abs = (themeDir as NSString).appendingPathComponent(rel)
        return ThemeConfigFile(themeName: themeName, themeKind: kind,
                               relativePath: rel, format: fmt,
                               absolutePath: abs, cmap: CmpMapping(), rawText: "")
    }

    /// 保存主题配置.
    /// - Parameter rawOverride: 若非 nil, 直接以该字符串覆盖整个文件 (高级模式).
    /// - Parameter cmap: 若非 nil, 优先用 CmpMapping 保存 (YAML 时会保留注释).
    /// - Parameter dict: 兜底, 兼容旧 API (YAML 不保留注释, TOML 直接 dump).
    public static func saveThemeConfig(_ cfg: ThemeConfigFile, cmap: CmpMapping? = nil, dict: [String: Any]? = nil, rawOverride: String? = nil) -> (ok: Bool, message: String) {
        let fm = FileManager.default
        let dir = (cfg.absolutePath as NSString).deletingLastPathComponent
        do {
            try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
            let text: String
            if let raw = rawOverride {
                text = raw
            } else if let m = cmap {
                switch cfg.format {
                case "yaml": text = MiniYAML.dump(m)
                case "toml": text = MiniTOML.dump(m.toDict())
                default:     text = MiniYAML.dump(m)
                }
            } else {
                let d = dict ?? cfg.dict
                switch cfg.format {
                case "yaml": text = MiniYAML.dump(d)
                case "toml": text = MiniTOML.dump(d)
                default: text = MiniYAML.dump(d)
                }
            }
            try text.write(toFile: cfg.absolutePath, atomically: true, encoding: .utf8)
            return (true, "已保存 \(cfg.relativePath)")
        } catch {
            return (false, "保存失败: \(error.localizedDescription)")
        }
    }

    // MARK: - 主题安装

    /// 安装一个主题从本地目录到 themes/ 下（拷贝）。
    /// - Returns: 是否成功 + 错误信息
    @discardableResult
    public static func installTheme(fromSource source: String, projectRoot: String, destName: String) -> (ok: Bool, message: String) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: source) else { return (false, "源路径不存在：\(source)") }
        let themesDir = (projectRoot as NSString).appendingPathComponent("themes")
        try? fm.createDirectory(atPath: themesDir, withIntermediateDirectories: true)
        let dst = (themesDir as NSString).appendingPathComponent(destName)
        if fm.fileExists(atPath: dst) { return (false, "已存在同名主题：\(destName)") }
        do {
            try fm.copyItem(atPath: source, toPath: dst)
            return (true, "已安装主题 \(destName)")
        } catch {
            return (false, "复制失败：\(error.localizedDescription)")
        }
    }

    /// 切换主题（写 config.yaml 的 theme 字段）
    @discardableResult
    public static func activateTheme(name: String, projectRoot: String) -> (ok: Bool, message: String) {
        let themesDir = (projectRoot as NSString).appendingPathComponent("themes/\(name)")
        guard FileManager.default.fileExists(atPath: themesDir) else {
            return (false, "主题不存在：\(name)")
        }
        let cfgPath = (projectRoot as NSString).appendingPathComponent("config.yaml")
        guard FileManager.default.fileExists(atPath: cfgPath) else {
            return (false, "找不到 config.yaml")
        }
        do {
            let text = try String(contentsOfFile: cfgPath, encoding: .utf8)
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            var found = false
            var out: [String] = []
            for l in lines {
                if l.trimmingCharacters(in: .whitespaces).hasPrefix("theme:") || l.trimmingCharacters(in: .whitespaces).hasPrefix("themeName:") {
                    let key = l.trimmingCharacters(in: .whitespaces).hasPrefix("themeName:") ? "themeName" : "theme"
                    out.append("\(key): \(name)")
                    found = true
                } else {
                    out.append(l)
                }
            }
            if !found {
                out.insert("theme: \(name)", at: 0)
            }
            let rendered = out.joined(separator: "\n")
            try rendered.write(toFile: cfgPath, atomically: true, encoding: .utf8)
            return (true, "已切换主题到 \(name)")
        } catch {
            return (false, "写入失败：\(error.localizedDescription)")
        }
    }
}
