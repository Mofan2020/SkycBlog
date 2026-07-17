import SwiftUI
import SkycBlogCore
import AppKit
import WebKit

// MARK: - 详情区

struct DetailColumnView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.theme) private var theme

    var body: some View {
        Group {
            // 主题页: 选中主题时显示配置编辑面板
            if appState.selection == .themes, !appState.selectedThemeName.isEmpty {
                ThemeConfigEditorPanel()
            }
            // 文章编辑优先于预览/无选择
            else if let pageID = appState.selectedPageID,
                    let page = currentPage(id: pageID) {
                EditorView(page: page)
            } else if let project = appState.project, appState.isServing, let url = appState.previewURL {
                PreviewView(url: url, project: project)
            } else {
                NoSelectionView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.background)
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
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "doc.text.below.ecg")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(theme.inkTertiary)
            Text("在左侧选择一篇文章开始编辑")
                .font(AppFont.body())
                .foregroundStyle(theme.inkSecondary)
            if appState.project != nil {
                Button {
                    appState.sheet = .newPost
                } label: {
                    Label("新建文章", systemImage: "plus")
                }
                .controlSize(.regular)
                .buttonStyle(.borderedProminent)
                .tint(theme.accent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 编辑器

struct EditorView: View {
    let page: Page
    @EnvironmentObject var appState: AppState
    @Environment(\.theme) private var theme
    @State private var frontMatter: String = ""
    @State private var content: String = ""
    @State private var rendered: String = ""
    @State private var renderToken: Int = 0
    @State private var isRendering: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // 头部
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(page.title)
                        .font(AppFont.title(size: 18))
                        .foregroundStyle(theme.ink)
                    HStack(spacing: 6) {
                        Text(page.url)
                        Text("·")
                        Text(page.kind.rawValue)
                        Text("·")
                        Text("\(content.count) 字")
                        if isRendering {
                            Text("·")
                            Text("渲染中…")
                                .foregroundStyle(theme.accent)
                        }
                    }
                    .font(AppFont.monoCaption())
                    .foregroundStyle(theme.inkTertiary)
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
            .background(theme.background)
            .overlay(Rectangle().fill(theme.divider).frame(height: 0.5), alignment: .bottom)

            // 编辑 + 预览
            if appState.editor.previewVisible {
                HSplitView {
                    MarkdownEditor(text: $content, onChange: handleContentChange)
                        .frame(minWidth: 320)
                    MarkdownWebPreview(html: rendered, baseURL: page.sourcePath)
                        .frame(minWidth: 320)
                }
            } else {
                MarkdownEditor(text: $content, onChange: handleContentChange)
            }
        }
        .onAppear(perform: load)
        .onChange(of: page.id) { _, _ in load() }
        .onDisappear {
            renderToken &+= 1   // 取消未完成的渲染任务
        }
        .onReceive(NotificationCenter.default.publisher(for: .editorPreviewRendered)) { note in
            guard
                let info = note.userInfo,
                let pid = info["pageID"] as? String, pid == page.id,
                let tok = info["token"] as? Int, tok == renderToken,
                let html = info["html"] as? String
            else { return }
            rendered = html
            isRendering = false
        }
    }

    private func load() {
        renderToken &+= 1
        let snapshot = renderToken
        isRendering = true
        do {
            let text = try String(contentsOfFile: page.sourcePath, encoding: .utf8)
            if let (fm, md) = splitFrontMatter(text) {
                frontMatter = fm
                content = md
            } else {
                content = text
            }
            appState.editor.isDirty = false
            scheduleRender(md: content, token: snapshot)
        } catch {
            appState.log(.error("读取失败：\(error.localizedDescription)"))
            isRendering = false
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

    private func handleContentChange() {
        appState.editor.isDirty = true
        renderToken &+= 1
        scheduleRender(md: content, token: renderToken)
    }

    /// 把 Markdown 渲染放到后台队列,debounce 200ms,只接受最新一次结果。
    private func scheduleRender(md: String, token: Int) {
        isRendering = true
        let pageID = page.id
        // 在后台执行渲染,通过 Notification 把结果送回主线程。
        Task.detached(priority: .userInitiated) { [token, pageID] in
            try? await Task.sleep(nanoseconds: 200_000_000)
            if Task.isCancelled { return }
            let html = MarkdownRenderer.render(md)
            await MainActor.run {
                NotificationCenter.default.post(
                    name: .editorPreviewRendered,
                    object: nil,
                    userInfo: ["pageID": pageID, "token": token, "html": html]
                )
            }
        }
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

extension Notification.Name {
    static let editorPreviewRendered = Notification.Name("SkycBlog.editorPreviewRendered")
    static let editorPreviewFailed   = Notification.Name("SkycBlog.editorPreviewFailed")
}

struct MarkdownEditor: View {
    @Binding var text: String
    let onChange: () -> Void
    @Environment(\.theme) private var theme
    @State private var fontSize: CGFloat = 14

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text("开始书写…")
                    .foregroundStyle(theme.inkTertiary)
                    .font(AppFont.body(size: fontSize))
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $text)
                .font(AppFont.body(size: fontSize))
                .scrollContentBackground(.hidden)
                .background(theme.editorBackground)
                .foregroundStyle(theme.ink)
                .padding(.horizontal, 16)
                .onChange(of: text) { _, _ in onChange() }
        }
        .background(theme.editorBackground)
    }
}

struct PreviewPane: View {
    let html: String
    @Environment(\.theme) private var theme

    var body: some View {
        // 已弃用的同步 HTML 解析实现 —— 已被 MarkdownWebPreview 替代,留空以避免破坏其它引用。
        ScrollView {
            VStack(alignment: .leading) {
                Text("")  // 占位
            }
        }
        .background(theme.previewBackground)
    }
}

/// 用 WKWebView 渲染 Markdown 预览 —— 在子进程解析 HTML,不会阻塞主线程。
struct MarkdownWebPreview: NSViewRepresentable {
    let html: String
    let baseURL: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        let web = WKWebView(frame: .zero, configuration: cfg)
        web.setValue(false, forKey: "drawsBackground")
        web.navigationDelegate = context.coordinator
        return web
    }

    func updateNSView(_ web: WKWebView, context: Context) {
        context.coordinator.lastHTML = html
        let body = Self.wrapHTML(body: html)
        if context.coordinator.loadedHTML == body { return }
        context.coordinator.loadedHTML = body
        let parent = (baseURL as NSString).deletingLastPathComponent
        web.loadHTMLString(body, baseURL: URL(fileURLWithPath: parent))
    }

    /// 把渲染出的 HTML 套上轻量样式（苹方字体、代码块背景、表格边框）。
    static func wrapHTML(body: String) -> String {
        let css = """
        :root { color-scheme: light dark; }
        body {
            font-family: "PingFang SC", "PingFangSC-Regular", -apple-system, sans-serif;
            line-height: 1.65;
            color: #1f1f21;
            background: #ffffff;
            max-width: 720px;
            margin: 0 auto;
            padding: 24px 28px 80px;
        }
        @media (prefers-color-scheme: dark) {
            body { color: #ececef; background: #1a1a1c; }
            a { color: #f08c6b; }
            pre, code { background: rgba(255,255,255,0.06); }
            blockquote { color: #b9b9bb; border-left-color: #444449; }
            table, th, td { border-color: #38383d; }
            hr { border-color: #2c2c30; }
        }
        h1, h2, h3, h4, h5, h6 {
            font-family: "PingFang SC", "PingFangSC-Semibold", sans-serif;
            font-weight: 600;
            margin: 1.4em 0 0.6em;
            line-height: 1.3;
        }
        h1 { font-size: 1.8em; border-bottom: 1px solid #e3e3e6; padding-bottom: 0.25em; }
        h2 { font-size: 1.45em; }
        h3 { font-size: 1.2em; }
        p { margin: 0.8em 0; }
        a { color: #bf5233; text-decoration: none; }
        a:hover { text-decoration: underline; }
        code {
            font-family: "SF Mono", Menlo, Consolas, monospace;
            font-size: 0.88em;
            padding: 1px 5px;
            border-radius: 4px;
            background: rgba(0,0,0,0.06);
        }
        pre {
            font-family: "SF Mono", Menlo, Consolas, monospace;
            padding: 14px 16px;
            border-radius: 8px;
            background: rgba(0,0,0,0.05);
            overflow-x: auto;
            line-height: 1.5;
        }
        pre code { background: transparent; padding: 0; }
        blockquote {
            margin: 1em 0;
            padding: 4px 14px;
            border-left: 3px solid #d3d3d6;
            color: #555;
        }
        ul, ol { padding-left: 1.6em; }
        li { margin: 0.25em 0; }
        img { max-width: 100%; border-radius: 6px; }
        table { border-collapse: collapse; margin: 1em 0; }
        th, td { border: 1px solid #e3e3e6; padding: 6px 10px; }
        th { background: rgba(0,0,0,0.03); }
        hr { border: none; border-top: 1px solid #e3e3e6; margin: 1.6em 0; }
        .task-item input { margin-right: 6px; }
        """
        return """
        <!DOCTYPE html>
        <html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><style>\(css)</style></head><body>\(body)</body></html>
        """
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var loadedHTML: String = ""
        var lastHTML: String = ""
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {}
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
                if url.scheme == "http" || url.scheme == "https" {
                    NSWorkspace.shared.open(url)
                    decisionHandler(.cancel)
                    return
                }
            }
            decisionHandler(.allow)
        }
    }
}

// MARK: - 浏览器预览

struct PreviewView: View {
    let url: URL
    let project: BlogProject
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "globe")
                    .foregroundStyle(theme.accent)
                Text("本地预览")
                    .font(AppFont.headline())
                    .foregroundStyle(theme.ink)
                Text(url.absoluteString)
                    .font(AppFont.monoCaption())
                    .foregroundStyle(theme.inkTertiary)
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
            .background(theme.background)
            .overlay(Rectangle().fill(theme.divider).frame(height: 0.5), alignment: .bottom)
            WebPreview(url: url)
        }
    }
}

// MARK: - 控制台

struct ConsoleView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.theme) private var theme
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
                    .font(AppFont.captionMedium())
                    .foregroundStyle(theme.consoleText.opacity(0.85))
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
                    .font(AppFont.caption())
                    .foregroundStyle(theme.consoleTextDim)
                Button {
                    appState.clearLog()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("清空")
                .foregroundStyle(theme.consoleTextDim)
                Button {
                    appState.consoleVisible = false
                } label: {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(.borderless)
                .help("收起 (⌘`)")
                .foregroundStyle(theme.consoleTextDim)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(theme.consoleBackground.opacity(0.85))

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(filtered) { entry in
                            ConsoleLine(entry: entry).id(entry.id)
                        }
                    }
                    .padding(.vertical, 6)
                }
                .background(theme.consoleBackground)
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
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(time)
                .font(AppFont.monoCaption(size: 10))
                .foregroundStyle(theme.consoleTextDim)
                .frame(width: 60, alignment: .leading)
            Text(prefix)
                .font(AppFont.monoCaption(size: 10).weight(.semibold))
                .foregroundStyle(color)
                .frame(width: 50, alignment: .leading)
            Text(entry.message)
                .font(AppFont.mono(size: 12))
                .foregroundStyle(theme.consoleText)
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
        case .info: return theme.consoleTextDim
        case .success: return theme.success
        case .warn: return theme.warn
        case .error: return theme.errorColor
        }
    }
}
