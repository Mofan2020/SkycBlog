import Foundation
import SkycBlogCore

/// `blog serve` 命令。
struct ServeCommand {
    static func run(args: [String]) {
        var port: UInt16 = 8080
        var i = 0
        while i < args.count {
            let a = args[i]
            if a == "--port", i + 1 < args.count, let p = UInt16(args[i+1]) {
                port = p; i += 1
            }
            i += 1
        }
        do {
            let root = FileManager.default.currentDirectoryPath
            let config = try ConfigLoader.load(projectRoot: root)
            // 先构建一次
            Log.info("首次构建...")
            let builder = Builder(config: config, includeDrafts: config.buildDrafts)
            let result = builder.build()
            Log.success("构建完成（\(result.generated.count) 个文件）")
            let server = LocalServer(port: port, rootDir: config.outputDir)
            server.onStatus = { msg in Log.info("[serve] \(msg)") }
            try server.start()
            Log.info("预览地址: http://localhost:\(port)")
            // 监视文件变化（简单的轮询）
            let watcher = FileWatcher(paths: [
                (root as NSString).appendingPathComponent("content"),
                (root as NSString).appendingPathComponent("themes"),
            ]) {
                Log.info("检测到文件变化，重新构建...")
                if let cfg = try? ConfigLoader.load(projectRoot: root) {
                    _ = Builder(config: cfg, includeDrafts: cfg.buildDrafts).build()
                    Log.success("重建完成")
                }
            }
            watcher.start()
            // 持续运行
            RunLoop.main.run()
        } catch {
            Log.error("启动服务失败：\(error)")
            exit(1)
        }
    }
}

/// 简单的文件监视器（基于 DispatchSource 监听目录 vnode 事件）。
final class FileWatcher {
    let paths: [String]
    let onChange: () -> Void
    private var sources: [DispatchSourceFileSystemObject] = []
    private var fds: [Int32] = []
    init(paths: [String], onChange: @escaping () -> Void) {
        self.paths = paths
        self.onChange = onChange
    }
    func start() {
        for p in paths {
            let fd = open(p, O_EVTONLY)
            if fd < 0 { continue }
            fds.append(fd)
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .delete, .rename, .extend], queue: .main)
            source.setEventHandler { [weak self] in self?.onChange() }
            source.setCancelHandler { close(fd) }
            source.resume()
            sources.append(source)
        }
    }
    deinit {
        for s in sources { s.cancel() }
    }
}
