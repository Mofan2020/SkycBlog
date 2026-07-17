import SwiftUI
import SkycBlogCore
import AppKit
import UniformTypeIdentifiers

// MARK: - 通用: 新建标签/分类 sheet

struct AddTaxonomySheet: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    let kind: String
    @Binding var name: String
    let onCreate: (String) -> Void
    @State private var error: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "新建\(kind)", subtitle: "在 _system 草稿里创建, 可在文章上调整")
            Divider().background(theme.divider)
            VStack(alignment: .leading, spacing: 10) {
                Text("名称").font(AppFont.eyebrow()).foregroundStyle(theme.inkSecondary)
                TextField("如: \(kind == "标签" ? "Swift" : "技术")", text: $name)
                    .textFieldStyle(.roundedBorder)
                if let error = error {
                    Text(error).font(AppFont.caption()).foregroundStyle(.red)
                }
                Text("会立即出现在左侧 \(kind) 列表里")
                    .font(AppFont.monoCaption())
                    .foregroundStyle(theme.inkTertiary)
            }
            .padding(20)
            Divider().background(theme.divider)
            SheetFooter(confirm: "创建", cancel: "取消", onConfirm: doCreate)
        }
        .frame(width: 440, height: 240)
    }

    private func doCreate() {
        let v = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !v.isEmpty else { error = "请输入名称"; return }
        onCreate(v)
        dismiss()
    }
}

// MARK: - 文章元数据编辑

/// 编辑单篇文章的标题/标签/分类/草稿状态。Tags 与 Categories 都支持输入即时添加、点击 chip 删除。
struct PageMetadataSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    let page: Page

    @State private var title: String = ""
    @State private var tagsText: String = ""
    @State private var categoriesText: String = ""
    @State private var draft: Bool = false
    @State private var newTag: String = ""
    @State private var newCategory: String = ""

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "编辑元数据", subtitle: page.title)
            Divider().background(theme.divider)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    fieldLabel("标题")
                    TextField("标题", text: $title)
                        .textFieldStyle(.roundedBorder)

                    fieldLabel("标签 (tags)")
                    chipEditor(items: parsedTags, new: $newTag, placeholder: "添加标签后回车", add: addTag, remove: removeTag)
                    Text("在每篇 markdown 的 front matter 里以 `tags: [a, b]` 存储")
                        .font(AppFont.caption())
                        .foregroundStyle(theme.inkTertiary)

                    fieldLabel("分类 (categories)")
                    chipEditor(items: parsedCategories, new: $newCategory, placeholder: "添加分类后回车", add: addCategory, remove: removeCategory)
                    Text("在每篇 markdown 的 front matter 里以 `categories: [a, b]` 存储")
                        .font(AppFont.caption())
                        .foregroundStyle(theme.inkTertiary)

                    Toggle("草稿", isOn: $draft)
                        .toggleStyle(.switch)
                }
                .padding(20)
            }
            Divider().background(theme.divider)
            SheetFooter(confirm: "保存", cancel: "取消", onConfirm: save)
        }
        .frame(width: 540, height: 520)
        .onAppear { hydrate() }
    }

    private func fieldLabel(_ s: String) -> some View {
        Text(s).font(AppFont.eyebrow()).foregroundStyle(theme.inkSecondary)
    }

    private var parsedTags: [String] {
        tagsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
    private var parsedCategories: [String] {
        categoriesText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private func addTag() {
        let v = newTag.trimmingCharacters(in: .whitespaces)
        guard !v.isEmpty else { return }
        var list = parsedTags
        if !list.contains(v) { list.append(v) }
        tagsText = list.joined(separator: ", ")
        newTag = ""
    }
    private func removeTag(_ t: String) {
        tagsText = parsedTags.filter { $0 != t }.joined(separator: ", ")
    }
    private func addCategory() {
        let v = newCategory.trimmingCharacters(in: .whitespaces)
        guard !v.isEmpty else { return }
        var list = parsedCategories
        if !list.contains(v) { list.append(v) }
        categoriesText = list.joined(separator: ", ")
        newCategory = ""
    }
    private func removeCategory(_ c: String) {
        categoriesText = parsedCategories.filter { $0 != c }.joined(separator: ", ")
    }

    private func hydrate() {
        title = page.title
        tagsText = page.tags.joined(separator: ", ")
        categoriesText = page.categories.joined(separator: ", ")
        draft = page.draft
    }

    private func save() {
        let newTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let tags = parsedTags
        let cats = parsedCategories
        appState.updatePageMetadata(page,
                                    title: newTitle.isEmpty ? nil : newTitle,
                                    tags: tags,
                                    categories: cats,
                                    draft: draft)
        dismiss()
    }

    @ViewBuilder
    private func chipEditor(items: [String], new: Binding<String>, placeholder: String, add: @escaping () -> Void, remove: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // 已存在的 chip
            if items.isEmpty {
                Text("暂无")
                    .font(AppFont.caption())
                    .foregroundStyle(theme.inkTertiary)
            } else {
                FlowChips(items: items) { item in remove(item) }
            }
            HStack(spacing: 6) {
                TextField(placeholder, text: new)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { add() }
                Button("添加") { add() }
                    .buttonStyle(.bordered)
                    .disabled(new.wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }
}

// MARK: - 文章重命名

struct RenamePageSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    let page: Page
    @State private var newTitle: String = ""

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "重命名文章", subtitle: "日期前缀会自动保留")
            Divider().background(theme.divider)
            VStack(alignment: .leading, spacing: 12) {
                Text("新标题").font(AppFont.eyebrow()).foregroundStyle(theme.inkSecondary)
                TextField("新标题", text: $newTitle)
                    .textFieldStyle(.roundedBorder)
                Text("当前：\((page.sourcePath as NSString).lastPathComponent)")
                    .font(AppFont.monoCaption())
                    .foregroundStyle(theme.inkTertiary)
            }
            .padding(20)
            Divider().background(theme.divider)
            SheetFooter(confirm: "重命名", cancel: "取消", onConfirm: {
                let v = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !v.isEmpty, v != page.title else { dismiss(); return }
                appState.renamePage(page, to: v)
                dismiss()
            })
        }
        .frame(width: 440, height: 240)
        .onAppear { newTitle = page.title }
    }
}

// MARK: - 新建相册

struct NewAlbumSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var error: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "新建相册", subtitle: "相簿名字, 用 slug 作为目录名")
            Divider().background(theme.divider)
            VStack(alignment: .leading, spacing: 12) {
                Text("名称").font(AppFont.eyebrow()).foregroundStyle(theme.inkSecondary)
                TextField("如: 我的旅行 / Travel 2026", text: $name)
                    .textFieldStyle(.roundedBorder)
                if let error = error {
                    Text(error).font(AppFont.caption()).foregroundStyle(.red)
                }
                Text("会自动创建 `content/albums/<slug>/index.md`")
                    .font(AppFont.monoCaption())
                    .foregroundStyle(theme.inkTertiary)
            }
            .padding(20)
            Divider().background(theme.divider)
            SheetFooter(confirm: "创建", cancel: "取消", onConfirm: create)
        }
        .frame(width: 460, height: 240)
    }

    private func create() {
        let v = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !v.isEmpty else { error = "请输入名称"; return }
        appState.createAlbum(title: v)
        dismiss()
    }
}

// MARK: - 重命名相册

struct RenameAlbumSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    let album: Page
    @State private var newName: String = ""
    @State private var error: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "重命名相册", subtitle: album.title)
            Divider().background(theme.divider)
            VStack(alignment: .leading, spacing: 12) {
                Text("新名称").font(AppFont.eyebrow()).foregroundStyle(theme.inkSecondary)
                TextField("新名称", text: $newName)
                    .textFieldStyle(.roundedBorder)
                if let error = error {
                    Text(error).font(AppFont.caption()).foregroundStyle(.red)
                }
            }
            .padding(20)
            Divider().background(theme.divider)
            SheetFooter(confirm: "重命名", cancel: "取消", onConfirm: doRename)
        }
        .frame(width: 460, height: 220)
        .onAppear { newName = album.title }
    }

    private func doRename() {
        let v = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !v.isEmpty else { error = "请输入名称"; return }
        // album.sourcePath = /.../content/albums/<slug>/index.md
        let oldSlug = (album.sourcePath as NSString).deletingLastPathComponent.components(separatedBy: "/").last ?? ""
        appState.renameAlbum(oldName: oldSlug, newTitle: v)
        dismiss()
    }
}

// MARK: - 重命名媒体文件

struct RenameMediaSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    let albumName: String
    let oldName: String
    let onDone: (String) -> Void
    @State private var newName: String = ""
    @State private var error: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "重命名文件", subtitle: oldName)
            Divider().background(theme.divider)
            VStack(alignment: .leading, spacing: 12) {
                Text("新文件名").font(AppFont.eyebrow()).foregroundStyle(theme.inkSecondary)
                TextField("新文件名", text: $newName)
                    .textFieldStyle(.roundedBorder)
                if let error = error {
                    Text(error).font(AppFont.caption()).foregroundStyle(.red)
                }
                Text("扩展名会自动保留（可手动改）")
                    .font(AppFont.monoCaption())
                    .foregroundStyle(theme.inkTertiary)
            }
            .padding(20)
            Divider().background(theme.divider)
            SheetFooter(confirm: "重命名", cancel: "取消", onConfirm: doRename)
        }
        .frame(width: 460, height: 240)
        .onAppear {
            newName = oldName
        }
    }

    private func doRename() {
        let v = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !v.isEmpty else { error = "请输入名称"; return }
        onDone(v)
        dismiss()
    }
}

// MARK: - 相册详情 (网格视图)

struct AlbumDetailView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    let album: Page

    @State private var media: [AlbumManager.MediaInfo] = []
    @State private var search: String = ""
    @State private var selectedMedia: String? = nil
    @State private var showAddSheet: Bool = false
    @State private var renameTarget: String? = nil
    @State private var renameValue: String = ""
    @State private var confirmDelete: String? = nil
    @State private var showRenameAlbum: Bool = false
    @State private var showDeleteAlbum: Bool = false

    private var albumName: String {
        (album.sourcePath as NSString).deletingLastPathComponent.components(separatedBy: "/").last ?? ""
    }

    private var filtered: [AlbumManager.MediaInfo] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty { return media }
        return media.filter { $0.filename.lowercased().contains(q) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // 顶部条
            HStack(spacing: 10) {
                Image(systemName: "photo.stack").foregroundStyle(theme.accent)
                Text(album.title.isEmpty ? albumName : album.title)
                    .font(AppFont.headline()).foregroundStyle(theme.ink)
                    .lineLimit(1)
                Text("· \(media.count) 项")
                    .font(AppFont.caption()).foregroundStyle(theme.inkTertiary)
                Spacer()
                TextField("搜索文件名…", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
                Button {
                    showAddSheet = true
                } label: {
                    Label("添加", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                Menu {
                    Button("重命名相簿") { showRenameAlbum = true }
                    Divider()
                    Button(role: .destructive) {
                        showDeleteAlbum = true
                    } label: { Text("删除相簿 (含所有媒体)") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                // 关闭按钮 (除 esc / 点外面外, 也有一个显式按钮)
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(theme.inkTertiary)
                        .font(.system(size: 18))
                }
                .buttonStyle(.plain)
                .help("关闭 (Esc)")
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            Divider().background(theme.divider)

            if filtered.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: media.isEmpty ? "photo.stack" : "magnifyingglass")
                        .font(.system(size: 36))
                        .foregroundStyle(theme.inkTertiary)
                    Text(media.isEmpty ? "相簿为空,点击 + 添加图片或视频" : "无匹配项")
                        .font(AppFont.caption()).foregroundStyle(theme.inkTertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 12)], spacing: 12) {
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
        .sheet(isPresented: $showRenameAlbum) {
            RenameAlbumSheet(album: album)
        }
        .confirmationDialog("确认删除相簿?",
                             isPresented: $showDeleteAlbum,
                             titleVisibility: .visible) {
            Button("删除相簿 (含 \(media.count) 个文件)", role: .destructive) {
                appState.deleteAlbum(name: albumName)
            }
            Button("取消", role: .cancel) { }
        } message: {
            Text("此操作不可撤销:\n\(albumName)")
        }
    }

    @ViewBuilder
    private func mediaCell(for item: AlbumManager.MediaInfo) -> some View {
        let dir = AlbumManager.albumDir(projectRoot: appState.project?.root.path ?? "", albumName: albumName)
        let fullPath: String = (dir as NSString).appendingPathComponent(item.filename)
        let isSelected: Bool = (selectedMedia == item.filename)
        VStack(spacing: 0) {
            MediaThumbView(
                item: item,
                isSelected: isSelected,
                onDelete: { confirmDelete = item.filename },
                onRename: {
                    renameTarget = item.filename
                    renameValue = item.filename
                },
                fullPath: fullPath
            )
            .onTapGesture { selectedMedia = item.filename }
            Text(item.filename)
                .font(AppFont.caption())
                .foregroundStyle(theme.inkSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 6).padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isSelected ? theme.accent : theme.divider, lineWidth: isSelected ? 1.5 : 0.5)
        )
        .alert("确认删除?", isPresented: Binding(
            get: { confirmDelete == item.filename },
            set: { if !$0 { confirmDelete = nil } }
        )) {
            Button("删除", role: .destructive) {
                appState.removeMedia(albumName: albumName, filename: item.filename)
                reload()
                confirmDelete = nil
            }
            Button("取消", role: .cancel) { confirmDelete = nil }
        } message: {
            Text(item.filename)
        }
    }

    private func reload() {
        let dir = (album.sourcePath as NSString).deletingLastPathComponent
        let name = (dir as NSString).lastPathComponent
        media = appState.albumMediaList(name: name)
    }
}

private struct RenameTarget: Identifiable, Equatable {
    let filename: String
    var id: String { filename }
}

// MARK: - 媒体缩略图 (hover 出按钮)

struct MediaThumbView: View {
    @Environment(\.theme) private var theme
    let item: AlbumManager.MediaInfo
    let isSelected: Bool
    let onDelete: () -> Void
    let onRename: () -> Void
    let fullPath: String
    @State private var hovered: Bool = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ZStack {
                Rectangle()
                    .fill(theme.surface)
                    .frame(height: 110)
                if item.isImage {
                    if let img = NSImage(contentsOfFile: fullPath) {
                        Image(nsImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 110)
                            .clipped()
                    } else {
                        Image(systemName: "photo")
                            .font(.system(size: 28))
                            .foregroundStyle(theme.inkTertiary)
                    }
                } else if item.isVideo {
                    ZStack {
                        Rectangle().fill(Color.black.opacity(0.06))
                        VStack(spacing: 4) {
                            Image(systemName: "play.rectangle.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(theme.accent)
                            Text((item.filename as NSString).pathExtension.uppercased())
                                .font(AppFont.monoCaption())
                                .foregroundStyle(theme.inkSecondary)
                        }
                    }
                    .frame(height: 110)
                } else {
                    VStack {
                        Image(systemName: "doc")
                            .font(.system(size: 28))
                            .foregroundStyle(theme.inkTertiary)
                        Text((item.filename as NSString).pathExtension)
                            .font(AppFont.monoCaption())
                            .foregroundStyle(theme.inkTertiary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 110)
            .clipped()

            if hovered {
                HStack(spacing: 4) {
                    Button(action: onRename) {
                        Image(systemName: "pencil")
                            .font(.system(size: 11, weight: .semibold))
                            .padding(4)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("重命名")
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 11, weight: .semibold))
                            .padding(4)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("删除")
                }
                .padding(6)
            }
        }
        .frame(height: 110)
        .onHover { hovered = $0 }
    }
}

// MARK: - 标签 / 分类 全量管理

struct TagManagerView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.theme) private var theme
    @State private var renameTarget: String? = nil
    @State private var renameValue: String = ""
    @State private var confirmDelete: String? = nil
    @State private var showAdd: Bool = false
    @State private var newName: String = ""

    private struct Row: Identifiable {
        let name: String
        let count: Int
        var id: String { name }
    }

    private var rows: [Row] {
        guard let p = appState.project else { return [] }
        return p.allTags.keys.sorted().map { Row(name: $0, count: p.allTags[$0]?.count ?? 0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "tag").foregroundStyle(theme.accent)
                Text("标签").font(AppFont.headline()).foregroundStyle(theme.ink)
                Text("\(rows.count)").font(AppFont.monoCaption()).foregroundStyle(theme.inkTertiary)
                Spacer()
                Button {
                    showAdd = true
                    newName = ""
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("新建标签 (会先在一篇 _system 草稿里创建, 之后可以再调整)")
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(theme.surface)
            Divider().background(theme.divider)
            group
        }
        .sheet(isPresented: $showAdd) {
            AddTaxonomySheet(kind: "标签", name: $newName) { v in
                appState.ensureTagExists(v)
            }
        }
        .alert("重命名标签", isPresented: Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )) {
            TextField("新名称", text: $renameValue)
            Button("确定") {
                if let old = renameTarget {
                    let new = renameValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !new.isEmpty, new != old {
                        appState.renameTagEverywhere(from: old, to: new)
                    }
                }
                renameTarget = nil
            }
            Button("取消", role: .cancel) { renameTarget = nil }
        } message: {
            Text("会把所有文章 front matter 里的 `\(renameTarget ?? "")` 替换为 `\(renameValue)`")
        }
        .alert("确认删除标签?",
               isPresented: Binding(
                get: { confirmDelete != nil },
                set: { if !$0 { confirmDelete = nil } }
               )) {
            Button("从所有文章中移除", role: .destructive) {
                if let t = confirmDelete { appState.removeTagEverywhere(t) }
                confirmDelete = nil
            }
            Button("取消", role: .cancel) { confirmDelete = nil }
        } message: {
            Text("`\(confirmDelete ?? "")` 会从所有文章的 front matter 中移除。")
        }
    }

    @ViewBuilder
    private var group: some View {
        if rows.isEmpty {
            EmptyState(icon: "tag", text: "还没有任何标签\n点击右上角 + 新建一个\n或在文章上编辑元数据添加")
        } else {
            List {
                Section {
                    ForEach(rows) { row in
                        rowView(row)
                    }
                } header: {
                    Text("已使用").font(AppFont.eyebrow()).foregroundStyle(theme.inkTertiary)
                }
            }
            .listStyle(.inset)
        }
    }

    @ViewBuilder
    private func rowView(_ row: Row) -> some View {
        HStack {
            Image(systemName: "tag.fill")
                .foregroundStyle(theme.accent)
                .frame(width: 18)
            Text(row.name)
                .font(AppFont.body())
                .foregroundStyle(theme.ink)
            Spacer()
            Text("\(row.count)")
                .font(AppFont.monoCaption())
                .foregroundStyle(theme.inkTertiary)
                .padding(.horizontal, 8).padding(.vertical, 2)
                .background(theme.tagBackground)
                .clipShape(Capsule())
        }
        .contextMenu {
            Button("重命名") {
                renameTarget = row.name
                renameValue = row.name
            }
            Button("复制名称") {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(row.name, forType: .string)
            }
            Divider()
            Button(role: .destructive) {
                confirmDelete = row.name
            } label: { Text("从所有文章中移除") }
        }
    }
}

struct CategoryManagerView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.theme) private var theme
    @State private var renameTarget: String? = nil
    @State private var renameValue: String = ""
    @State private var confirmDelete: String? = nil
    @State private var showAdd: Bool = false
    @State private var newName: String = ""

    private struct Row: Identifiable {
        let name: String
        let count: Int
        var id: String { name }
    }

    private var rows: [Row] {
        guard let p = appState.project else { return [] }
        return p.allCategories.keys.sorted().map { Row(name: $0, count: p.allCategories[$0]?.count ?? 0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "folder").foregroundStyle(theme.accent)
                Text("分类").font(AppFont.headline()).foregroundStyle(theme.ink)
                Text("\(rows.count)").font(AppFont.monoCaption()).foregroundStyle(theme.inkTertiary)
                Spacer()
                Button {
                    showAdd = true
                    newName = ""
                } label: { Image(systemName: "plus") }
                .buttonStyle(.borderless)
                .help("新建分类")
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(theme.surface)
            Divider().background(theme.divider)
            if rows.isEmpty {
                EmptyState(icon: "folder", text: "还没有任何分类\n点击右上角 + 新建一个\n或在文章上编辑元数据添加")
            } else {
                List {
                    Section {
                        ForEach(rows) { row in rowView(row) }
                    } header: {
                        Text("已使用").font(AppFont.eyebrow()).foregroundStyle(theme.inkTertiary)
                    }
                }
                .listStyle(.inset)
            }
        }
        .sheet(isPresented: $showAdd) {
            AddTaxonomySheet(kind: "分类", name: $newName) { v in
                appState.ensureCategoryExists(v)
            }
        }
        .alert("重命名分类", isPresented: Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )) {
            TextField("新名称", text: $renameValue)
            Button("确定") {
                if let old = renameTarget {
                    let new = renameValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !new.isEmpty, new != old {
                        appState.renameCategoryEverywhere(from: old, to: new)
                    }
                }
                renameTarget = nil
            }
            Button("取消", role: .cancel) { renameTarget = nil }
        } message: {
            Text("会把所有文章 front matter 里的 `\(renameTarget ?? "")` 替换为 `\(renameValue)`")
        }
        .alert("确认删除分类?",
               isPresented: Binding(
                get: { confirmDelete != nil },
                set: { if !$0 { confirmDelete = nil } }
               )) {
            Button("从所有文章中移除", role: .destructive) {
                if let c = confirmDelete { appState.removeCategoryEverywhere(c) }
                confirmDelete = nil
            }
            Button("取消", role: .cancel) { confirmDelete = nil }
        } message: {
            Text("`\(confirmDelete ?? "")` 会从所有文章的 front matter 中移除。")
        }
    }

    @ViewBuilder
    private func rowView(_ row: Row) -> some View {
        HStack {
            Image(systemName: "folder.fill")
                .foregroundStyle(theme.accent)
                .frame(width: 18)
            Text(row.name)
                .font(AppFont.body())
                .foregroundStyle(theme.ink)
            Spacer()
            Text("\(row.count)")
                .font(AppFont.monoCaption())
                .foregroundStyle(theme.inkTertiary)
                .padding(.horizontal, 8).padding(.vertical, 2)
                .background(theme.tagBackground)
                .clipShape(Capsule())
        }
        .contextMenu {
            Button("重命名") {
                renameTarget = row.name
                renameValue = row.name
            }
            Button("复制名称") {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(row.name, forType: .string)
            }
            Divider()
            Button(role: .destructive) {
                confirmDelete = row.name
            } label: { Text("从所有文章中移除") }
        }
    }
}

// MARK: - 插件管理 (开关)

struct PluginListView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.theme) private var theme
    @State private var refresh: Bool = false

    var body: some View {
        let items = appState.listPlugins()
        VStack(alignment: .leading, spacing: 0) {
            ListHeader(icon: "puzzlepiece", title: "插件", count: items.count)
            if items.isEmpty {
                EmptyState(icon: "puzzlepiece", text: "项目下没有脚本。\n在 `scripts/` 目录放置 `*.js` 文件即可。")
            } else {
                List(items) { item in
                    HStack {
                        Image(systemName: item.enabled ? "checkmark.circle.fill" : "circle.dashed")
                            .foregroundStyle(item.enabled ? theme.accent : theme.inkTertiary)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name)
                                .font(AppFont.body())
                                .foregroundStyle(theme.ink)
                            Text((item.path as NSString).lastPathComponent)
                                .font(AppFont.monoCaption())
                                .foregroundStyle(theme.inkTertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { item.enabled },
                            set: { appState.setPluginEnabled(name: item.name, enabled: $0); refresh.toggle() }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                    }
                    .padding(.vertical, 4)
                }
                .listStyle(.inset)
            }
        }
        .id(refresh) // 强制刷新列表
    }
}

// MARK: - 简单 flow chips (用于标签/分类编辑)

struct FlowChips: View {
    @Environment(\.theme) private var theme
    let items: [String]
    let onRemove: (String) -> Void

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(items, id: \.self) { item in
                HStack(spacing: 4) {
                    Text(item)
                        .font(AppFont.caption())
                        .foregroundStyle(theme.ink)
                    Button {
                        onRemove(item)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(theme.inkTertiary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(theme.tagBackground)
                .clipShape(Capsule())
            }
        }
    }
}

/// 简版 flow layout, 把 children 横向铺, 必要时换行。
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > width, x > 0 {
                x = 0
                y += rowH + spacing
                rowH = 0
            }
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
        return CGSize(width: width, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowH + spacing
                rowH = 0
            }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
    }
}

// MARK: - 主题管理 (SkycBlog / Hexo / Hugo)

struct ThemeManagerView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.theme) private var theme
    @State private var refresh: Bool = false
    @State private var showInstall: Bool = false

    private var items: [(info: ThemeInfo, isActive: Bool)] {
        _ = refresh
        return appState.listThemes()
    }

    private var grouped: [(kind: ThemeKind, themes: [(info: ThemeInfo, isActive: Bool)])] {
        let groups = Dictionary(grouping: items, by: { $0.info.kind })
        return ThemeKind.allCases.compactMap { k in
            guard let arr = groups[k], !arr.isEmpty else { return nil }
            return (k, arr)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "paintpalette").foregroundStyle(theme.accent)
                Text("主题").font(AppFont.headline()).foregroundStyle(theme.ink)
                Text("\(items.count)").font(AppFont.monoCaption()).foregroundStyle(theme.inkTertiary)
                Spacer()
                Button {
                    showInstall = true
                } label: {
                    Label("安装主题", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.bordered)
                .help("从本地路径安装一个主题")
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(theme.surface)
            Divider().background(theme.divider)

            if items.isEmpty {
                EmptyState(icon: "paintpalette", text: "themes/ 目录还没有任何主题\n点击右上角安装一个")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        ForEach(grouped, id: \.kind) { group in
                            sectionView(kind: group.kind, themes: group.themes)
                        }
                    }
                    .padding(16)
                }
            }
        }
        .sheet(isPresented: $showInstall) {
            ThemeInstallSheet()
        }
        .id(refresh) // 强制刷新
    }

    @ViewBuilder
    private func sectionView(kind: ThemeKind, themes: [(info: ThemeInfo, isActive: Bool)]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: kind.systemImage)
                    .foregroundStyle(theme.accent)
                Text("\(kind.displayName) 主题")
                    .font(AppFont.headline())
                    .foregroundStyle(theme.ink)
                Text("\(themes.count)")
                    .font(AppFont.monoCaption())
                    .foregroundStyle(theme.inkTertiary)
                Spacer()
                if kind != .skyc {
                    Text(kind == .hexo
                         ? "识别自 _config.yml + layout/ — 构建时跳过 EJS 解析 (仅供预览)"
                         : "识别自 theme.toml / layouts/ — 构建时跳过 Go template 解析 (仅供预览)")
                        .font(AppFont.caption())
                        .foregroundStyle(theme.inkTertiary)
                }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 12)], spacing: 12) {
                ForEach(themes, id: \.info.id) { item in
                    ThemeCard(info: item.info, isActive: item.isActive, onActivate: {
                        if !item.info.kind.supportsBuild {
                            appState.activateTheme(name: item.info.name)
                            appState.log(.info("已切换 theme 字段, 但 \(item.info.kind.displayName) 主题的 EJS/Go 模板不会被 SkycBlog 引擎解析 — 仅可作为目录识别结果查看。"))
                        } else {
                            appState.activateTheme(name: item.info.name)
                        }
                        refresh.toggle()
                     }, onReveal: {
                        appState.revealThemeInFinder(name: item.info.name)
                    })
                }
            }
        }
    }
}

struct ThemeCard: View {
    @Environment(\.theme) private var theme
    let info: ThemeInfo
    let isActive: Bool
    let onActivate: () -> Void
    let onReveal: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: info.kind.systemImage)
                    .foregroundStyle(info.kind.supportsBuild ? theme.accent : theme.inkTertiary)
                    .font(.system(size: 18))
                Text(info.name)
                    .font(AppFont.headline())
                    .foregroundStyle(theme.ink)
                    .lineLimit(1)
                Spacer()
                if isActive {
                    Text("已启用")
                        .font(AppFont.monoCaption())
                        .foregroundStyle(theme.accent)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(theme.tagBackground)
                        .clipShape(Capsule())
                }
            }
            if let desc = info.description, !desc.isEmpty {
                Text(desc).font(AppFont.caption()).foregroundStyle(theme.inkSecondary)
                    .lineLimit(2)
            }
            HStack(spacing: 6) {
                if info.kind == .skyc {
                    Label("支持构建", systemImage: "checkmark.seal.fill")
                        .font(AppFont.monoCaption()).foregroundStyle(theme.accent)
                } else {
                    Label("识别, 不参与构建", systemImage: "eye")
                        .font(AppFont.monoCaption()).foregroundStyle(theme.inkTertiary)
                }
                if let v = info.version {
                    Text("v\(v)").font(AppFont.monoCaption()).foregroundStyle(theme.inkTertiary)
                }
                if let a = info.author {
                    Text("·").font(AppFont.monoCaption()).foregroundStyle(theme.inkTertiary)
                    Text(a).font(AppFont.monoCaption()).foregroundStyle(theme.inkTertiary)
                }
                Spacer()
            }
            HStack(spacing: 8) {
                if isActive {
                    Button {} label: { Text("当前主题") }
                        .buttonStyle(.bordered)
                        .disabled(true)
                } else {
                    Button("启用", action: onActivate)
                        .buttonStyle(.borderedProminent)
                        .disabled(!info.kind.supportsBuild)
                        .help(info.kind.supportsBuild ? "切换到此主题" : "非 SkycBlog 主题暂不可用于构建")
                }
                Button("在 Finder 中显示", action: onReveal)
                    .buttonStyle(.borderless)
            }
        }
        .padding(14)
        .background(theme.cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isActive ? theme.accent : theme.divider, lineWidth: isActive ? 1.5 : 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct ThemeInstallSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var sourcePath: String = ""
    @State private var destName: String = ""
    @State private var error: String? = nil
    @State private var showPicker: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "安装主题", subtitle: "从本地目录复制到 themes/<name>")
            Divider().background(theme.divider)
            VStack(alignment: .leading, spacing: 12) {
                Text("源路径").font(AppFont.eyebrow()).foregroundStyle(theme.inkSecondary)
                HStack {
                    TextField("/Users/.../my-theme-dir", text: $sourcePath)
                        .textFieldStyle(.roundedBorder)
                    Button("选择…") { showPicker = true }
                        .buttonStyle(.bordered)
                }
                Text("主题名称").font(AppFont.eyebrow()).foregroundStyle(theme.inkSecondary)
                TextField("在 themes/ 下的目录名", text: $destName)
                    .textFieldStyle(.roundedBorder)
                if let error = error {
                    Text(error).font(AppFont.caption()).foregroundStyle(.red)
                }
                Text("会自动识别主题类型 (SkycBlog / Hexo / Hugo)").font(AppFont.monoCaption())
                    .foregroundStyle(theme.inkTertiary)
            }
            .padding(20)
            Divider().background(theme.divider)
            SheetFooter(confirm: "安装", cancel: "取消", onConfirm: doInstall)
        }
        .frame(width: 540, height: 300)
        .fileImporter(isPresented: $showPicker, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                sourcePath = url.path
                if destName.isEmpty {
                    destName = url.lastPathComponent
                }
            }
        }
    }

    private func doInstall() {
        let src = sourcePath.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = destName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !src.isEmpty else { error = "请填写源路径"; return }
        guard !name.isEmpty else { error = "请填写主题名称"; return }
        appState.installThemeFromPath(source: src, name: name)
        dismiss()
    }
}
