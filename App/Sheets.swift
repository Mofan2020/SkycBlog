import SwiftUI
import AppKit
import SkycBlogCore

// MARK: - 新建项目

struct NewProjectSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = "my-blog"
    @State private var language: String = "zh-CN"
    @State private var parent: URL = defaultLocation()
    @State private var error: String? = nil

    static func defaultLocation() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        return docs ?? URL(fileURLWithPath: NSHomeDirectory())
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "新建项目", subtitle: "在指定目录创建一套完整的 SkycBlog 站点")

            Form {
                Section {
                    TextField("项目名", text: $name)
                    Picker("语言", selection: $language) {
                        Text("中文 (zh-CN)").tag("zh-CN")
                        Text("English (en)").tag("en")
                        Text("日本語 (ja)").tag("ja")
                    }
                } header: {
                    Text("基本信息")
                }
                Section {
                    HStack {
                        Text(parent.path)
                            .font(Theme.monoCaption)
                            .foregroundStyle(Theme.inkSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button("选择…") { pickParent() }
                    }
                } header: {
                    Text("父目录")
                } footer: {
                    Text("项目将创建为：\(parent.appendingPathComponent(name).path)")
                        .font(.caption)
                        .foregroundStyle(Theme.inkTertiary)
                }
                if let error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(Theme.error)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            SheetFooter(confirm: "创建", cancel: "取消") {
                appState.createProject(at: parent, name: name, language: language)
                dismiss()
            }
        }
        .frame(width: 520, height: 440)
        .background(Theme.cream)
    }

    private func pickParent() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let u = panel.url {
            parent = u
        }
    }
}

// MARK: - 打开项目

struct OpenProjectSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var url: URL? = nil

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "打开项目", subtitle: "选择一个已存在的 SkycBlog 站点目录")
            VStack(spacing: 16) {
                Button {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    panel.allowsMultipleSelection = false
                    if panel.runModal() == .OK, let u = panel.url {
                        url = u
                    }
                } label: {
                    HStack {
                        Image(systemName: "folder.badge.plus")
                        Text(url?.path ?? "选择目录…")
                            .lineLimit(1).truncationMode(.middle)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Theme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Theme.divider, lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)

                if !appState.recentProjects.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("最近")
                            .font(.system(.caption, design: .serif).weight(.semibold))
                            .foregroundStyle(Theme.inkSecondary)
                            .textCase(.uppercase)
                            .tracking(1.0)
                        ForEach(appState.recentProjects.prefix(5), id: \.self) { url in
                            Button {
                                appState.openProject(at: url)
                                dismiss()
                            } label: {
                                HStack {
                                    Image(systemName: "clock")
                                        .foregroundStyle(Theme.inkTertiary)
                                    Text(url.lastPathComponent)
                                        .foregroundStyle(Theme.ink)
                                    Spacer()
                                }
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(Theme.cardBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Spacer()
            }
            .padding(20)
            SheetFooter(confirm: "打开", cancel: "取消", confirmDisabled: url == nil) {
                if let u = url { appState.openProject(at: u) }
                dismiss()
            }
        }
        .frame(width: 520, height: 420)
        .background(Theme.cream)
    }
}

// MARK: - 新建文章

struct NewPostSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var title: String = ""
    @State private var isDraft: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: isDraft ? "新建草稿" : "新建文章", subtitle: isDraft ? "不会发布到生产站点" : "发布到 _posts/")

            Form {
                Section {
                    TextField("文章标题", text: $title)
                    Toggle("保存为草稿", isOn: $isDraft)
                } header: {
                    Text("标题")
                } footer: {
                    Text("文件名将自动生成为 YYYY-MM-DD-<slug>.md")
                        .font(.caption)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            SheetFooter(confirm: "创建", cancel: "取消", confirmDisabled: title.isEmpty) {
                appState.createNewPost(title: title)
                dismiss()
            }
        }
        .frame(width: 460, height: 320)
        .background(Theme.cream)
    }
}

// MARK: - 项目信息

struct ProjectInfoSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack {
            Text("项目信息").font(.title2)
            if let project = appState.project {
                Text(project.config.title)
                Text(project.root.path).font(.caption)
            }
            Button("关闭") { dismiss() }
        }
        .frame(width: 400, height: 200)
    }
}

// MARK: - 部署

struct DeploySheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack {
            Text("部署").font(.title2)
            Text("部署到 GitHub Pages / Cloudflare Pages")
            HStack {
                Button("GitHub Pages") { appState.log(.info("暂未实现")) }
                Button("Cloudflare Pages") { appState.log(.info("暂未实现")) }
                Button("关闭") { dismiss() }
            }
        }
        .frame(width: 400, height: 200)
    }
}

// MARK: - 通用 sheet 元素

struct SheetHeader: View {
    let title: String
    let subtitle: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(.title2, design: .serif).weight(.semibold))
                .foregroundStyle(Theme.ink)
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Theme.inkSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 12)
    }
}

struct SheetFooter: View {
    let confirm: String
    let cancel: String
    var confirmDisabled: Bool = false
    let onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HStack {
            Spacer()
            Button(cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button(confirm) { onConfirm() }
                .keyboardShortcut(.defaultAction)
                .disabled(confirmDisabled)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(Color.white.opacity(0.5))
    }
}

// MARK: - 偏好设置窗口

struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        TabView {
            Form {
                Section("编辑器") {
                    Toggle("默认显示预览", isOn: $appState.editor.previewVisible)
                    Toggle("默认显示控制台", isOn: $appState.consoleVisible)
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("通用", systemImage: "gearshape") }

            Form {
                Section("最近项目") {
                    if appState.recentProjects.isEmpty {
                        Text("暂无").foregroundStyle(.secondary)
                    } else {
                        ForEach(appState.recentProjects, id: \.self) { url in
                            HStack {
                                Text(url.lastPathComponent)
                                Spacer()
                                Text(url.path)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("项目", systemImage: "folder") }

            VStack {
                Text("SkycBlog 1.0.0")
                    .font(.headline)
                Text("一个安静的写作桌面。")
                    .font(.caption)
                Spacer()
            }
            .padding()
            .tabItem { Label("关于", systemImage: "info.circle") }
        }
        .frame(width: 520, height: 360)
    }
}
