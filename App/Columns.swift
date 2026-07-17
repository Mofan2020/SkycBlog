import SwiftUI
import SkycBlogCore
import AppKit

// MARK: - 侧栏 (Sidebar)

struct SidebarView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 顶部 logo + 项目名
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "doc.text.fill")
                        .foregroundStyle(theme.accent)
                    Text(appState.project?.config.title ?? "SkycBlog")
                        .font(AppFont.headline())
                        .foregroundStyle(theme.ink)
                        .lineLimit(1)
                }
                if let project = appState.project {
                    Text(project.root.path)
                        .font(AppFont.monoCaption())
                        .foregroundStyle(theme.inkTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .padding(16)
            Divider().background(theme.divider)

            // 分组导航
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    group(title: "内容", items: LibrarySection.contentSections)
                    group(title: "分类与标签", items: LibrarySection.taxonomySections)
                    group(title: "项目", items: LibrarySection.adminSections)
                }
                .padding(.vertical, 12)
            }
        }
        .background(theme.surface)
    }

    @ViewBuilder
    private func group(title: String, items: [LibrarySection]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(AppFont.eyebrow())
                .foregroundStyle(theme.inkTertiary)
                .textCase(.uppercase)
                .tracking(1.2)
                .padding(.horizontal, 16).padding(.bottom, 4)
            ForEach(items) { section in
                SidebarRow(section: section, isSelected: appState.selection == section) {
                    appState.selection = section
                    if section != .themes { appState.clearThemeSelection() }
                }
            }
        }
    }
}

struct SidebarRow: View {
    @Environment(\.theme) private var theme
    let section: LibrarySection
    let isSelected: Bool
    let onTap: () -> Void
    @State private var hovered: Bool = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: section.systemImage)
                    .frame(width: 18)
                    .foregroundStyle(isSelected ? theme.accent : theme.inkSecondary)
                Text(section.rawValue)
                    .font(AppFont.body())
                    .foregroundStyle(isSelected ? theme.ink : theme.inkSecondary)
                Spacer()
                if let count = appState.sectionCount(section) {
                    Text("\(count)")
                        .font(AppFont.monoCaption())
                        .foregroundStyle(theme.inkTertiary)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(theme.tagBackground)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 7)
            .background(background)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }

    @EnvironmentObject var appState: AppState
    private var background: some View {
        Group {
            if isSelected { theme.cardHover }
            else if hovered { theme.cardBackground }
            else { Color.clear }
        }
    }
}

extension AppState {
    /// 给侧栏行的数字徽标
    func sectionCount(_ s: LibrarySection) -> Int? {
        guard let p = project else { return nil }
        switch s {
        case .posts: return p.posts.count
        case .drafts: return p.drafts.count
        case .pages: return p.pages.count
        case .albums: return p.albums.count
        case .tags: return p.allTags.count
        case .categories: return p.allCategories.count
        case .assets: return nil
        case .plugins: return listPlugins().count
        case .themes: return listThemes().count
        case .settings: return nil
        }
    }
}

// MARK: - 中间列 (Middle Column)

struct MiddleColumnView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        switch appState.selection {
        case .posts:     PostsList()
        case .drafts:    DraftsList()
        case .pages:     PagesList()
        case .albums:    AlbumsList()
        case .tags:      TagManagerView()
        case .categories: CategoryManagerView()
        case .assets:    AssetsList()
        case .plugins:   PluginListView()
        case .themes:    ThemeManagerView()
        case .settings:  ProjectSettingsView()
        }
    }
}

struct ListHeader: View {
    @Environment(\.theme) private var theme
    let icon: String
    let title: String
    let count: Int
    var trailing: AnyView? = nil

    var body: some View {
        HStack {
            Image(systemName: icon).foregroundStyle(theme.accent)
            Text(title).font(AppFont.headline()).foregroundStyle(theme.ink)
            Text("\(count)").font(AppFont.monoCaption()).foregroundStyle(theme.inkTertiary)
            Spacer()
            if let trailing = trailing { trailing }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(theme.surface)
    }
}

struct EmptyState: View {
    @Environment(\.theme) private var theme
    let icon: String
    let text: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 36))
                .foregroundStyle(theme.inkTertiary)
            Text(text)
                .font(AppFont.caption())
                .foregroundStyle(theme.inkTertiary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

// MARK: - 文章列表

struct PostsList: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            ListHeader(icon: "doc.text", title: "文章", count: appState.project?.posts.count ?? 0,
                       trailing: AnyView(
                        Button {
                            appState.sheet = .newPost
                        } label: { Image(systemName: "plus") }
                        .buttonStyle(.borderless)
                       ))
            if let posts = appState.project?.posts, !posts.isEmpty {
                List(posts) { page in
                    PageRow(page: page)
                        .listRowBackground(
                            appState.selectedPageID == page.id ? theme.cardHover : Color.clear
                        )
                        .onTapGesture { appState.selectedPageID = page.id }
                }
                .listStyle(.inset)
            } else {
                EmptyState(icon: "doc.text", text: "还没有文章\n点击右上角 + 创建")
            }
        }
    }
}

struct DraftsList: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            ListHeader(icon: "pencil.and.outline", title: "草稿", count: appState.project?.drafts.count ?? 0)
            if let drafts = appState.project?.drafts, !drafts.isEmpty {
                List(drafts) { page in
                    PageRow(page: page)
                        .listRowBackground(
                            appState.selectedPageID == page.id ? theme.cardHover : Color.clear
                        )
                        .onTapGesture { appState.selectedPageID = page.id }
                }
                .listStyle(.inset)
            } else {
                EmptyState(icon: "pencil.and.outline", text: "没有草稿")
            }
        }
    }
}

struct PagesList: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            ListHeader(icon: "doc.richtext", title: "页面", count: appState.project?.pages.count ?? 0)
            if let pages = appState.project?.pages, !pages.isEmpty {
                List(pages) { page in
                    PageRow(page: page)
                        .listRowBackground(
                            appState.selectedPageID == page.id ? theme.cardHover : Color.clear
                        )
                        .onTapGesture { appState.selectedPageID = page.id }
                }
                .listStyle(.inset)
            } else {
                EmptyState(icon: "doc.richtext", text: "没有独立页面")
            }
        }
    }
}

struct AssetsList: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            ListHeader(icon: "photo", title: "资源", count: 0,
                       trailing: AnyView(
                        Button {
                            openInFinder()
                        } label: { Image(systemName: "folder") }
                        .buttonStyle(.borderless)
                        .help("在 Finder 中打开")
                       ))
            EmptyState(icon: "photo", text: "资源管理请在 Finder 中操作\n`static/` 目录下的文件会被原样复制到 `output/`")
        }
    }

    private func openInFinder() {
        guard let p = appState.project else { return }
        let staticDir = p.root.appendingPathComponent("static")
        try? FileManager.default.createDirectory(at: staticDir, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([staticDir])
    }
}

struct ProjectSettingsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.theme) private var theme

    // 本地编辑态
    @State private var title: String = ""
    @State private var description: String = ""
    @State private var author: String = ""
    @State private var language: String = ""
    @State private var baseURL: String = ""
    @State private var outputDir: String = ""
    @State private var permalink: String = ""
    @State private var paginationSize: Int = 10
    @State private var buildDrafts: Bool = false
    @State private var minifyHTML: Bool = true
    @State private var fingerprintAssets: Bool = false
    @State private var generateSearchIndex: Bool = true
    @State private var generateRSS: Bool = true
    @State private var generateSitemap: Bool = true
    @State private var loaded: Bool = false
    @State private var savedHint: String? = nil

    var body: some View {
        if let p = appState.project {
            VStack(alignment: .leading, spacing: 0) {
                ListHeader(icon: "gearshape", title: "项目设置", count: 0,
                           trailing: AnyView(
                            Button {
                                save()
                            } label: { Label("保存", systemImage: "checkmark.circle.fill") }
                            .buttonStyle(.borderedProminent)
                            .keyboardShortcut("s", modifiers: .command)
                            .help("保存 (⌘S)")
                           ))

                ScrollView {
                    Form {
                        Section("基本信息") {
                            TextField("标题", text: $title)
                            TextField("描述", text: $description, axis: .vertical)
                                .lineLimit(1...3)
                            TextField("作者", text: $author)
                            HStack {
                                Text("语言")
                                    .frame(width: 80, alignment: .leading)
                                TextField("如 zh-CN / en", text: $language)
                            }
                        }
                        Section("URL 与目录") {
                            TextField("基础 URL (baseURL)", text: $baseURL)
                                .help("如 https://example.com/ 或 /")
                            TextField("输出目录 (outputDir)", text: $outputDir)
                                .help("相对项目根的路径, 如 output")
                            TextField("永久链接格式", text: $permalink)
                                .help("如 /:year/:month/:day/:slug/ 或 /posts/:slug/")
                            HStack {
                                Text("每页文章数")
                                    .frame(width: 120, alignment: .leading)
                                Stepper(value: $paginationSize, in: 1...100) {
                                    Text("\(paginationSize)").monospacedDigit()
                                }
                            }
                        }
                        Section("构建选项") {
                            Toggle("包含草稿", isOn: $buildDrafts)
                            Toggle("压缩 HTML", isOn: $minifyHTML)
                            Toggle("静态资源指纹 (cache busting)", isOn: $fingerprintAssets)
                        }
                        Section("生成开关") {
                            Toggle("生成 RSS", isOn: $generateRSS)
                            Toggle("生成 sitemap.xml", isOn: $generateSitemap)
                            Toggle("生成 search.json", isOn: $generateSearchIndex)
                        }
                        Section {
                            HStack {
                                Button("在 Finder 中显示项目") {
                                    NSWorkspace.shared.activateFileViewerSelecting([p.root])
                                }
                                Spacer()
                                if let hint = savedHint {
                                    Label(hint, systemImage: "checkmark.seal.fill")
                                        .font(AppFont.caption())
                                        .foregroundStyle(theme.accent)
                                        .transition(.opacity)
                                }
                            }
                        } header: {
                            Text("操作")
                        }
                    }
                    .formStyle(.grouped)
                    .padding(.bottom, 24)
                }
            }
            .onAppear { hydrate() }
            .onChange(of: appState.project?.root.path) { _, _ in hydrate() }
        } else {
            EmptyState(icon: "gearshape", text: "没有打开的项目")
        }
    }

    private func hydrate() {
        guard let cfg = appState.project?.config else { return }
        title = cfg.title
        description = cfg.description
        author = cfg.author
        language = cfg.language
        baseURL = cfg.baseURL
        outputDir = cfg.outputDir
        permalink = cfg.permalink
        paginationSize = cfg.paginationSize
        buildDrafts = cfg.buildDrafts
        minifyHTML = cfg.minifyHTML
        fingerprintAssets = cfg.fingerprintAssets
        generateSearchIndex = cfg.generateSearchIndex
        generateRSS = cfg.generateRSS
        generateSitemap = cfg.generateSitemap
        loaded = true
    }

    private func save() {
        guard let project = appState.project else { return }
        var cfg = project.config
        cfg.title = title
        cfg.description = description
        cfg.author = author
        cfg.language = language
        cfg.baseURL = baseURL
        cfg.outputDir = outputDir
        cfg.permalink = permalink
        cfg.paginationSize = paginationSize
        cfg.buildDrafts = buildDrafts
        cfg.minifyHTML = minifyHTML
        cfg.fingerprintAssets = fingerprintAssets
        cfg.generateSearchIndex = generateSearchIndex
        cfg.generateRSS = generateRSS
        cfg.generateSitemap = generateSitemap
        do {
            try ConfigWriter.write(cfg, to: project.root.path)
            project.refresh()
            withAnimation { savedHint = "已保存 (\(Date().formatted(date: .omitted, time: .shortened)))" }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                withAnimation { savedHint = nil }
            }
        } catch {
            appState.log(.error("保存失败：\(error.localizedDescription)"))
        }
    }
}

// MARK: - 文章行 (右键菜单: 编辑元数据 / 重命名 / 删除)

struct PageRow: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.theme) private var theme
    let page: Page

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(page.title)
                    .font(AppFont.body())
                    .foregroundStyle(theme.ink)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if page.draft {
                        Text("草稿")
                            .font(AppFont.monoCaption())
                            .foregroundStyle(theme.accent)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(theme.tagBackground)
                            .clipShape(Capsule())
                    }
                    if !page.tags.isEmpty {
                        Text(page.tags.prefix(3).map { "#\($0)" }.joined(separator: " "))
                            .font(AppFont.monoCaption())
                            .foregroundStyle(theme.inkTertiary)
                            .lineLimit(1)
                    }
                }
            }
            Spacer()
            Text(Self.formatter.string(from: page.date))
                .font(AppFont.monoCaption())
                .foregroundStyle(theme.inkTertiary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .contextMenu {
            Button("编辑元数据…") { appState.metadataPageTarget = page }
            Button("重命名…") { appState.renamePageTarget = page }
            Divider()
            Button(role: .destructive) {
                appState.deletePage(page)
            } label: { Text("删除") }
        }
    }

    static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

// MARK: - 相册列表 (含 + 按钮, 双击进详情)

struct AlbumsList: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            ListHeader(icon: "photo.stack", title: "相册", count: appState.project?.albums.count ?? 0,
                       trailing: AnyView(
                        Button {
                            appState.newAlbumSheet = true
                        } label: { Image(systemName: "plus") }
                        .buttonStyle(.borderless)
                        .help("新建相册")
                       ))
            if let albums = appState.project?.albums, !albums.isEmpty {
                List(albums) { album in
                    AlbumRow(album: album)
                        .listRowBackground(
                            appState.selectedAlbumID == album.id ? theme.cardHover : Color.clear
                        )
                        .onTapGesture(count: 2) {
                            appState.selectedAlbumID = album.id
                            appState.selectedPageID = nil
                            // 用一个临时 navigation: 用 sheet 展开详情
                            appState.openAlbumDetail(album: album)
                        }
                }
                .listStyle(.inset)
            } else {
                EmptyState(icon: "photo.stack", text: "还没有相册\n点击右上角 + 创建")
            }
        }
    }
}

struct AlbumRow: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.theme) private var theme
    let album: Page

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "photo.stack.fill")
                .foregroundStyle(theme.accent)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(album.title.isEmpty ? album.id : album.title)
                    .font(AppFont.body())
                    .foregroundStyle(theme.ink)
                    .lineLimit(1)
                Text(album.id)
                    .font(AppFont.monoCaption())
                    .foregroundStyle(theme.inkTertiary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .contextMenu {
            Button("打开") { appState.openAlbumDetail(album: album) }
            Button("重命名…") { appState.renameAlbumTarget = album }
            Divider()
            Button(role: .destructive) {
                let slug = (album.sourcePath as NSString).deletingLastPathComponent.components(separatedBy: "/").last ?? ""
                appState.deleteAlbum(name: slug)
            } label: { Text("删除相簿") }
        }
    }
}
