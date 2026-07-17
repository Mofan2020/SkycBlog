import SwiftUI
import SkycBlogCore
import AppKit

/// 主题页右侧配置编辑面板。
/// 布局：顶部元信息 (主题名/类型/已激活状态/配置文件) ->
///       中部键值对编辑器 (递归展示 String/Int/Double/Bool/String/Array/[String:Any]) ->
///       底部原始文本模式 (advanced) + 保存按钮 + 错误提示
struct ThemeConfigEditorPanel: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.theme) private var theme

    /// 当前打开的配置文件 (在 panel 出现时加载, 之后保持引用, 用户操作字典)
    @State private var config: ThemeManager.ThemeConfigFile? = nil
    /// 字典的可变副本 — SwiftUI 通过 [key: Binding<Any>] 暴露子编辑器
    @State private var working: [String: Any] = [:]
    /// 高级模式下的原始文本
    @State private var rawText: String = ""
    /// 是否处于"高级"模式
    @State private var advancedMode: Bool = false
    /// 错误提示
    @State private var errorMessage: String? = nil
    /// 成功提示
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
        }
        .padding(16)
    }

    // MARK: - 键值对编辑
    private var kvEditor: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let cfg = config {
                    if cfg.dict.isEmpty && cfg.rawText.isEmpty {
                        emptyHint(cfg)
                    } else {
                        KeyValueTreeEditor(value: $working, keyPath: [], depth: 0)
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
            working = [:]
            rawText = ""
            return
        }
        config = cfg
        working = cfg.dict
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
            let r = appState.saveThemeConfig(name: cfg.themeName, dict: working)
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

// MARK: - 递归键值树编辑器

/// 递归渲染 [String: Any] 的子树, 允许编辑. 通过 Binding<[String: Any]> 修改父 dict.
struct KeyValueTreeEditor: View {
    @Environment(\.theme) private var theme
    @Binding var value: [String: Any]
    let keyPath: [String]
    let depth: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(value.keys.sorted(), id: \.self) { key in
                row(forKey: key)
            }
            addRow
        }
    }

    private func row(forKey key: String) -> some View {
        let binding = Binding<Any>(
            get: { value[key] ?? NSNull() },
            set: { value[key] = $0 }
        )
        let isDict = value[key] is [String: Any]
        let isArr = value[key] is [Any]
        return HStack(alignment: .top, spacing: 8) {
            Text(key)
                .font(AppFont.mono(size: 12))
                .foregroundStyle(theme.accent)
                .frame(minWidth: 120, alignment: .trailing)
                .padding(.top, 6)
            if isDict {
                nestedDict(key: key)
            } else if isArr {
                nestedArr(key: key)
            } else {
                scalarField(key: key, binding: binding)
            }
            Spacer()
            Button { removeKey(key) } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(theme.inkTertiary)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func nestedDict(key: String) -> some View {
        let sub = Binding<[String: Any]>(
            get: { (value[key] as? [String: Any]) ?? [:] },
            set: { value[key] = $0 }
        )
        DisclosureGroup {
            KeyValueTreeEditor(value: sub, keyPath: keyPath + [key], depth: depth + 1)
                .padding(8)
                .background(theme.cardBackground.opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        } label: {
            Text("{…}").font(AppFont.mono(size: 11)).foregroundStyle(theme.inkTertiary)
        }
    }

    @ViewBuilder
    private func nestedArr(key: String) -> some View {
        let arr = Binding<[Any]>(
            get: { (value[key] as? [Any]) ?? [] },
            set: { value[key] = $0 }
        )
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(arr.indices, id: \.self) { i in
                    let itemBinding = Binding<Any>(
                        get: { arr.wrappedValue[i] },
                        set: { newVal in
                            var a = arr.wrappedValue
                            if i < a.count { a[i] = newVal }
                            arr.wrappedValue = a
                        }
                    )
                    HStack {
                        Text("[\(i)]").font(AppFont.monoCaption()).foregroundStyle(theme.inkTertiary)
                        if let _ = arr.wrappedValue[i] as? [String: Any] {
                            Text("(object — 切换到高级模式编辑)").font(AppFont.caption()).foregroundStyle(theme.inkTertiary)
                        } else {
                            TextField("", text: scalarTextBinding(itemBinding))
                                .textFieldStyle(.roundedBorder)
                                .font(AppFont.mono(size: 12))
                                .frame(maxWidth: 240)
                        }
                        Spacer()
                        Button {
                            var a = arr.wrappedValue; if i < a.count { a.remove(at: i) }; arr.wrappedValue = a
                        } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                        .foregroundStyle(theme.inkTertiary)
                    }
                }
                HStack {
                    Button("+ 添加项") {
                        arr.wrappedValue.append("")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(8)
            .background(theme.cardBackground.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        } label: {
            Text("[\(arr.wrappedValue.count) 项]").font(AppFont.mono(size: 11)).foregroundStyle(theme.inkTertiary)
        }
    }

    @ViewBuilder
    private func scalarField(key: String, binding: Binding<Any>) -> some View {
        let v = binding.wrappedValue
        if v is Bool {
            Toggle("", isOn: Binding<Bool>(
                get: { (v as? Bool) ?? false },
                set: { binding.wrappedValue = $0 }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
        } else if v is Int || v is Double || v is NSNull {
            TextField("", text: scalarTextBinding(binding))
                .textFieldStyle(.roundedBorder)
                .font(AppFont.mono(size: 12))
                .frame(maxWidth: 200)
        } else {
            TextField("", text: scalarTextBinding(binding))
                .textFieldStyle(.roundedBorder)
                .font(AppFont.mono(size: 12))
                .frame(maxWidth: 240)
        }
    }

    /// 标量值 ↔ 字符串的双向 binding (number/null 用 raw 文本, bool 用上面单独处理)
    private func scalarTextBinding(_ binding: Binding<Any>) -> Binding<String> {
        Binding<String>(
            get: {
                let v = binding.wrappedValue
                if v is NSNull { return "null" }
                if let b = v as? Bool { return b ? "true" : "false" }
                if let i = v as? Int { return String(i) }
                if let d = v as? Double { return String(d) }
                return v as? String ?? ""
            },
            set: { newStr in
                let s = newStr.trimmingCharacters(in: .whitespaces)
                if s == "null" || s.isEmpty { binding.wrappedValue = NSNull(); return }
                if s == "true" { binding.wrappedValue = true; return }
                if s == "false" { binding.wrappedValue = false; return }
                if let i = Int(s) { binding.wrappedValue = i; return }
                if let d = Double(s) { binding.wrappedValue = d; return }
                binding.wrappedValue = s
            }
        )
    }

    private var addRow: some View {
        HStack {
            TextField("新键名", text: .constant(""))
                .textFieldStyle(.roundedBorder)
                .font(AppFont.mono(size: 12))
                .frame(maxWidth: 160)
            Button("+ 添加键") {
                var i = 1
                var k = "new_key"
                while value[k] != nil { i += 1; k = "new_key_\(i)" }
                value[k] = ""
            }
            .buttonStyle(.bordered)
        }
        .padding(.top, 6)
    }

    private func removeKey(_ key: String) {
        value.removeValue(forKey: key)
    }
}

// MARK: - ThemePalette 扩展 (把 themeKind 映射到图标)
private extension ThemePalette {
    func icon(for kind: ThemeKind?) -> String {
        guard let k = kind else { return "doc.text" }
        return k.systemImage
    }
}
