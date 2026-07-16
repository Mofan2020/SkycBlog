import SwiftUI
import AppKit
import SkycBlogCore

// MARK: - 新建项目

struct NewProjectSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme

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
                            .font(AppFont.monoCaption())
                            .foregroundStyle(theme.inkSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button("选择…") { pickParent() }
                    }
                } header: {
                    Text("父目录")
                } footer: {
                    Text("项目将创建为：\(parent.appendingPathComponent(name).path)")
                        .font(AppFont.caption())
                        .foregroundStyle(theme.inkTertiary)
                }
                if let error {
                    Text(error)
                        .font(AppFont.caption())
                        .foregroundStyle(theme.errorColor)
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
        .background(theme.background)
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
    @Environment(\.theme) private var theme
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
                            .foregroundStyle(theme.accent)
                        Text(url?.path ?? "选择目录…")
                            .font(AppFont.body())
                            .foregroundStyle(theme.ink)
                            .lineLimit(1).truncationMode(.middle)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(theme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(theme.divider, lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)

                if !appState.recentProjects.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("最近")
                            .font(AppFont.eyebrow())
                            .foregroundStyle(theme.inkSecondary)
                            .textCase(.uppercase)
                            .tracking(1.0)
                        ForEach(appState.recentProjects.prefix(5), id: \.self) { url in
                            Button {
                                appState.openProject(at: url)
                                dismiss()
                            } label: {
                                HStack {
                                    Image(systemName: "clock")
                                        .foregroundStyle(theme.inkTertiary)
                                    Text(url.lastPathComponent)
                                        .font(AppFont.body())
                                        .foregroundStyle(theme.ink)
                                    Spacer()
                                }
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(theme.cardBackground)
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
        .background(theme.background)
    }
}

// MARK: - 新建文章

struct NewPostSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
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
                        .font(AppFont.caption())
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
        .background(theme.background)
    }
}

// MARK: - 项目信息

struct ProjectInfoSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    var body: some View {
        VStack(spacing: 16) {
            Text("项目信息")
                .font(AppFont.title())
                .foregroundStyle(theme.ink)
            if let project = appState.project {
                Text(project.config.title)
                    .font(AppFont.body())
                    .foregroundStyle(theme.ink)
                Text(project.root.path)
                    .font(AppFont.monoCaption())
                    .foregroundStyle(theme.inkSecondary)
            }
            Spacer()
            Button("关闭") { dismiss() }
                .controlSize(.regular)
        }
        .padding(24)
        .frame(width: 400, height: 200)
        .background(theme.background)
    }
}

// MARK: - 部署

struct DeploySheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    var body: some View {
        VStack(spacing: 16) {
            Text("部署")
                .font(AppFont.title())
                .foregroundStyle(theme.ink)
            Text("部署到 GitHub Pages / Cloudflare Pages")
                .font(AppFont.body())
                .foregroundStyle(theme.inkSecondary)
            HStack {
                Button("GitHub Pages") { appState.log(.info("暂未实现")) }
                    .controlSize(.regular)
                Button("Cloudflare Pages") { appState.log(.info("暂未实现")) }
                    .controlSize(.regular)
                Button("关闭") { dismiss() }
                    .controlSize(.regular)
            }
            Spacer()
        }
        .padding(24)
        .frame(width: 400, height: 200)
        .background(theme.background)
    }
}

// MARK: - 通用 sheet 元素

struct SheetHeader: View {
    @Environment(\.theme) private var theme
    let title: String
    let subtitle: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(AppFont.title())
                .foregroundStyle(theme.ink)
            if let subtitle {
                Text(subtitle)
                    .font(AppFont.caption())
                    .foregroundStyle(theme.inkSecondary)
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
    @Environment(\.theme) private var theme

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
        .background(theme.surface)
    }
}

// MARK: - 偏好设置窗口

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.theme) private var theme

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
                        Text("暂无")
                            .font(AppFont.body())
                            .foregroundStyle(theme.inkSecondary)
                    } else {
                        ForEach(appState.recentProjects, id: \.self) { url in
                            HStack {
                                Text(url.lastPathComponent)
                                    .font(AppFont.body())
                                    .foregroundStyle(theme.ink)
                                Spacer()
                                Text(url.path)
                                    .font(AppFont.monoCaption())
                                    .foregroundStyle(theme.inkSecondary)
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
                    .font(AppFont.title())
                    .foregroundStyle(theme.ink)
                Text("一个安静的写作桌面。")
                    .font(AppFont.body())
                    .foregroundStyle(theme.inkSecondary)
                Spacer()
            }
            .padding()
            .tabItem { Label("关于", systemImage: "info.circle") }
        }
        .frame(width: 520, height: 360)
        .background(theme.background)
    }
}
