import SwiftUI
import SkycBlogCore

/// 根视图：无项目时显示欢迎屏，有项目时显示工作台。
struct RootView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.theme) private var theme

    var body: some View {
        Group {
            if appState.project == nil {
                WelcomeView()
            } else {
                WorkspaceView()
            }
        }
        .themed()
        .background(Color(.windowBackgroundColor))
        .sheet(item: $appState.sheet) { sheet in
            sheetContent(sheet)
                .environmentObject(appState)
                .themed()
        }
        .sheet(item: $appState.renamePageTarget) { page in
            RenamePageSheet(page: page)
                .environmentObject(appState)
                .themed()
        }
        .sheet(item: $appState.metadataPageTarget) { page in
            PageMetadataSheet(page: page)
                .environmentObject(appState)
                .themed()
        }
        .sheet(item: $appState.renameAlbumTarget) { album in
            RenameAlbumSheet(album: album)
                .environmentObject(appState)
                .themed()
        }
        .sheet(isPresented: $appState.newAlbumSheet) {
            NewAlbumSheet()
                .environmentObject(appState)
                .themed()
        }
    }

    @ViewBuilder
    private func sheetContent(_ sheet: AppState.Sheet) -> some View {
        switch sheet {
        case .newProject:  NewProjectSheet()
        case .openProject: OpenProjectSheet()
        case .newPost:     NewPostSheet()
        case .projectInfo: ProjectInfoSheet()
        case .deploy:      DeploySheet()
        }
    }
}

// MARK: - 欢迎屏

struct WelcomeView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 0) {
            // 左侧品牌区
            VStack(alignment: .leading, spacing: 24) {
                Spacer()
                VStack(alignment: .leading, spacing: 16) {
                    Text("SkycBlog")
                        .font(.system(size: 48, weight: .semibold))
                        .foregroundStyle(theme.ink)
                    Text("一个博客管理工具，由Skyc8266制作，希望大家喜欢❤️～\n如果有问题的话可以发邮件到panmofan@icloud.com哦，感谢大家的支持喵")
                        .font(AppFont.body(size: 16))
                        .foregroundStyle(theme.inkSecondary)
                        .lineSpacing(4)
                }
                Spacer()
                Label {
                    Text("v1.0")
                } icon: {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 6))
                        .foregroundStyle(theme.accent)
                }
                .font(AppFont.monoCaption())
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(theme.tagBackground)
                .clipShape(Capsule())
                .foregroundStyle(theme.inkSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 60)
            .background(theme.surface)

            // 右侧操作区
            VStack(alignment: .leading, spacing: 28) {
                Text("开始")
                    .font(AppFont.headline(size: 18))
                    .foregroundStyle(theme.ink)

                VStack(spacing: 12) {
                    WelcomeAction(icon: "plus.circle", title: "新建项目", subtitle: "在指定目录创建一套完整的博客工程") {
                        appState.sheet = .newProject
                    }
                    WelcomeAction(icon: "folder", title: "打开项目", subtitle: "从本地目录加载一个已有的 SkycBlog 站点") {
                        appState.sheet = .openProject
                    }
                }

                if !appState.recentProjects.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("最近的项目")
                            .font(AppFont.eyebrow())
                            .foregroundStyle(theme.inkSecondary)
                            .textCase(.uppercase)
                            .tracking(1.2)
                        VStack(spacing: 4) {
                            ForEach(appState.recentProjects, id: \.self) { url in
                                RecentProjectRow(url: url) { appState.openProject(at: url) }
                            }
                        }
                    }
                }

                Spacer()
            }
            .frame(maxWidth: 420)
            .padding(.horizontal, 40)
            .padding(.vertical, 40)
            .background(theme.background)
        }
    }
}

struct WelcomeAction: View {
    let icon: String
    let title: String
    let subtitle: String
    let action: () -> Void
    @Environment(\.theme) private var theme
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(theme.accent)
                    .frame(width: 32, alignment: .center)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(AppFont.headline())
                        .foregroundStyle(theme.ink)
                    Text(subtitle)
                        .font(AppFont.caption())
                        .foregroundStyle(theme.inkSecondary)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.inkTertiary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(hovered ? theme.cardHover : theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(theme.divider, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
    }
}

struct RecentProjectRow: View {
    let url: URL
    let onOpen: () -> Void
    @State private var hovered = false
    @Environment(\.theme) private var theme

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 10) {
                Image(systemName: "doc.text")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.inkTertiary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(url.lastPathComponent)
                        .font(AppFont.body())
                        .foregroundStyle(theme.ink)
                    Text(url.deletingLastPathComponent().path)
                        .font(AppFont.monoCaption())
                        .foregroundStyle(theme.inkTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(hovered ? theme.cardHover : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
    }
}

// MARK: - 工作台

struct WorkspaceView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.theme) private var theme

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } content: {
            MiddleColumnView()
                .navigationSplitViewColumnWidth(min: 280, ideal: 340, max: 480)
        } detail: {
            DetailColumnView()
                .navigationSplitViewColumnWidth(min: 480, ideal: 720)
        }
        .toolbar { WorkspaceToolbar() }
        .safeAreaInset(edge: .bottom) {
            if appState.consoleVisible {
                ConsoleView()
                    .frame(height: 200)
                    .background(theme.consoleBackground)
            }
        }
    }
}

// MARK: - 工作台工具栏

struct WorkspaceToolbar: ToolbarContent {
    @EnvironmentObject var appState: AppState

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            ProjectBadge()
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                appState.sheet = .newPost
            } label: {
                Label("写文章", systemImage: "square.and.pencil")
            }
            .help("新建文章 ⌘⇧N")
            .disabled(appState.project == nil)

            Button {
                appState.runBuild()
            } label: {
                if appState.isWorking {
                    Label("构建中…", systemImage: "ellipsis.circle")
                } else {
                    Label("构建", systemImage: "hammer")
                }
            }
            .help("构建站点 ⌘B")
            .disabled(appState.project == nil || appState.isWorking)

            Button {
                if appState.isServing { appState.stopServer() } else { appState.startServer() }
            } label: {
                Label(appState.isServing ? "停止" : "预览",
                      systemImage: appState.isServing ? "stop.circle" : "play.circle")
            }
            .help(appState.isServing ? "停止预览 ⌘⇧P" : "启动预览 ⌘P")
            .disabled(appState.project == nil)
        }
    }
}

struct ProjectBadge: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.theme) private var theme

    var body: some View {
        if let project = appState.project {
            HStack(spacing: 10) {
                Circle().fill(theme.accent).frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 0) {
                    Text(project.config.title.isEmpty ? project.root.lastPathComponent : project.config.title)
                        .font(AppFont.headline())
                        .foregroundStyle(theme.ink)
                    HStack(spacing: 8) {
                        Text("\(project.posts.count) 文章")
                        if let last = appState.lastBuild {
                            Text("·")
                            Text("上次构建 \(last.fileCount) 文件 · \(String(format: "%.1f", last.elapsed))s")
                        }
                    }
                    .font(AppFont.monoCaption())
                    .foregroundStyle(theme.inkTertiary)
                }
            }
        }
    }
}
