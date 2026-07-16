import Foundation

/// 相册与媒体文件管理：在 `content/albums/<name>/` 下创建/重命名/删除相册,以及增删媒体文件。
public enum AlbumManager {
    public struct MediaInfo: Hashable {
        public let filename: String
        public let size: Int64
        public let isImage: Bool
        public let isVideo: Bool
    }

    public static let imageExts: Set<String> = ["jpg","jpeg","png","gif","webp","heic","heif","bmp","tiff"]
    public static let videoExts: Set<String> = ["mp4","mov","m4v","webm","mkv"]

    public static func isImage(_ filename: String) -> Bool {
        imageExts.contains((filename as NSString).pathExtension.lowercased())
    }
    public static func isVideo(_ filename: String) -> Bool {
        videoExts.contains((filename as NSString).pathExtension.lowercased())
    }

    public static func listMedia(in albumDir: String) -> [MediaInfo] {
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(atPath: albumDir)) ?? []
        return files
            .filter { $0 != "index.md" }
            .sorted()
            .map { name -> MediaInfo in
                let p = (albumDir as NSString).appendingPathComponent(name)
                let attrs = try? fm.attributesOfItem(atPath: p)
                let size = (attrs?[.size] as? Int64) ?? 0
                return MediaInfo(filename: name, size: size, isImage: isImage(name), isVideo: isVideo(name))
            }
    }

    public static func albumDir(projectRoot: String, albumName: String) -> String {
        (projectRoot as NSString).appendingPathComponent("content/albums/\(albumName)")
    }

    /// 创建相册：`content/albums/<slug>/index.md`,slug 由标题生成。
    @discardableResult
    public static func createAlbum(projectRoot: String, title: String, layout: String = "album") throws -> String {
        let slug = slugify(title)
        let dir = albumDir(projectRoot: projectRoot, albumName: slug)
        if FileManager.default.fileExists(atPath: dir) {
            throw NSError(domain: "AlbumManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "相册已存在：\(slug)"])
        }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let date = DateUtil.yyyyMMdd.string(from: Date())
        let text = """
        ---
        title: \(title)
        date: \(date) 09:00:00
        layout: \(layout)
        cover: ""
        ---

        # \(title)

        在此写相册描述。
        """
        let path = (dir as NSString).appendingPathComponent("index.md")
        try text.write(toFile: path, atomically: true, encoding: .utf8)
        return dir
    }

    /// 重命名相册目录。
    public static func renameAlbum(projectRoot: String, oldName: String, newName: String) throws {
        let from = albumDir(projectRoot: projectRoot, albumName: oldName)
        let slug = slugify(newName)
        let to = albumDir(projectRoot: projectRoot, albumName: slug)
        if oldName == slug { return }
        if FileManager.default.fileExists(atPath: to) {
            throw NSError(domain: "AlbumManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "目标相册已存在：\(slug)"])
        }
        try FileManager.default.moveItem(atPath: from, toPath: to)
    }

    public static func deleteAlbum(projectRoot: String, name: String) throws {
        let dir = albumDir(projectRoot: projectRoot, albumName: name)
        try FileManager.default.removeItem(atPath: dir)
    }

    /// 把外部文件复制到相册目录。
    public static func addMedia(projectRoot: String, albumName: String, sourceURL: URL) throws -> String {
        let dir = albumDir(projectRoot: projectRoot, albumName: albumName)
        let fm = FileManager.default
        var destPath = (dir as NSString).appendingPathComponent(sourceURL.lastPathComponent)
        if fm.fileExists(atPath: destPath) {
            // 避免覆盖：加数字后缀
            var i = 1
            let base = sourceURL.deletingPathExtension().lastPathComponent
            let ext = sourceURL.pathExtension
            while fm.fileExists(atPath: destPath) {
                destPath = (dir as NSString).appendingPathComponent("\(base)-\(i).\(ext)")
                i += 1
            }
        }
        try fm.copyItem(at: sourceURL, to: URL(fileURLWithPath: destPath))
        return (destPath as NSString).lastPathComponent
    }

    public static func removeMedia(projectRoot: String, albumName: String, filename: String) throws {
        let dir = albumDir(projectRoot: projectRoot, albumName: albumName)
        let p = (dir as NSString).appendingPathComponent(filename)
        try FileManager.default.removeItem(atPath: p)
    }

    public static func renameMedia(projectRoot: String, albumName: String, oldName: String, newName: String) throws {
        let dir = albumDir(projectRoot: projectRoot, albumName: albumName)
        let from = (dir as NSString).appendingPathComponent(oldName)
        let to = (dir as NSString).appendingPathComponent(newName)
        if from == to { return }
        if FileManager.default.fileExists(atPath: to) {
            throw NSError(domain: "AlbumManager", code: 3, userInfo: [NSLocalizedDescriptionKey: "已存在：\(newName)"])
        }
        try FileManager.default.moveItem(atPath: from, toPath: to)
    }

    public static func slugify(_ s: String) -> String {
        var out = ""
        for ch in s.lowercased() {
            if ch.isLetter || ch.isNumber || ch == "-" || ch == "_" {
                out.append(ch)
            } else if ch == " " {
                out.append("-")
            }
        }
        return out.isEmpty ? "album" : out
    }
}
