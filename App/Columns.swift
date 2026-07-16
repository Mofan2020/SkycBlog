import SwiftUI
import SkycBlogCore
import AppKit

// MARK: - 左侧栏

struct SidebarView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.theme) private var theme

    var body: some View {
        List(selection: $appState.selection) {
            Section {
                ForEach(LibrarySection.contentSections) { section in
                    NavigationLink(value: section) {
                        sidebarRow(section: section, showCount: true)
                    }
                }
            }
            Section("分类法") {
                ForEach(LibrarySection.taxonomySections) { section in
                    NavigationLink(value: section) {
                        sidebarRow(section: section, showCount: false)
                    }
                }
            }
            Section("管理") {
                ForEach(LibrarySection.adminSections) { section in
                    NavigationLink(value: section) {
                        sidebarRow(section: section, showCount: false)
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

    @ViewBuilder
    private func sidebarRow(section: LibrarySection, showCount: Bool) -> some View {
        if showCount {
            Label {
                HStack {
                    Text(section.rawValue)
                        .font(AppFont.body())
                    Spacer()
                    if count(for: section) > 0 {
                        Text("\(count(for: section))")
                            .font(AppFont.monoCaption())
                            .foregroundStyle(theme.inkTertiary)
                    }
                }
            } icon: {
                Image(systemName: section.systemImage)
                    .foregroundStyle(theme.inkSecondary)
            }
        } else {
            Label {
                Text(section.rawValue)
                    .font(AppFont.body())
            } icon: {
                Image(systemName: section.systemImage)
                    .foregroundStyle(theme.inkSecondary)
            }
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
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(appState.isServing ? theme.success : theme.inkTertiary)
                .frame(width: 8, height: 8)
            Text(appState.isServing ? "预览运行中 · 8765" : "预览未启动")
                .font(AppFont.caption())
                .foregroundStyle(theme.inkSecondary)
            Spacer()
            if appState.isServing {
                Button("停止") { appState.stopServer() }
                    .controlSize(.mini)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(theme.cardBackground)
    }
}

// MARK: - 中间栏

struct MiddleColumnView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Group {
            switch appState.selection {
            case .posts:      PagesList(title: "文章", icon: "doc.text", pages: appState.project?.posts ?? [], allowNew: true)
            case .drafts:     PagesList(title: "草稿", icon: "pencil.and.outline", pages: appState.project?.drafts ?? [], allowNew: false)
            case .pages:      PagesList(title: "页面", icon: "doc.richtext", pages: appState.project?.pages ?? [], allowNew: true)
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
    @Environment(\.theme) private var theme
    let title: String
    let icon: String
    let pages: [Page]
    let allowNew: Bool
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
                            .listRowSeparator(.visible)
                            .contextMenu {
                                Button("编辑元数据…") {
                                    appState.metadataPageTarget = page
                                }
                                Button("重命名…") {
                                    appState.renamePageTarget = page
                                }
                                Divider()
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
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(page.title)
                    .font(AppFont.body())
                    .foregroundStyle(theme.ink)
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
            .font(AppFont.caption())
            .foregroundStyle(theme.inkTertiary)
        }
        .padding(.vertical, 3)
    }
}

struct StatusBadge: View {
    let status: String?
    @Environment(\.theme) private var theme
    var body: some View {
        if let status, !status.isEmpty {
            Text(status)
                .font(AppFont.monoCaption(size: 10))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(theme.tagBackground)
                .clipShape(Capsule())
                .foregroundStyle(theme.inkSecondary)
        }
    }
}

struct ListHeader: View {
    @Environment(\.theme) private var theme
    let title: String
    let subtitle: String
    let icon: String
    let trailing: AnyView

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(theme.inkSecondary)
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(AppFont.title(size: 18))
                    .foregroundStyle(theme.ink)
                Text(subtitle)
                    .font(AppFont.caption())
                    .foregroundStyle(theme.inkTertiary)
            }
            Spacer()
            trailing
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(theme.background)
        .overlay(Rectangle().fill(theme.divider).frame(height: 0.5), alignment: .bottom)
    }
}

struct EmptyState: View {
    @Environment(\.theme) private var theme
    let icon: String
    let text: String
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(theme.inkTertiary)
            Text(text)
                .font(AppFont.body())
                .foregroundStyle(theme.inkSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 其他列表

struct AlbumsList: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.theme) private var theme
    var body: some View {
        VStack(spacing: 0) {
            ListHeader(
                title: "相册",
                subtitle: "\(appState.project?.albums.count ?? 0) 个",
                icon: "photo.stack",
                trailing: AnyView(
                    HStack(spacing: 4) {
                        Button {
                            appState.newAlbumSheet = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .buttonStyle(.borderless)
                        .help("新建相册")
                    }
                )
            )
            if let project = appState.project {
                if project.albums.isEmpty {
                    EmptyState(icon: "photo.stack", text: "还没有相册,点击 + 新建")
                } else {
                    List(selection: $appState.selectedAlbumID) {
                        ForEach(project.albums) { album in
                            HStack {
                                Image(systemName: "photo.stack")
                                    .foregroundStyle(theme.inkSecondary)
                                VStack(alignment: .leading) {
                                    Text(album.title)
                                        .font(AppFont.body())
                                        .foregroundStyle(theme.ink)
                                    Text(album.url)
                                        .font(AppFont.monoCaption())
                                        .foregroundStyle(theme.inkTertiary)
                                }
                                Spacer()
                            }
                            .tag(album.id as String?)
                            .contextMenu {
                                Button("重命名…") { appState.renameAlbumTarget = album }
                                Button("删除", role: .destructive) {
                                    let dir = (album.sourcePath as NSString).deletingLastPathComponent
                                    let name = (dir as NSString).lastPathComponent
                                    appState.deleteAlbum(name: name)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

struct TagList: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.theme) private var theme
    var body: some View {
        TagManagerView()
    }
}

struct CategoryList: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.theme) private var theme
    var body: some View {
        CategoryManagerView()
    }
}

struct AssetsList: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.theme) private var theme
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
                .background(theme.background)
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
    @Environment(\.theme) private var theme
    let url: URL
    let isHovered: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(theme.cardBackground)
                if let img = NSImage(contentsOf: url) {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    Image(systemName: "doc")
                        .font(.system(size: 28))
                        .foregroundStyle(theme.inkTertiary)
                }
            }
            .frame(height: 80)
            Text(url.lastPathComponent)
                .font(AppFont.caption())
                .foregroundStyle(theme.inkSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .scaleEffect(isHovered ? 1.03 : 1.0)
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}

struct PluginList: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.theme) private var theme
    var body: some View {
        PluginListView()
    }
}

struct SettingsList: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.theme) private var theme

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
                                .font(AppFont.monoCaption())
                                .foregroundStyle(theme.inkSecondary)
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
