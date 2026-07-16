import SwiftUI
import SkycBlogCore

/// 主窗口。
struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedSection: SidebarSection? = .posts

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selectedSection)
                .frame(minWidth: 200)
        } content: {
            ContentListView(section: selectedSection ?? .posts)
                .frame(minWidth: 280)
        } detail: {
            DetailView()
                .frame(minWidth: 480)
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                ProjectPathLabel()
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    appState.runBuild()
                } label: {
                    Label("构建", systemImage: "hammer")
                }
                .help("构建站点")
                .disabled(appState.project == nil || appState.isWorking)

                Button {
                    appState.runServe()
                } label: {
                    Label("预览", systemImage: "play.circle")
                }
                .help("启动本地预览")
                .disabled(appState.project == nil)

                Button {
                    appState.showNewPost = true
                } label: {
                    Label("新建文章", systemImage: "square.and.pencil")
                }
                .help("新建文章")
                .disabled(appState.project == nil)
            }
        }
        .sheet(isPresented: $appState.showNewProject) {
            NewProjectSheet()
                .environmentObject(appState)
        }
        .sheet(isPresented: $appState.showOpenProject) {
            OpenProjectSheet()
                .environmentObject(appState)
        }
        .sheet(isPresented: $appState.showNewPost) {
            NewPostSheet()
                .environmentObject(appState)
        }
    }
}

enum SidebarSection: String, Hashable, CaseIterable, Identifiable {
    case posts = "文章"
    case pages = "页面"
    case drafts = "草稿"
    case albums = "相册"
    case tags = "标签"
    case categories = "分类"
    case plugins = "插件"
    case settings = "设置"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .posts: return "doc.text"
        case .pages: return "doc.richtext"
        case .drafts: return "pencil.and.outline"
        case .albums: return "photo.stack"
        case .tags: return "tag"
        case .categories: return "folder"
        case .plugins: return "puzzlepiece"
        case .settings: return "gearshape"
        }
    }
}

struct SidebarView: View {
    @Binding var selection: SidebarSection?
    @EnvironmentObject var appState: AppState

    var body: some View {
        List(SidebarSection.allCases, selection: $selection) { section in
            NavigationLink(value: section) {
                Label(section.rawValue, systemImage: section.systemImage)
            }
        }
        .navigationTitle("SkycBlog")
        .listStyle(.sidebar)
    }
}

struct ProjectPathLabel: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        if let project = appState.project {
            HStack(spacing: 6) {
                Image(systemName: "folder")
                Text(project.root.lastPathComponent)
                    .font(.headline)
                Text("·")
                    .foregroundStyle(.secondary)
                Text(project.root.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        } else {
            Text("未打开项目")
                .foregroundStyle(.secondary)
        }
    }
}

struct ContentListView: View {
    let section: SidebarSection
    @EnvironmentObject var appState: AppState

    var body: some View {
        Group {
            switch section {
            case .posts:
                PostsListView()
            case .pages:
                PagesListView()
            case .drafts:
                DraftsListView()
            case .albums:
                AlbumsListView()
            case .tags:
                TagsListView()
            case .categories:
                CategoriesListView()
            case .plugins:
                PluginsListView()
            case .settings:
                SettingsView()
            }
        }
        .navigationTitle(section.rawValue)
    }
}

struct DetailView: View {
    @EnvironmentObject var appState: AppState
    @State private var logExpanded: Bool = true

    var body: some View {
        VSplitView {
            WebPreviewPane()
                .frame(minHeight: 320)
            VStack(spacing: 0) {
                HStack {
                    Button {
                        withAnimation { logExpanded.toggle() }
                    } label: {
                        Image(systemName: logExpanded ? "chevron.down" : "chevron.up")
                    }
                    .buttonStyle(.borderless)
                    Text("日志")
                        .font(.headline)
                    Spacer()
                    if appState.isWorking {
                        ProgressView()
                            .controlSize(.small)
                        Text("正在工作…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.bar)

                if logExpanded {
                    LogView()
                        .frame(minHeight: 120, maxHeight: 240)
                }
            }
        }
    }
}

struct WebPreviewPane: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Group {
            if let url = appState.previewURL {
                WebPreview(url: url)
            } else {
                ContentUnavailableView(
                    "无预览",
                    systemImage: "globe",
                    description: Text("点击工具栏的「预览」按钮启动本地服务器")
                )
            }
        }
    }
}

struct LogView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(appState.log) { entry in
                        LogRow(entry: entry)
                            .id(entry.id)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
            .onChange(of: appState.log.count) { _, _ in
                if let last = appState.log.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
        .background(.background.secondary)
    }
}

struct LogRow: View {
    let entry: LogEntry

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text(timeString)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
            Text(prefix)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(color)
                .frame(width: 24, alignment: .leading)
            Text(entry.message)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
        }
    }

    private var timeString: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: entry.date)
    }

    private var prefix: String {
        switch entry.level {
        case .info: return "INFO"
        case .success: return "OK"
        case .warn: return "WARN"
        case .error: return "ERR"
        }
    }

    private var color: Color {
        switch entry.level {
        case .info: return .secondary
        case .success: return .green
        case .warn: return .orange
        case .error: return .red
        }
    }
}
