import SwiftUI
import SkycBlogCore

// MARK: - 各类内容列表

struct PostsListView: View {
    @EnvironmentObject var appState: AppState
    @State private var selection: Page? = nil

    var body: some View {
        Group {
            if let project = appState.project, !project.posts.isEmpty {
                List(project.posts, selection: $selection) { page in
                    PostRow(page: page)
                        .tag(page)
                }
            } else {
                ContentUnavailableView(
                    "暂无文章",
                    systemImage: "doc.text",
                    description: Text("点击工具栏的「新建文章」按钮开始写作")
                )
            }
        }
    }
}

struct PostRow: View {
    let page: Page
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(page.title)
                .font(.headline)
                .lineLimit(1)
            HStack(spacing: 8) {
                Text(DateUtil.human.string(from: page.date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !page.tags.isEmpty {
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(page.tags.map { "#\($0)" }.joined(separator: " "))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

struct PagesListView: View {
    @EnvironmentObject var appState: AppState
    var body: some View {
        if let project = appState.project {
            List(project.pages) { page in
                VStack(alignment: .leading) {
                    Text(page.title).font(.headline)
                    Text(page.url).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct DraftsListView: View {
    @EnvironmentObject var appState: AppState
    var body: some View {
        if let project = appState.project, !project.drafts.isEmpty {
            List(project.drafts) { page in
                PostRow(page: page)
            }
        } else {
            ContentUnavailableView("无草稿", systemImage: "pencil.and.outline")
        }
    }
}

struct AlbumsListView: View {
    @EnvironmentObject var appState: AppState
    var body: some View {
        if let project = appState.project, !project.albums.isEmpty {
            List(project.albums) { album in
                VStack(alignment: .leading) {
                    Text(album.title).font(.headline)
                    Text(album.url).font(.caption).foregroundStyle(.secondary)
                }
            }
        } else {
            ContentUnavailableView("无相册", systemImage: "photo.stack")
        }
    }
}

struct TagsListView: View {
    @EnvironmentObject var appState: AppState
    var body: some View {
        if let project = appState.project {
            let keys = project.allTags.keys.sorted()
            if keys.isEmpty {
                ContentUnavailableView("暂无标签", systemImage: "tag")
            } else {
                List(keys, id: \.self) { tag in
                    HStack {
                        Image(systemName: "tag")
                        Text(tag)
                        Spacer()
                        Text("\(project.allTags[tag]?.count ?? 0)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

struct CategoriesListView: View {
    @EnvironmentObject var appState: AppState
    var body: some View {
        if let project = appState.project {
            let keys = project.allCategories.keys.sorted()
            if keys.isEmpty {
                ContentUnavailableView("暂无分类", systemImage: "folder")
            } else {
                List(keys, id: \.self) { cat in
                    HStack {
                        Image(systemName: "folder")
                        Text(cat)
                        Spacer()
                        Text("\(project.allCategories[cat]?.count ?? 0)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

struct PluginsListView: View {
    @EnvironmentObject var appState: AppState
    @State private var scripts: [URL] = []

    var body: some View {
        VStack {
            if scripts.isEmpty {
                ContentUnavailableView("未找到插件脚本", systemImage: "puzzlepiece", description: Text("将 .js 脚本放入 scripts/ 目录"))
            } else {
                List(scripts, id: \.self) { url in
                    Label(url.lastPathComponent, systemImage: "doc.text")
                }
            }
        }
        .onAppear {
            if let project = appState.project {
                let dir = project.root.appendingPathComponent("scripts")
                scripts = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            }
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    var body: some View {
        Form {
            Section("项目") {
                if let project = appState.project {
                    LabeledContent("标题", value: project.config.title)
                    LabeledContent("作者", value: project.config.author.isEmpty ? "—" : project.config.author)
                    LabeledContent("语言", value: project.config.language)
                    LabeledContent("主题", value: project.config.themeName)
                    LabeledContent("输出目录", value: project.config.outputDir)
                    LabeledContent("永久链接", value: project.config.permalink)
                } else {
                    Text("未打开项目").foregroundStyle(.secondary)
                }
            }
            Section("生成") {
                if let project = appState.project {
                    Toggle("RSS", isOn: .constant(project.config.generateRSS))
                    Toggle("Sitemap", isOn: .constant(project.config.generateSitemap))
                    Toggle("搜索索引", isOn: .constant(project.config.generateSearchIndex))
                    Toggle("压缩 HTML", isOn: .constant(project.config.minifyHTML))
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - 表单

struct NewProjectSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    @State private var name: String = "my-blog"
    @State private var language: String = "zh-CN"
    @State private var location: URL = URL(fileURLWithPath: NSHomeDirectory() + "/Documents")

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("新建项目").font(.title2).bold()
            Form {
                TextField("项目名", text: $name)
                Picker("语言", selection: $language) {
                    Text("中文 (zh-CN)").tag("zh-CN")
                    Text("English (en)").tag("en")
                    Text("日本語 (ja)").tag("ja")
                }
                PathPicker(title: "位置", url: $location)
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("创建") {
                    appState.createProject(at: location, name: name, language: language)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 480, height: 360)
    }
}

struct OpenProjectSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    @State private var url: URL? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("打开项目").font(.title2).bold()
            PathPicker(title: "项目目录", url: Binding(get: { url ?? URL(fileURLWithPath: NSHomeDirectory()) },
                                                       set: { url = $0 }))
                .formStyle(.grouped)
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("打开") {
                    if let u = url { appState.openProject(at: u) }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(url == nil)
            }
        }
        .padding(20)
        .frame(width: 480, height: 280)
    }
}

struct NewPostSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    @State private var title: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("新建文章").font(.title2).bold()
            TextField("标题", text: $title)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("创建") {
                    appState.runNewPost(title: title)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(title.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420, height: 200)
    }
}

struct PathPicker: View {
    let title: String
    @Binding var url: URL
    var body: some View {
        HStack {
            TextField(title, text: .constant(url.path))
                .textFieldStyle(.roundedBorder)
                .disabled(true)
            Button("选择…") {
                let panel = NSOpenPanel()
                panel.canChooseDirectories = true
                panel.canChooseFiles = false
                panel.allowsMultipleSelection = false
                if panel.runModal() == .OK, let u = panel.url {
                    url = u
                }
            }
        }
    }
}
