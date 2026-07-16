import SwiftUI
import SkycBlogCore
import AppKit
import UniformTypeIdentifiers

// MARK: - 通用编辑 Sheet

/// 编辑文章的元数据：标题、标签、分类、草稿状态。
struct PageMetadataSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme

    let page: Page

    @State private var title: String = ""
    @State private var tagsText: String = ""        // 逗号分隔
    @State private var categoriesText: String = "" // 逗号分隔
    @State private var isDraft: Bool = false
    @State private var newTag: String = ""
    @State private var newCategory: String = ""

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "编辑元数据", subtitle: page.url)

            Form {
                Section("基本信息") {
                    TextField("标题", text: $title)
                    Toggle("保存为草稿", isOn: $isDraft)
                }
                Section("标签") {
                    if !tags.isEmpty {
                        FlowChips(items: tags, accent: theme.accent) { tag in
                            removeTag(tag)
                        }
                    }
                    HStack {
                        TextField("添加标签", text: $newTag)
                            .onSubmit { addTag() }
                        Button("添加") { addTag() }
                            .disabled(newTag.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    Text("用逗号分隔多个标签：\(tagsText)")
                        .font(AppFont.caption())
                        .foregroundStyle(theme.inkTertiary)
                }
                Section("分类") {
                    if !categories.isEmpty {
                        FlowChips(items: categories, accent: theme.success) { cat in
                            removeCategory(cat)
                        }
                    }
                    HStack {
                        TextField("添加分类", text: $newCategory)
                            .onSubmit { addCategory() }
                        Button("添加") { addCategory() }
                            .disabled(newCategory.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            SheetFooter(confirm: "保存", cancel: "取消", confirmDisabled: title.isEmpty) {
                appState.updatePageMetadata(page,
                                            title: title,
                                            tags: tags,
                                            categories: categories,
                                            draft: isDraft)
                dismiss()
            }
        }
        .frame(width: 540, height: 480)
        .background(theme.background)
        .onAppear(perform: load)
    }

    private var tags: [String] { parseList(tagsText) }
    private var categories: [String] { parseList(categoriesText) }

    private func parseList(_ s: String) -> [String] {
        s.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private func load() {
        title = page.title
        tagsText = page.tags.joined(separator: ", ")
        categoriesText = page.categories.joined(separator: ", ")
        isDraft = page.kind == .draft
    }

    private func addTag() {
        let v = newTag.trimmingCharacters(in: .whitespaces)
        guard !v.isEmpty else { return }
        if !tags.contains(v) {
            var merged: [String] = tags
            merged.append(v)
            let safe: [String] = merged.map { $0.replacingOccurrences(of: ",", with: " ") }
            tagsText = safe.joined(separator: ", ")
        }
        newTag = ""
    }
    private func removeTag(_ t: String) {
        tagsText = tags.filter { $0 != t }.joined(separator: ", ")
    }
    private func addCategory() {
        let v = newCategory.trimmingCharacters(in: .whitespaces)
        guard !v.isEmpty else { return }
        if !categories.contains(v) {
            let merged = categories + [v]
            categoriesText = merged.joined(separator: ", ")
        }
        newCategory = ""
    }
    private func removeCategory(_ c: String) {
        categoriesText = categories.filter { $0 != c }.joined(separator: ", ")
    }
}

/// 标签/分类芯片
struct FlowChips: View {
    let items: [String]
    let accent: Color
    let onRemove: (String) -> Void
    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(items, id: \.self) { item in
                HStack(spacing: 4) {
                    Text(item).font(AppFont.caption())
                    Button {
                        onRemove(item)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(accent.opacity(0.15))
                .clipShape(Capsule())
            }
        }
    }
}

/// 简单 Flow 布局（SwiftUI 自带 Layout 协议）
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let lines = layoutLines(in: maxWidth, subviews: subviews)
        let height = lines.reduce(0) { $0 + $1.height + spacing } - (lines.isEmpty ? 0 : spacing)
        return CGSize(width: maxWidth, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        let lines = layoutLines(in: maxWidth, subviews: subviews)
        var y = bounds.minY
        for line in lines {
            var x = bounds.minX
            for item in line.items {
                let size = subviews[item.index].sizeThatFits(.unspecified)
                subviews[item.index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += line.height + spacing
        }
    }

    private struct LineItem { var index: Int; var width: CGFloat }
    private struct Line { var items: [LineItem]; var height: CGFloat }

    private func layoutLines(in maxWidth: CGFloat, subviews: Subviews) -> [Line] {
        var lines: [Line] = []
        var current = Line(items: [], height: 0)
        var x: CGFloat = 0
        for i in subviews.indices {
            let size = subviews[i].sizeThatFits(.unspecified)
            if x + size.width > maxWidth && !current.items.isEmpty {
                lines.append(current)
                current = Line(items: [], height: 0)
                x = 0
            }
            current.items.append(LineItem(index: i, width: size.width))
            current.height = max(current.height, size.height)
            x += size.width + spacing
        }
        if !current.items.isEmpty { lines.append(current) }
        return lines
    }
}

// MARK: - 文章重命名

struct RenamePageSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme

    let page: Page
    @State private var title: String = ""

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "重命名", subtitle: "将同步修改文件名与 front matter 的 title")
            Form {
                Section {
                    TextField("新标题", text: $title)
                } footer: {
                    Text("原文件：\(((page.sourcePath as NSString).lastPathComponent))")
                        .font(AppFont.monoCaption())
                        .foregroundStyle(theme.inkTertiary)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            SheetFooter(confirm: "重命名", cancel: "取消", confirmDisabled: title.isEmpty) {
                appState.renamePage(page, to: title)
                dismiss()
            }
        }
        .frame(width: 460, height: 280)
        .background(theme.background)
        .onAppear { title = page.title }
    }
}

// MARK: - 相册管理

struct NewAlbumSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @State private var title: String = ""

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "新建相册", subtitle: "在 content/albums/ 下创建")
            Form {
                Section {
                    TextField("相册名", text: $title)
                } footer: {
                    Text("目录名会自动转为英文 slug。")
                        .font(AppFont.caption())
                        .foregroundStyle(theme.inkTertiary)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            SheetFooter(confirm: "创建", cancel: "取消", confirmDisabled: title.isEmpty) {
                appState.createAlbum(title: title)
                dismiss()
            }
        }
        .frame(width: 460, height: 240)
        .background(theme.background)
    }
}

struct RenameAlbumSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    let album: Page
    @State private var title: String = ""
    @State private var oldName: String = ""

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "重命名相册", subtitle: album.title)
            Form {
                Section {
                    TextField("新相册名", text: $title)
                } footer: {
                    Text("目录 slug 将重新生成。")
                        .font(AppFont.caption())
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            SheetFooter(confirm: "重命名", cancel: "取消", confirmDisabled: title.isEmpty) {
                appState.renameAlbum(oldName: oldName, newTitle: title)
                dismiss()
            }
        }
        .frame(width: 460, height: 240)
        .background(theme.background)
        .onAppear {
            title = album.title
            oldName = (album.sourcePath as NSString).deletingLastPathComponent
                .components(separatedBy: "/").last ?? album.title
        }
    }
}

// MARK: - 相册详情

struct AlbumDetailView: View {
    let album: Page
    @EnvironmentObject var appState: AppState
    @Environment(\.theme) private var theme
    @State private var media: [AlbumManager.MediaInfo] = []
    @State private var search: String = ""
    @State private var selectedMedia: String? = nil
    @State private var showAddSheet: Bool = false
    @State private var renameTarget: String? = nil
    @State private var renameValue: String = ""
    @State private var albumName: String = ""

    var filtered: [AlbumManager.MediaInfo] {
        guard !search.isEmpty else { return media }
        return media.filter { $0.filename.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(album.title)
                        .font(AppFont.title(size: 18))
                        .foregroundStyle(theme.ink)
                    Text(album.url)
                        .font(AppFont.monoCaption())
                        .foregroundStyle(theme.inkTertiary)
                }
                Spacer()
                Button {
                    showAddSheet = true
                } label: {
                    Label("添加", systemImage: "plus")
                }
                Button {
                    appState.renameAlbumTarget = album
                } label: {
                    Label("重命名", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    appState.deleteAlbum(name: albumName)
                } label: {
                    Label("删除", systemImage: "trash")
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(theme.background)
            .overlay(Rectangle().fill(theme.divider).frame(height: 0.5), alignment: .bottom)

            // 工具栏：搜索
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(theme.inkTertiary)
                TextField("搜索文件名…", text: $search)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(theme.cardBackground)

            if media.isEmpty {
                EmptyState(icon: "photo.stack", text: "相册为空,点击 + 添加图片或视频")
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 12)], spacing: 12) {
                        ForEach(filtered, id: \.filename) { item in
                            mediaCell(for: item)
                        }
                    }
                    .padding(16)
                }
            }
        }
        .onAppear { reload() }
        .onChange(of: appState.project?.albums.count) { _, _ in reload() }
        .fileImporter(
            isPresented: $showAddSheet,
            allowedContentTypes: [.image, .movie, .png, .jpeg, .heic, .gif, .mp3, .mpeg4Movie, .quickTimeMovie],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                appState.addMedia(albumName: albumName, sourceURLs: urls)
                reload()
            }
        }
        .sheet(item: Binding(
            get: { renameTarget.map { RenameTarget(filename: $0) } },
            set: { renameTarget = $0?.filename }
        )) { target in
            RenameMediaSheet(albumName: albumName, oldName: target.filename) { newName in
                if newName != target.filename {
                    appState.renameMedia(albumName: albumName, oldName: target.filename, newName: newName)
                }
                renameTarget = nil
                reload()
            }
        }
    }

    @ViewBuilder
    private func mediaCell(for item: AlbumManager.MediaInfo) -> some View {
        let dir = AlbumManager.albumDir(projectRoot: appState.project?.root.path ?? "", albumName: albumName)
        let fullPath: String = (dir as NSString).appendingPathComponent(item.filename)
        let isSelected: Bool = (selectedMedia == item.filename)
        MediaThumbView(
            item: item,
            isSelected: isSelected,
            onDelete: { handleDelete(filename: item.filename) },
            onRename: { handleRename(filename: item.filename) },
            fullPath: fullPath
        )
        .onTapGesture {
            selectedMedia = item.filename
        }
    }

    private func handleDelete(filename: String) {
        appState.removeMedia(albumName: albumName, filename: filename)
        reload()
    }

    private func handleRename(filename: String) {
        renameTarget = filename
        renameValue = filename
    }

    private func reload() {
        // 从 album.sourcePath 提取相册名
        let dir = (album.sourcePath as NSString).deletingLastPathComponent
        albumName = (dir as NSString).lastPathComponent
        media = appState.albumMediaList(name: albumName)
    }
}

struct RenameTarget: Identifiable {
    let filename: String
    var id: String { filename }
}

struct RenameMediaSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    let albumName: String
    let oldName: String
    let onSave: (String) -> Void
    @State private var newName: String = ""

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "重命名", subtitle: albumName)
            Form {
                Section {
                    TextField("新文件名", text: $newName)
                } footer: {
                    Text("原文件名：\(oldName)")
                        .font(AppFont.monoCaption())
                        .foregroundStyle(theme.inkTertiary)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            SheetFooter(confirm: "保存", cancel: "取消", confirmDisabled: newName.isEmpty) {
                onSave(newName)
                dismiss()
            }
        }
        .frame(width: 460, height: 240)
        .background(theme.background)
        .onAppear { newName = oldName }
    }
}

struct MediaThumbView: View {
    let item: AlbumManager.MediaInfo
    let isSelected: Bool
    let onDelete: () -> Void
    let onRename: () -> Void
    let fullPath: String    // 绝对路径,用于加载图片
    @Environment(\.theme) private var theme
    @State private var hovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(theme.cardBackground)
                if item.isImage, let img = NSImage(contentsOfFile: fullPath) {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else if item.isVideo {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.black.opacity(0.4))
                        Image(systemName: "play.rectangle.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(.white)
                    }
                } else {
                    Image(systemName: "doc")
                        .font(.system(size: 32))
                        .foregroundStyle(theme.inkTertiary)
                }
            }
            .frame(height: 110)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(isSelected ? theme.accent : Color.clear, lineWidth: 2)
            )
            Text(item.filename)
                .font(AppFont.caption())
                .foregroundStyle(theme.inkSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(byteFormat(item.size))
                .font(AppFont.monoCaption(size: 10))
                .foregroundStyle(theme.inkTertiary)
        }
        .contextMenu {
            Button("重命名") { onRename() }
            Button("删除", role: .destructive) { onDelete() }
        }
        .scaleEffect(hovered ? 1.02 : 1.0)
        .animation(.easeOut(duration: 0.1), value: hovered)
        .onHover { hovered = $0 }
    }

    private func byteFormat(_ bytes: Int64) -> String {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useKB, .useMB, .useGB]
        f.countStyle = .file
        return f.string(fromByteCount: bytes)
    }
}

// 为 MediaThumbView 提供访问 AppState 的兜底（用 shared 单例）
// (不再需要：fullPath 已直接传入)

// MARK: - 插件开关

struct PluginListView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.theme) private var theme
    @State private var plugins: [PluginInfo] = []

    var body: some View {
        VStack(spacing: 0) {
            ListHeader(title: "插件", subtitle: "scripts/*.js  ·  关闭后不会被构建加载",
                       icon: "puzzlepiece",
                       trailing: AnyView(EmptyView()))
            if plugins.isEmpty {
                EmptyState(icon: "puzzlepiece", text: "将 .js 脚本放入 scripts/ 目录")
            } else {
                List(plugins) { plugin in
                    HStack {
                        Image(systemName: "curlybraces")
                            .foregroundStyle(theme.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(plugin.name)
                                .font(AppFont.body())
                                .foregroundStyle(theme.ink)
                            Text(plugin.path)
                                .font(AppFont.monoCaption())
                                .foregroundStyle(theme.inkTertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { plugin.enabled },
                            set: { appState.setPluginEnabled(name: plugin.name, enabled: $0); reload() }
                        ))
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .labelsHidden()
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .onAppear(perform: reload)
        .onChange(of: appState.project?.config.disabledPlugins) { _, _ in reload() }
    }

    private func reload() {
        plugins = appState.listPlugins()
    }
}

// MARK: - 分类/标签管理

struct TagManagerView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.theme) private var theme
    @State private var newTag: String = ""

    var body: some View {
        VStack(spacing: 0) {
            ListHeader(title: "标签", subtitle: "出现在文章 front matter 中的所有标签",
                       icon: "tag",
                       trailing: AnyView(EmptyView()))
            HStack {
                TextField("新建标签", text: $newTag)
                    .onSubmit { addTag() }
                Button("添加") { addTag() }
                    .disabled(newTag.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(12)
            if let project = appState.project, !project.allTags.isEmpty {
                List(Array(project.allTags.keys).sorted(), id: \.self) { tag in
                    HStack {
                        Text("#\(tag)")
                            .font(AppFont.body())
                            .foregroundStyle(theme.ink)
                        Spacer()
                        Text("\(project.allTags[tag]?.count ?? 0) 篇")
                            .font(AppFont.monoCaption())
                            .foregroundStyle(theme.inkTertiary)
                    }
                }
            } else {
                EmptyState(icon: "tag", text: "暂无标签")
            }
        }
    }

    private func addTag() {
        let v = newTag.trimmingCharacters(in: .whitespaces)
        guard !v.isEmpty else { return }
        appState.addTag(v)
        newTag = ""
    }
}

struct CategoryManagerView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.theme) private var theme
    @State private var newCategory: String = ""

    var body: some View {
        VStack(spacing: 0) {
            ListHeader(title: "分类", subtitle: "出现在文章 front matter 中的所有分类",
                       icon: "folder",
                       trailing: AnyView(EmptyView()))
            HStack {
                TextField("新建分类", text: $newCategory)
                    .onSubmit { addCategory() }
                Button("添加") { addCategory() }
                    .disabled(newCategory.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(12)
            if let project = appState.project, !project.allCategories.isEmpty {
                List(Array(project.allCategories.keys).sorted(), id: \.self) { cat in
                    HStack {
                        Image(systemName: "folder")
                            .foregroundStyle(theme.inkSecondary)
                        Text(cat)
                            .font(AppFont.body())
                            .foregroundStyle(theme.ink)
                        Spacer()
                        Text("\(project.allCategories[cat]?.count ?? 0) 篇")
                            .font(AppFont.monoCaption())
                            .foregroundStyle(theme.inkTertiary)
                    }
                }
            } else {
                EmptyState(icon: "folder", text: "暂无分类")
            }
        }
    }

    private func addCategory() {
        let v = newCategory.trimmingCharacters(in: .whitespaces)
        guard !v.isEmpty else { return }
        appState.addTag(v)  // 同样行为
        newCategory = ""
    }
}
