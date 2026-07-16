import SwiftUI
import SkycBlogCore

/// 根视图：无项目时显示欢迎屏，有项目时显示工作台。
struct RootView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Group {
            if appState.project == nil {
                WelcomeView()
            } else {
                WorkspaceView()
            }
        }
        .background(Theme.background)
        .sheet(item: $appState.sheet) { sheet in
            switch sheet {
            case .newProject: NewProjectSheet().environmentObject(appState)
            case .openProject: OpenProjectSheet().environmentObject(appState)
            case .newPost: NewPostSheet().environmentObject(appState)
            case .projectInfo: ProjectInfoSheet().environmentObject(appState)
            case .deploy: DeploySheet().environmentObject(appState)
            }
        }
    }
}

// MARK: - 欢迎屏

struct WelcomeView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 0) {
            // 左侧品牌区
            VStack(alignment: .leading, spacing: 24) {
                Spacer()
                VStack(alignment: .leading, spacing: 16) {
                    Text("SkycBlog")
                        .font(.system(size: 48, weight: .semibold, design: .serif))
                        .foregroundStyle(Theme.ink)
                    Text("一个安静的写作桌面。\n把 Markdown 文件交给它，把静态站点收回来。")
                        .font(.system(size: 16, design: .serif))
                        .foregroundStyle(Theme.inkSecondary)
                        .lineSpacing(4)
                }
                Spacer()
                HStack(spacing: 12) {
                    Text("v1.0")
                        .font(.system(.caption, design: .monospaced))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Theme.tagBackground)
                        .clipShape(Capsule())
                    Text("macOS 15+")
                        .font(.system(.caption, design: .monospaced))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Theme.tagBackground)
                        .clipShape(Capsule())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 60)
            .background(Theme.cream)

            // 右侧操作区
            VStack(alignment: .leading, spacing: 28) {
                Text("开始")
                    .font(.system(.title3, design: .serif).weight(.semibold))
                    .foregroundStyle(Theme.ink)

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
                            .font(.system(.subheadline, design: .serif).weight(.semibold))
                            .foregroundStyle(Theme.inkSecondary)
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
            .background(Theme.background)
        }
    }
}

struct WelcomeAction: View {
    let icon: String
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 32, alignment: .center)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(.body, design: .serif).weight(.semibold))
                        .foregroundStyle(Theme.ink)
                    Text(subtitle)
                        .font(.system(.caption))
                        .foregroundStyle(Theme.inkSecondary)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.inkTertiary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Theme.divider, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}

struct RecentProjectRow: View {
    let url: URL
    let onOpen: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 10) {
                Image(systemName: "doc.text")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.inkTertiary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(url.lastPathComponent)
                        .font(.system(.body))
                        .foregroundStyle(Theme.ink)
                    Text(url.deletingLastPathComponent().path)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Theme.inkTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(hovered ? Theme.cardHover : Color.clear)
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
                    .background(Theme.consoleBackground)
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

    var body: some View {
        if let project = appState.project {
            HStack(spacing: 10) {
                Circle().fill(Theme.accent).frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 0) {
                    Text(project.config.title.isEmpty ? project.root.lastPathComponent : project.config.title)
                        .font(.system(.body, design: .serif).weight(.semibold))
                        .foregroundStyle(Theme.ink)
                    HStack(spacing: 8) {
                        Text("\(project.posts.count) 文章")
                        if let last = appState.lastBuild {
                            Text("·")
                            Text("上次构建 \(last.fileCount) 文件 · \(String(format: "%.1f", last.elapsed))s")
                        }
                    }
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Theme.inkTertiary)
                }
            }
        }
    }
}
