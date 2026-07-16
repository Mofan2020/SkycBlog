import SwiftUI
import SkycBlogCore
import AppKit

// MARK: - 详情区

struct DetailColumnView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Group {
            if let pageID = appState.selectedPageID,
               let page = currentPage(id: pageID) {
                EditorView(page: page)
            } else if let project = appState.project, appState.isServing, let url = appState.previewURL {
                PreviewView(url: url, project: project)
            } else if appState.project != nil {
                NoSelectionView()
            } else {
                NoSelectionView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func currentPage(id: String) -> Page? {
        guard let project = appState.project else { return nil }
        return project.posts.first(where: { $0.id == id })
            ?? project.drafts.first(where: { $0.id == id })
            ?? project.pages.first(where: { $0.id == id })
    }
}

struct NoSelectionView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "doc.text.below.ecg")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(Theme.inkTertiary)
            Text("在左侧选择一篇文章开始编辑")
                .font(.system(.body, design: .serif))
                .foregroundStyle(Theme.inkSecondary)
            if appState.project != nil {
                Button {
                    appState.sheet = .newPost
                } label: {
                    Label("新建文章", systemImage: "plus")
                }
                .controlSize(.regular)
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }
}

// MARK: - 编辑器

struct EditorView: View {
    let page: Page
    @EnvironmentObject var appState: AppState
    @State private var raw: String = ""
    @State private var frontMatter: String = ""
    @State private var content: String = ""
    @State private var rendered: String = ""
    @State private var loaded: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // 头部
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(page.title)
                        .font(.system(.title3, design: .serif).weight(.semibold))
                        .foregroundStyle(Theme.ink)
                    HStack(spacing: 6) {
                        Text(page.url)
                        Text("·")
                        Text(page.kind.rawValue)
                        Text("·")
                        Text("\(content.count) 字")
                    }
                    .font(.caption)
                    .foregroundStyle(Theme.inkTertiary)
                }
                Spacer()
                Toggle("预览", isOn: $appState.editor.previewVisible)
                    .toggleStyle(.button)
                    .controlSize(.small)
                Button {
                    save()
                } label: {
                    Label(appState.editor.isDirty ? "保存" : "已保存", systemImage: "tray.and.arrow.down")
                }
                .keyboardShortcut("s", modifiers: [.command])
                .controlSize(.small)
                .disabled(!appState.editor.isDirty)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Theme.background)
            .overlay(Divider(), alignment: .bottom)

            // 编辑 + 预览
            if appState.editor.previewVisible {
                HSplitView {
                    MarkdownEditor(text: $content, onChange: markDirty)
                        .frame(minWidth: 320)
                    PreviewPane(html: rendered)
                        .frame(minWidth: 320)
                }
            } else {
                MarkdownEditor(text: $content, onChange: markDirty)
            }
        }
        .onAppear(perform: load)
        .onChange(of: page.id) { _, _ in load() }
        .onChange(of: content) { _, new in renderPreview(new) }
    }

    private func load() {
        do {
            let text = try String(contentsOfFile: page.sourcePath, encoding: .utf8)
            if let (fm, md) = splitFrontMatter(text) {
                frontMatter = fm
                content = md
            } else {
                content = text
            }
            raw = text
            appState.editor.isDirty = false
            renderPreview(content)
            loaded = true
        } catch {
            appState.log(.error("读取失败：\(error.localizedDescription)"))
        }
    }

    private func save() {
        let text = frontMatter.isEmpty ? content : (frontMatter + "\n" + content)
        do {
            try text.write(toFile: page.sourcePath, atomically: true, encoding: .utf8)
            appState.editor.isDirty = false
            appState.editor.lastSave = Date()
            appState.project?.refresh()
            appState.log(.success("已保存：\(page.title)"))
        } catch {
            appState.log(.error("保存失败：\(error.localizedDescription)"))
        }
    }

    private func markDirty() {
        appState.editor.isDirty = true
    }

    private func renderPreview(_ md: String) {
        rendered = MarkdownRenderer.render(md)
    }

    /// 简单切分 front matter：`---\n...\n---\n` 前缀。
    private func splitFrontMatter(_ text: String) -> (String, String)? {
        guard text.hasPrefix("---\n") || text.hasPrefix("---\r\n") else { return nil }
        let lines = text.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return nil }
        for i in 1..<lines.count {
            if lines[i].trimmingCharacters(in: .whitespaces) == "---" {
                let fm = lines[0...i].joined(separator: "\n") + "\n"
                let rest = lines[(i+1)...].joined(separator: "\n")
                return (fm, rest)
            }
        }
        return nil
    }
}

struct MarkdownEditor: View {
    @Binding var text: String
    let onChange: () -> Void
    @State private var fontSize: CGFloat = 14

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text("开始书写…")
                    .foregroundStyle(Theme.inkTertiary)
                    .font(.system(size: fontSize, design: .serif))
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $text)
                .font(.system(size: fontSize, design: .serif))
                .scrollContentBackground(.hidden)
                .background(Theme.editorBackground)
                .padding(.horizontal, 16)
                .onChange(of: text) { _, _ in onChange() }
        }
        .background(Theme.editorBackground)
    }
}

struct PreviewPane: View {
    let html: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading) {
                if let attributed = renderAttributed(html) {
                    Text(attributed)
                        .textSelection(.enabled)
                        .frame(maxWidth: 720, alignment: .leading)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 16)
                } else {
                    Text(html).font(Theme.mono).foregroundStyle(.secondary)
                        .padding(20)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(red: 1.0, green: 0.99, blue: 0.97))
    }

    private func renderAttributed(_ html: String) -> AttributedString? {
        guard let data = html.data(using: .utf8) else { return nil }
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]
        if let ns = try? NSAttributedString(data: data, options: options, documentAttributes: nil) {
            return AttributedString(ns)
        }
        return nil
    }
}

// MARK: - 浏览器预览

struct PreviewView: View {
    let url: URL
    let project: BlogProject

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "globe")
                    .foregroundStyle(Theme.accent)
                Text("本地预览")
                    .font(.system(.body, design: .serif).weight(.semibold))
                Text(url.absoluteString)
                    .font(Theme.monoCaption)
                    .foregroundStyle(Theme.inkTertiary)
                Spacer()
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Label("在浏览器中打开", systemImage: "arrow.up.right.square")
                }
                .controlSize(.small)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Theme.background)
            .overlay(Divider(), alignment: .bottom)
            WebPreview(url: url)
        }
    }
}

// MARK: - 控制台

struct ConsoleView: View {
    @EnvironmentObject var appState: AppState
    @State private var filter: Filter = .all

    enum Filter: String, CaseIterable, Identifiable {
        case all = "全部", info = "信息", success = "成功", warn = "警告", error = "错误"
        var id: String { rawValue }
    }

    var filtered: [LogEntry] {
        switch filter {
        case .all: return appState.console
        case .info: return appState.console.filter { $0.level == .info }
        case .success: return appState.console.filter { $0.level == .success }
        case .warn: return appState.console.filter { $0.level == .warn }
        case .error: return appState.console.filter { $0.level == .error }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("控制台")
                    .font(.system(.caption, design: .serif).weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.8))
                Picker("", selection: $filter) {
                    ForEach(Filter.allCases) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
                .pickerStyle(.segmented)
                .controlSize(.small)
                .frame(width: 360)
                Spacer()
                Text("\(filtered.count) 条")
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.5))
                Button {
                    appState.clearLog()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("清空")
                .foregroundStyle(Color.white.opacity(0.7))
                Button {
                    appState.consoleVisible = false
                } label: {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(.borderless)
                .help("收起 (⌘`)")
                .foregroundStyle(Color.white.opacity(0.7))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.5))

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(filtered) { entry in
                            ConsoleLine(entry: entry).id(entry.id)
                        }
                    }
                    .padding(.vertical, 6)
                }
                .onChange(of: filtered.count) { _, _ in
                    if let last = filtered.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }
        }
    }
}

struct ConsoleLine: View {
    let entry: LogEntry

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(time)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.4))
                .frame(width: 60, alignment: .leading)
            Text(prefix)
                .font(.system(.caption2, design: .monospaced).weight(.semibold))
                .foregroundStyle(color)
                .frame(width: 50, alignment: .leading)
            Text(entry.message)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.92))
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
    }

    private var time: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: entry.date)
    }

    private var prefix: String {
        switch entry.level {
        case .info: return "INFO"
        case .success: return " OK "
        case .warn: return "WARN"
        case .error: return " ERR"
        }
    }

    private var color: Color {
        switch entry.level {
        case .info: return Color.white.opacity(0.55)
        case .success: return Theme.success
        case .warn: return Theme.warn
        case .error: return Theme.error
        }
    }
}
