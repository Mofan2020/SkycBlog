import SwiftUI
import SkycBlogCore
import AppKit

/// 主题页右侧配置编辑面板.
/// 布局: 顶部元信息 -> 中部键值对编辑器 (基于 CmpMapping, 保留顺序 + 注释) -> 高级模式原文 -> 保存
struct ThemeConfigEditorPanel: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.theme) private var theme

    @State private var config: ThemeManager.ThemeConfigFile? = nil
    /// 当前在面板上编辑的 CmpMapping (YAML: 保顺序 + 注释; TOML: 仅顺序)
    @State private var working: CmpMapping = CmpMapping()
    /// 高级模式下的原始文本
    @State private var rawText: String = ""
    @State private var advancedMode: Bool = false
    @State private var errorMessage: String? = nil
    @State private var successMessage: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().background(theme.divider)
            if advancedMode {
                rawEditor
            } else {
                kvEditor
            }
            Divider().background(theme.divider)
            footer
        }
        .background(theme.surface)
        .onAppear { reload() }
        .onChange(of: appState.selectedThemeName) { _ in reload() }
    }

    // MARK: - 顶部
    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: theme.icon(for: config?.themeKind))
                    .font(.system(size: 18))
                    .foregroundStyle(theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(config?.themeName ?? appState.selectedThemeName)
                            .font(AppFont.title(size: 18))
                            .foregroundStyle(theme.ink)
                        if let cfg = config, appState.activeThemeName == cfg.themeName {
                            Text("已启用")
                                .font(AppFont.monoCaption())
                                .foregroundStyle(theme.accent)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(theme.tagBackground)
                                .clipShape(Capsule())
                        }
                    }
                    if let cfg = config {
                        Text("\(cfg.themeKind.displayName) · \(cfg.relativePath) · \(cfg.format.uppercased())")
                            .font(AppFont.monoCaption())
                            .foregroundStyle(theme.inkTertiary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                Button {
                    if let cfg = config { openInEditor(cfg.absolutePath) }
                } label: { Image(systemName: "pencil.circle") }
                .buttonStyle(.borderless)
                .help("在外部编辑器中打开该配置文件")
            }
            if let cfg = config, cfg.rawText.isEmpty {
                Text("该主题没有配置文件 — 保存后将创建默认 \(cfg.format.uppercased()) 文本")
                    .font(AppFont.caption())
                    .foregroundStyle(theme.inkTertiary)
            }
            if let cfg = config, cfg.format == "yaml" {
                Text("注释 (#) 已自动保留, 可点击右侧 💬 按钮查看与编辑")
                    .font(AppFont.caption())
                    .foregroundStyle(theme.inkTertiary)
            } else if let cfg = config, cfg.format == "toml" {
                Text("TOML 格式不保留注释, 改用 YAML 或在高级模式编辑原文")
                    .font(AppFont.caption())
                    .foregroundStyle(theme.inkTertiary)
            }
        }
        .padding(16)
    }

    // MARK: - 键值对编辑器
    private var kvEditor: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let cfg = config {
                    if working.entries.isEmpty && cfg.rawText.isEmpty {
                        emptyHint(cfg)
                    } else {
                        MappingEditor(
                            mapping: $working,
                            format: cfg.format
                        )
                        .padding(16)
                    }
                } else {
                    ProgressView().padding(40)
                }
            }
        }
    }

    private func emptyHint(_ cfg: ThemeManager.ThemeConfigFile) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.badge.plus")
                .font(.system(size: 32))
                .foregroundStyle(theme.inkTertiary)
            Text("此主题尚无配置")
                .font(AppFont.body())
                .foregroundStyle(theme.inkSecondary)
            Button("生成默认 \(cfg.format.uppercased()) 模板") {
                rawText = defaultTemplate(for: cfg.format)
                advancedMode = true
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }

    // MARK: - 高级 (原始文本)
    private var rawEditor: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextEditor(text: $rawText)
                .font(AppFont.mono(size: 12))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(8)
                .background(theme.editorBackground)
                .foregroundStyle(theme.ink)
        }
    }

    // MARK: - 底部
    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let err = errorMessage {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .font(AppFont.caption())
                    .foregroundStyle(.red)
            }
            if let ok = successMessage {
                Label(ok, systemImage: "checkmark.seal.fill")
                    .font(AppFont.caption())
                    .foregroundStyle(theme.accent)
            }
            HStack {
                Toggle(isOn: $advancedMode) { Text("高级模式（直接编辑原始 \(config?.format.uppercased() ?? "YAML")）") }
                    .toggleStyle(.switch)
                    .font(AppFont.caption())
                Spacer()
                Button("重新加载") { reload() }
                    .buttonStyle(.bordered)
                Button("保存") { save() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut("s", modifiers: [.command])
                    .disabled(config == nil)
            }
        }
        .padding(12)
    }

    // MARK: - 行为
    private func reload() {
        let name = appState.selectedThemeName
        guard !name.isEmpty, let cfg = appState.loadThemeConfig(name: name) else {
            config = nil
            working = CmpMapping()
            rawText = ""
            return
        }
        config = cfg
        working = cfg.cmap
        rawText = cfg.rawText.isEmpty ? defaultTemplate(for: cfg.format) : cfg.rawText
        errorMessage = nil
        successMessage = nil
    }

    private func save() {
        guard let cfg = config else { return }
        if advancedMode {
            let r = appState.saveThemeConfig(name: cfg.themeName, rawOverride: rawText)
            if r.ok {
                successMessage = r.message
                errorMessage = nil
                reload()
            } else {
                errorMessage = r.message
            }
        } else {
            // YAML 走 cmap (保留注释), TOML 走 dict (从 cmap.toDict() 转)
            let r: (ok: Bool, message: String)
            if cfg.format == "yaml" {
                r = appState.saveThemeConfig(name: cfg.themeName, cmap: working)
            } else {
                r = appState.saveThemeConfig(name: cfg.themeName, dict: working.toDict())
            }
            if r.ok {
                successMessage = r.message
                errorMessage = nil
                reload()
            } else {
                errorMessage = r.message
            }
        }
    }

    private func openInEditor(_ path: String) {
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    private func defaultTemplate(for format: String) -> String {
        switch format {
        case "yaml": return "# 在此编辑主题配置 (YAML)\n\n"
        case "toml": return "# 在此编辑主题配置 (TOML)\n\n"
        default:     return ""
        }
    }
}

// MARK: - 通知 (用于子层通知父层删除 entry)
extension Notification.Name {
    static let removeCmpEntry = Notification.Name("SkycBlog.removeCmpEntry")
    static let updateCmpEntry = Notification.Name("SkycBlog.updateCmpEntry")
}

// MARK: - CmpMapping 递归编辑器

/// 递归渲染一个 CmpMapping: 每条 key 一行, 包含:
///   - 注释按钮 (💬): 弹出文本编辑面板, 修改 leadingComments + inlineComment
///   - 键名 (右侧对齐, 等宽)
///   - 值编辑器 (按类型: scalar / nested mapping / list)
///   - 删除键
/// 末尾有"添加键"行.
struct MappingEditor: View {
    @Environment(\.theme) private var theme
    @Binding var mapping: CmpMapping
    let format: String
    /// 用于让外层(嵌套编辑器)传递 onRemove 闭包, 配合 binding 一起工作
    var parentKey: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 顶部游离注释展示
            if !mapping.leadingComments.isEmpty {
                ForEach(Array(mapping.leadingComments.enumerated()), id: \.offset) { _, c in
                    Text(c)
                        .font(AppFont.mono(size: 11))
                        .foregroundStyle(theme.inkTertiary)
                }
                Divider().background(theme.divider).padding(.vertical, 4)
            }
            ForEach(Array(mapping.entries.enumerated()), id: \.offset) { idx, _ in
                entryRow(idx: idx)
            }
            addKeyRow
        }
    }

    @ViewBuilder
    private func entryRow(idx: Int) -> some View {
        if idx < mapping.entries.count {
            let binding = Binding<CmpEntry>(
                get: { mapping.entries[idx] },
                set: { mapping.entries[idx] = $0 }
            )
            EntryRow(
                entry: binding,
                format: format,
                depth: 0,
                onRemove: {
                    if idx < mapping.entries.count {
                        mapping.entries.remove(at: idx)
                    }
                }
            )
        }
    }

    private var addKeyRow: some View {
        HStack {
            TextField("新键名", text: .constant(""))
                .textFieldStyle(.roundedBorder)
                .font(AppFont.mono(size: 12))
                .frame(maxWidth: 160)
            Button("+ 添加键") {
                var i = 1
                var k = "new_key"
                while mapping.entry(forKey: k) != nil { i += 1; k = "new_key_\(i)" }
                mapping.entries.append(CmpEntry(key: k, value: .scalar("")))
            }
            .buttonStyle(.bordered)
        }
        .padding(.top, 10)
    }
}

// MARK: - 单行 entry (key + value + 注释按钮 + 删除)
struct EntryRow: View {
    @Environment(\.theme) private var theme
    @Binding var entry: CmpEntry
    let format: String
    let depth: Int
    let onRemove: () -> Void
    @State private var showCommentEditor: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 该 entry 上方的 leading comments (整行注释)
            if !entry.leadingComments.isEmpty {
                ForEach(Array(entry.leadingComments.enumerated()), id: \.offset) { _, c in
                    HStack {
                        Text(c)
                            .font(AppFont.mono(size: 11))
                            .foregroundStyle(theme.inkTertiary)
                            .textSelection(.enabled)
                        Spacer()
                    }
                }
            }
            HStack(alignment: .top, spacing: 8) {
                // 注释按钮: 仅 YAML 才显示
                if format == "yaml" {
                    Button { showCommentEditor.toggle() } label: {
                        Image(systemName: hasAnyComment ? "text.bubble.fill" : "text.bubble")
                            .foregroundStyle(hasAnyComment ? theme.accent : theme.inkTertiary)
                    }
                    .buttonStyle(.borderless)
                    .help(hasAnyComment ? "查看/编辑注释 (\(commentCountText))" : "添加注释")
                    .popover(isPresented: $showCommentEditor) {
                        CommentEditor(entry: $entry)
                            .frame(width: 380, height: 320)
                            .padding(8)
                    }
                }
                Text(entry.key)
                    .font(AppFont.mono(size: 12))
                    .foregroundStyle(theme.accent)
                    .frame(minWidth: 120, alignment: .trailing)
                    .padding(.top, 6)
                valueEditor
                Spacer()
                Button { onRemove() } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(theme.inkTertiary)
            }
            .padding(.vertical, 2)
        }
    }

    private var hasAnyComment: Bool {
        !entry.leadingComments.isEmpty || entry.inlineComment != nil
    }
    private var commentCountText: String {
        var parts: [String] = []
        if !entry.leadingComments.isEmpty { parts.append("\(entry.leadingComments.count) 上方") }
        if entry.inlineComment != nil { parts.append("1 同行") }
        return parts.joined(separator: " / ")
    }

    @ViewBuilder
    private var valueEditor: some View {
        switch entry.value {
        case .scalar(let s):
            scalarField(initial: s)
        case .mapping(let m):
            NestedMappingEditor(parent: $entry, format: format, depth: depth + 1)
        case .list(let items):
            ListEditor(parent: $entry, format: format, depth: depth + 1)
        }
    }

    @ViewBuilder
    private func scalarField(initial: Any) -> some View {
        if initial is Bool {
            Toggle("", isOn: Binding<Bool>(
                get: { (initial as? Bool) ?? false },
                set: { entry.value = .scalar($0) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
        } else {
            TextField("", text: Binding<String>(
                get: { scalarToString(initial) },
                set: { entry.value = .scalar(stringToScalar($0)) }
            ))
            .textFieldStyle(.roundedBorder)
            .font(AppFont.mono(size: 12))
            .frame(maxWidth: 280)
        }
    }

    private func scalarToString(_ v: Any) -> String {
        if v is NSNull { return "null" }
        if let b = v as? Bool { return b ? "true" : "false" }
        if let i = v as? Int { return String(i) }
        if let d = v as? Double { return String(d) }
        return v as? String ?? ""
    }
    private func stringToScalar(_ s: String) -> Any {
        let t = s.trimmingCharacters(in: .whitespaces)
        if t == "null" || t.isEmpty { return NSNull() }
        if t == "true" { return true }
        if t == "false" { return false }
        if let i = Int(t) { return i }
        if let d = Double(t) { return d }
        return t
    }
}

// MARK: - 注释编辑器 (popover)
struct CommentEditor: View {
    @Environment(\.theme) private var theme
    @Binding var entry: CmpEntry
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("注释 (YAML # 格式)").font(AppFont.caption()).foregroundStyle(theme.inkSecondary)
            Text("上方注释 (每行一条, 写到 key 上方):").font(AppFont.caption()).foregroundStyle(theme.inkTertiary)
            TextEditor(text: Binding<String>(
                get: { entry.leadingComments.joined(separator: "\n") },
                set: { newStr in
                    entry.leadingComments = newStr.split(separator: "\n", omittingEmptySubsequences: false).map { String($0) }
                }
            ))
            .font(AppFont.mono(size: 11))
            .frame(height: 130)
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(theme.divider, lineWidth: 0.5))
            Text("同行尾注释 (写在 key 后面, # 引导):").font(AppFont.caption()).foregroundStyle(theme.inkTertiary)
            TextField("# 你的注释", text: Binding<String>(
                get: { entry.inlineComment ?? "" },
                set: { newStr in
                    entry.inlineComment = newStr.isEmpty ? nil : newStr
                }
            ))
            .textFieldStyle(.roundedBorder)
            .font(AppFont.mono(size: 11))
            HStack {
                Button("清空全部注释") {
                    entry.leadingComments = []
                    entry.inlineComment = nil
                }
                .buttonStyle(.bordered)
                Spacer()
                Button("完成") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}

// MARK: - 嵌套 mapping 编辑器
struct NestedMappingEditor: View {
    @Environment(\.theme) private var theme
    @Binding var parent: CmpEntry
    let format: String
    let depth: Int
    @State private var expanded: Bool = true

    var body: some View {
        // 通过 binding 提取 .mapping; 每次重绘都从 parent.value 读最新值
        if case .mapping = parent.value {
            // 用一个 内部 @State 镜像 (init 时同步), 修改时再写回 parent
            NestedMappingContent(parent: $parent, format: format, depth: depth, expanded: $expanded)
        } else {
            Button("转为对象") {
                parent.value = .mapping(CmpMapping())
            }
            .buttonStyle(.borderless)
            .font(AppFont.caption())
        }
    }
}

private struct NestedMappingContent: View {
    @Environment(\.theme) private var theme
    @Binding var parent: CmpEntry
    let format: String
    let depth: Int
    @Binding var expanded: Bool

    var body: some View {
        if case .mapping(let sub) = parent.value {
            VStack(alignment: .leading, spacing: 0) {
                DisclosureGroup(isExpanded: $expanded) {
                    // 通过 Binding<CmpMapping> 直接修改 sub
                    MappingEditor(
                        mapping: Binding<CmpMapping>(
                            get: { sub },
                            set: { parent.value = .mapping($0) }
                        ),
                        format: format
                    )
                    .padding(8)
                    .background(theme.cardBackground.opacity(0.4))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                } label: {
                    HStack(spacing: 4) {
                        Text("{…} \(sub.entries.count) keys")
                            .font(AppFont.mono(size: 11))
                            .foregroundStyle(theme.inkTertiary)
                        Spacer()
                    }
                }
            }
        }
    }
}

// MARK: - list 编辑器
struct ListEditor: View {
    @Environment(\.theme) private var theme
    @Binding var parent: CmpEntry
    let format: String
    let depth: Int
    @State private var expanded: Bool = true

    var body: some View {
        if case .list(var items) = parent.value {
            DisclosureGroup(isExpanded: $expanded) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(items.enumerated()), id: \.offset) { idx, _ in
                        listItemRow(idx: idx, items: items)
                    }
                    HStack {
                        Button("+ 添加项") {
                            var arr = items
                            arr.append(CmpListItem(value: .scalar("")))
                            parent.value = .list(arr)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(8)
                .background(theme.cardBackground.opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            } label: {
                Text("[\(items.count) 项]").font(AppFont.mono(size: 11)).foregroundStyle(theme.inkTertiary)
            }
        } else {
            Button("转为列表") {
                parent.value = .list([CmpListItem(value: .scalar(""))])
            }
            .buttonStyle(.borderless)
            .font(AppFont.caption())
        }
    }

    @ViewBuilder
    private func listItemRow(idx: Int, items: [CmpListItem]) -> some View {
        if idx < items.count {
            let itemBinding = Binding<CmpListItem>(
                get: { items[idx] },
                set: { newVal in
                    var arr = items
                    if idx < arr.count { arr[idx] = newVal }
                    parent.value = .list(arr)
                }
            )
            HStack {
                Text("[\(idx)]").font(AppFont.monoCaption()).foregroundStyle(theme.inkTertiary)
                if case .mapping = itemBinding.wrappedValue.value {
                    Text("(object — 在高级模式编辑)").font(AppFont.caption()).foregroundStyle(theme.inkTertiary)
                } else if case .list = itemBinding.wrappedValue.value {
                    Text("(nested list — 在高级模式编辑)").font(AppFont.caption()).foregroundStyle(theme.inkTertiary)
                } else {
                    TextField("", text: Binding<String>(
                        get: {
                            if case .scalar(let s) = itemBinding.wrappedValue.value {
                                return scalarToString(s)
                            }
                            return ""
                        },
                        set: { itemBinding.wrappedValue.value = .scalar(stringToScalar($0)) }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .font(AppFont.mono(size: 12))
                    .frame(maxWidth: 240)
                }
                Spacer()
                Button {
                    var arr = items; if idx < arr.count { arr.remove(at: idx) }; parent.value = .list(arr)
                } label: { Image(systemName: "minus.circle") }
                .buttonStyle(.borderless)
                .foregroundStyle(theme.inkTertiary)
            }
        }
    }

    private func scalarToString(_ v: Any) -> String {
        if v is NSNull { return "null" }
        if let b = v as? Bool { return b ? "true" : "false" }
        if let i = v as? Int { return String(i) }
        if let d = v as? Double { return String(d) }
        return v as? String ?? ""
    }
    private func stringToScalar(_ s: String) -> Any {
        let t = s.trimmingCharacters(in: .whitespaces)
        if t == "null" || t.isEmpty { return NSNull() }
        if t == "true" { return true }
        if t == "false" { return false }
        if let i = Int(t) { return i }
        if let d = Double(t) { return d }
        return t
    }
}

// MARK: - 主题调色板扩展
private extension ThemePalette {
    func icon(for kind: ThemeKind?) -> String {
        guard let k = kind else { return "doc.text" }
        return k.systemImage
    }
}
