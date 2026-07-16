import SwiftUI
import SkycBlogCore
import AppKit

// MARK: - 入口

@main
struct SkycBlogAppMain: App {
    @StateObject private var appState = AppState()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup("SkycBlog", id: "main") {
            RootView()
                .environmentObject(appState)
                .frame(minWidth: 1100, minHeight: 680)
        }
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            AppCommands(appState: appState)
        }

        Settings {
            SettingsView()
                .environmentObject(appState)
                .frame(width: 520, height: 360)
        }
    }
}

// MARK: - 顶层命令菜单

struct AppCommands: Commands {
    @ObservedObject var appState: AppState

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("新建项目…") { appState.sheet = .newProject }
                .keyboardShortcut("n", modifiers: [.command])
            Button("打开项目…") { appState.sheet = .openProject }
                .keyboardShortcut("o", modifiers: [.command])
            Divider()
            Button("新建文章…") { appState.sheet = .newPost }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(appState.project == nil)
            Button("在 Finder 中显示项目") { appState.revealProjectInFinder() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(appState.project == nil)
        }
        CommandMenu("站点") {
            Button("构建") { appState.runBuild() }
                .keyboardShortcut("b", modifiers: [.command])
                .disabled(appState.project == nil || appState.isWorking)
            Button("清理并重新构建") { appState.runBuild(clean: true) }
                .keyboardShortcut("b", modifiers: [.command, .shift])
                .disabled(appState.project == nil || appState.isWorking)
            Divider()
            Button("启动本地预览") { appState.startServer() }
                .keyboardShortcut("p", modifiers: [.command])
                .disabled(appState.project == nil || appState.isServing)
            Button("停止预览") { appState.stopServer() }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .disabled(!appState.isServing)
        }
        CommandMenu("视图") {
            Toggle("显示控制台", isOn: $appState.consoleVisible)
                .keyboardShortcut("`", modifiers: [.command])
            Toggle("在编辑器中预览", isOn: $appState.editor.previewVisible)
                .keyboardShortcut("i", modifiers: [.option])
        }
    }
}
