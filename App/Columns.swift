import SwiftUI
import SkycBlogCore

// MARK: - 左侧栏

struct SidebarView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        List(selection: $appState.selection) {
            Section {
                ForEach(LibrarySection.contentSections) { section in
                    NavigationLink(value: section) {
                        Label {
                            HStack {
                                Text(section.rawValue)
                                Spacer()
                                Text("\(count(for: section))")
                                    .font(.caption)
                                    .foregroundStyle(Theme.inkTertiary)
                            }
                        } icon: {
                            Image(systemName: section.systemImage)
                        }
                    }
                }
            }
            Section("分类法") {
                ForEach(LibrarySection.taxonomySections) { section in
                    NavigationLink(value: section) {
                        Label(section.rawValue, systemImage: section.systemImage)
                    }
                }
            }
            Section("管理") {
                ForEach(LibrarySection.adminSections) { section in
                    NavigationLink(value: section) {
                        Label(section.rawValue, systemImage: section.systemImage)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("SkycBlog")
        .safeAreaInset(edge: .bottom) {
            ServerControlStrip()
        }
    }

    private func count(for section: LibrarySection) -> Int {
        guard let p = appState.project else { return 0 }
        switch section {
        case .posts: return p.posts.count
        case .drafts: return p.drafts.count
        case .pages: return p.pages.count
        case .albums: return p.albums.count
        default: return 0
        }
    }
}

struct ServerControlStrip: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(appState.isServing ? Theme.success : Theme.inkTertiary)
                .frame(width: 8, height: 8)
            Text(appState.isServing ? "预览运行中 · 8765" : "预览未启动")
                .font(.caption)
                .foregroundStyle(Theme.inkSecondary)
            Spacer()
            if appState.isServing {
                Button("停止") { appState.stopServer() }
                    .controlSize(.mini)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.cardBackground)
    }
}

// MARK: - 中间栏

struct MiddleColumnView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Group {
            switch appState.selection {
            case .posts:      PagesList(title: "文章", icon: "doc.text", pages: appState.project?.posts ?? [], allowNew: true, newIsPost: true)
            case .drafts:     PagesList(title: "草稿", icon: "pencil.and.outline", pages: appState.project?.drafts ?? [], allowNew: false)
            case .pages:      PagesList(title: "页面", icon: "doc.richtext", pages: appState.project?.pages ?? [], allowNew: true, newIsPost: false)
            case .albums:     AlbumsList()
            case .tags:       TagList()
            case .categories: CategoryList()
            case .assets:     AssetsList()
            case .plugins:    PluginList()
            case .settings:   SettingsList()
            }
        }
    }
}

// MARK: - 文章/页面列表

struct PagesList: View {
    @EnvironmentObject var appState: AppState
    let title: String
    let icon: String
    let pages: [Page]
    let allowNew: Bool
    var newIsPost: Bool = true
    @State private var search: String = ""

    var filtered: [Page] {
        guard !search.isEmpty else { return pages }
        return pages.filter {
            $0.title.localizedCaseInsensitiveContains(search) ||
            $0.tags.joined(separator: ",").localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ListHeader(
                title: title,
                subtitle: "\(filtered.count) / \(pages.count)",
                icon: icon,
                trailing: AnyView(
                    HStack(spacing: 4) {
                        if allowNew {
                            Button {
                                appState.sheet = .newPost
                            } label: {
                                Image(systemName: "plus")
                            }
                            .buttonStyle(.borderless)
                            .help("新建")
                        }
                    }
                )
            )
            if !pages.isEmpty {
                TextField("搜索…", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }
            if filtered.isEmpty {
                EmptyState(icon: icon, text: pages.isEmpty ? "还没有内容" : "没有匹配项")
            } else {
                List(selection: $appState.selectedPageID) {
                    ForEach(filtered) { page in
                        PageRow(page: page)
                            .tag(page.id as String?)
                            .contextMenu {
                                Button("在 Finder 中显示") {
                                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: page.sourcePath)])
                                }
                                Divider()
                                Button("删除", role: .destructive) { appState.deletePage(page) }
                            }
                    }
                }
                .listStyle(.inset)
            }
        }
    }
}

struct PageRow: View {
    let page: Page

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(page.title)
                    .font(.system(.body))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Spacer()
                StatusBadge(status: page.extra["status"] as? String)
            }
            HStack(spacing: 6) {
                Text(DateUtil.human.string(from: page.date))
                if !page.tags.isEmpty {
                    Text("·")
                    ForEach(page.tags.prefix(2), id: \.self) { tag in
                        Text("#\(tag)")
                    }
                    if page.tags.count > 2 {
                        Text("+\(page.tags.count - 2)")
                    }
                }
            }
            .font(.caption)
            .foregroundStyle(Theme.inkTertiary)
        }
        .padding(.vertical, 3)
    }
}

struct StatusBadge: View {
    let status: String?
    var body: some View {
        if let status, !status.isEmpty {
            Text(status)
                .font(.system(.caption2, design: .monospaced))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Theme.tagBackground)
                .clipShape(Capsule())
                .foregroundStyle(Theme.inkSecondary)
        }
    }
}

struct ListHeader: View {
    let title: String
    let subtitle: String
    let icon: String
    let trailing: AnyView

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(Theme.inkSecondary)
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(.title3, design: .serif).weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Theme.inkTertiary)
            }
            Spacer()
            trailing
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Theme.background)
        .overlay(Divider(), alignment: .bottom)
    }
}

struct EmptyState: View {
    let icon: String
    let text: String
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(Theme.inkTertiary)
            Text(text)
                .font(.system(.body, design: .serif))
                .foregroundStyle(Theme.inkSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 其他列表

struct AlbumsList: View {
    @EnvironmentObject var appState: AppState
    var body: some View {
        if let project = appState.project {
            if project.albums.isEmpty {
                EmptyState(icon: "photo.stack", text: "还没有相册")
            } else {
                List(project.albums) { album in
                    HStack {
                        Image(systemName: "photo.stack")
                            .foregroundStyle(Theme.inkSecondary)
                        VStack(alignment: .leading) {
                            Text(album.title)
                            Text(album.url).font(.caption).foregroundStyle(Theme.inkTertiary)
                        }
                    }
                }
            }
        }
    }
}

struct TagList: View {
    @EnvironmentObject var appState: AppState
    var body: some View {
        if let project = appState.project, !project.allTags.isEmpty {
            List(Array(project.allTags.keys).sorted(), id: \.self) { tag in
                HStack {
                    Text("#\(tag)")
                    Spacer()
                    Text("\(project.allTags[tag]?.count ?? 0)")
                        .font(.caption)
                        .foregroundStyle(Theme.inkTertiary)
                }
            }
        } else {
            EmptyState(icon: "tag", text: "暂无标签")
        }
    }
}

struct CategoryList: View {
    @EnvironmentObject var appState: AppState
    var body: some View {
        if let project = appState.project, !project.allCategories.isEmpty {
            List(Array(project.allCategories.keys).sorted(), id: \.self) { cat in
                HStack {
                    Image(systemName: "folder")
                        .foregroundStyle(Theme.inkSecondary)
                    Text(cat)
                    Spacer()
                    Text("\(project.allCategories[cat]?.count ?? 0)")
                        .font(.caption)
                        .foregroundStyle(Theme.inkTertiary)
                }
            }
        } else {
            EmptyState(icon: "folder", text: "暂无分类")
        }
    }
}

struct AssetsList: View {
    @EnvironmentObject var appState: AppState
    @State private var files: [URL] = []
    @State private var hovered: URL? = nil

    var body: some View {
        VStack(spacing: 0) {
            ListHeader(title: "资源", subtitle: "\(files.count) 个文件", icon: "photo", trailing: AnyView(EmptyView()))
            if files.isEmpty {
                EmptyState(icon: "photo", text: "static/ 目录为空")
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 12)], spacing: 12) {
                        ForEach(files, id: \.self) { url in
                            AssetThumb(url: url, isHovered: hovered == url)
                                .onHover { hovered = $0 ? url : nil }
                        }
                    }
                    .padding(16)
                }
            }
        }
        .onAppear { reload() }
    }

    private func reload() {
        guard let root = appState.project?.root else { return }
        let dir = root.appendingPathComponent("static")
        files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
    }
}

struct AssetThumb: View {
    let url: URL
    let isHovered: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Theme.cardBackground)
                if let img = NSImage(contentsOf: url) {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    Image(systemName: "doc")
                        .font(.system(size: 28))
                        .foregroundStyle(Theme.inkTertiary)
                }
            }
            .frame(height: 80)
            Text(url.lastPathComponent)
                .font(.caption)
                .foregroundStyle(Theme.inkSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .scaleEffect(isHovered ? 1.03 : 1.0)
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}

struct PluginList: View {
    @EnvironmentObject var appState: AppState
    @State private var scripts: [URL] = []

    var body: some View {
        VStack(spacing: 0) {
            ListHeader(title: "插件", subtitle: "scripts/*.js", icon: "puzzlepiece", trailing: AnyView(EmptyView()))
            if scripts.isEmpty {
                EmptyState(icon: "puzzlepiece", text: "将 .js 脚本放入 scripts/ 目录")
            } else {
                List(scripts, id: \.self) { url in
                    HStack {
                        Image(systemName: "curlybraces")
                            .foregroundStyle(Theme.accent)
                        VStack(alignment: .leading) {
                            Text(url.lastPathComponent)
                            Text(url.path)
                                .font(.caption)
                                .foregroundStyle(Theme.inkTertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }
            }
        }
        .onAppear {
            if let root = appState.project?.root {
                let dir = root.appendingPathComponent("scripts")
                scripts = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            }
        }
    }
}

struct SettingsList: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            ListHeader(title: "项目设置", subtitle: "config.yaml", icon: "gearshape", trailing: AnyView(EmptyView()))
            if let project = appState.project {
                Form {
                    Section("基本信息") {
                        LabeledContent("标题", value: project.config.title)
                        LabeledContent("作者", value: project.config.author.isEmpty ? "—" : project.config.author)
                        LabeledContent("语言", value: project.config.language)
                        LabeledContent("主题", value: project.config.themeName)
                    }
                    Section("构建") {
                        LabeledContent("输出目录", value: project.config.outputDir)
                        LabeledContent("永久链接", value: project.config.permalink)
                        Toggle("生成 RSS", isOn: .constant(project.config.generateRSS))
                        Toggle("生成 Sitemap", isOn: .constant(project.config.generateSitemap))
                        Toggle("生成搜索索引", isOn: .constant(project.config.generateSearchIndex))
                        Toggle("压缩 HTML", isOn: .constant(project.config.minifyHTML))
                    }
                    Section("路径") {
                        LabeledContent("根目录") {
                            Text(project.root.path)
                                .font(Theme.monoCaption)
                                .foregroundStyle(Theme.inkSecondary)
                                .textSelection(.enabled)
                        }
                    }
                    Section {
                        Button("在 Finder 中显示") { appState.revealProjectInFinder() }
                        Button("关闭项目", role: .destructive) { appState.closeProject() }
                    }
                }
                .formStyle(.grouped)
            }
        }
    }
}
