import SwiftUI
import SkycBlogCore

/// SkycBlog 桌面端主入口。
@main
struct SkycBlogAppMain: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup("SkycBlog") {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 1000, minHeight: 640)
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("新建项目…") { appState.showNewProject = true }
                    .keyboardShortcut("n", modifiers: [.command])
                Button("打开项目…") { appState.showOpenProject = true }
                    .keyboardShortcut("o", modifiers: [.command])
            }
            CommandMenu("站点") {
                Button("构建") { appState.runBuild() }
                    .keyboardShortcut("b", modifiers: [.command])
                .disabled(appState.project == nil)
                Button("本地预览") { appState.runServe() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                    .disabled(appState.project == nil)
                Divider()
                Button("新建文章…") { appState.showNewPost = true }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                    .disabled(appState.project == nil)
            }
        }
    }
}

/// 全局应用状态。
@MainActor
final class AppState: ObservableObject {
    @Published var project: BlogProject? = nil
    @Published var log: [LogEntry] = []
    @Published var isWorking: Bool = false
    @Published var showNewProject: Bool = false
    @Published var showOpenProject: Bool = false
    @Published var showNewPost: Bool = false
    @Published var previewURL: URL? = nil

    func openProject(at url: URL) {
        do {
            let p = try BlogProject.load(root: url)
            self.project = p
            appendLog(.info("已打开项目：\(url.path)"))
        } catch {
            appendLog(.error("打开项目失败：\(error.localizedDescription)"))
        }
    }

    func createProject(at url: URL, name: String, language: String) {
        do {
            try ProjectScaffold.createProject(at: url.appendingPathComponent(name).path, name: name, language: language)
            let p = try BlogProject.load(root: url.appendingPathComponent(name))
            self.project = p
            appendLog(.info("已创建项目：\(name)"))
        } catch {
            appendLog(.error("创建项目失败：\(error.localizedDescription)"))
        }
    }

    func runBuild() {
        let captured = self.project
        guard let project = captured else { return }
        isWorking = true
        appendLog(.info("开始构建：\(project.root.path)"))
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            do {
                let result = try project.runBuild()
                await MainActor.run {
                    self.appendLog(.success("构建完成：\(result.generated.count) 个文件，用时 \(String(format: "%.2f", result.elapsed)) 秒"))
                    self.isWorking = false
                }
            } catch {
                await MainActor.run {
                    self.appendLog(.error("构建失败：\(error.localizedDescription)"))
                    self.isWorking = false
                }
            }
        }
    }

    func runServe() {
        guard let project = project else { return }
        appendLog(.info("启动本地预览：\(project.outputDir.path)"))
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            do {
                let server = try LocalServer(port: 8765, rootDir: project.outputDir.path)
                try server.start()
                await MainActor.run {
                    self.previewURL = URL(string: "http://localhost:8765/")
                    self.appendLog(.success("本地预览已启动：http://localhost:8765/"))
                }
            } catch {
                await MainActor.run {
                    self.appendLog(.error("启动预览失败：\(error.localizedDescription)"))
                }
            }
        }
    }

    func runNewPost(title: String) {
        guard let project = project else { return }
        do {
            let path = try ProjectScaffold.createPost(projectRoot: project.root.path, title: title)
            appendLog(.success("已创建文章：\(path)"))
            project.refresh()
        } catch {
            appendLog(.error("创建文章失败：\(error.localizedDescription)"))
        }
    }

    func appendLog(_ entry: LogEntry) {
        log.append(entry)
        if log.count > 500 { log.removeFirst(log.count - 500) }
    }
}

struct LogEntry: Identifiable, Equatable {
    enum Level: String { case info, success, warn, error }
    let id = UUID()
    let date = Date()
    let level: Level
    let message: String

    static func info(_ m: String) -> LogEntry { LogEntry(level: .info, message: m) }
    static func success(_ m: String) -> LogEntry { LogEntry(level: .success, message: m) }
    static func warn(_ m: String) -> LogEntry { LogEntry(level: .warn, message: m) }
    static func error(_ m: String) -> LogEntry { LogEntry(level: .error, message: m) }
}
