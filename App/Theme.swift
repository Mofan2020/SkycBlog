import SwiftUI

// MARK: - 字体常量

/// 字体层级：全部基于「苹方」+ 等宽用 SF Mono，跨浅深色一致。
enum AppFont {
    /// 大标题：苹方 Semibold（适合 Welcome、Sheet 标题等）
    static func largeTitle(size: CGFloat = 34) -> Font {
        .custom("PingFangSC-Semibold", size: size)
    }
    /// 区域标题：苹方 Semibold
    static func title(size: CGFloat = 20) -> Font {
        .custom("PingFangSC-Semibold", size: size)
    }
    /// 中标题：苹方 Medium（用于 Card 内标题）
    static func headline(size: CGFloat = 15) -> Font {
        .custom("PingFangSC-Medium", size: size)
    }
    /// 正文：苹方 Regular
    static func body(size: CGFloat = 13) -> Font {
        .custom("PingFangSC-Regular", size: size)
    }
    /// 辅助文字：苹方 Regular 较小
    static func subhead(size: CGFloat = 12) -> Font {
        .custom("PingFangSC-Regular", size: size)
    }
    /// 极小标签：苹方 Regular
    static func caption(size: CGFloat = 11) -> Font {
        .custom("PingFangSC-Regular", size: size)
    }
    /// 强调小标签：苹方 Medium
    static func captionMedium(size: CGFloat = 11) -> Font {
        .custom("PingFangSC-Medium", size: size)
    }
    /// 上标大写字距
    static func eyebrow(size: CGFloat = 10) -> Font {
        .custom("PingFangSC-Medium", size: size)
    }
    /// 等宽（路径/技术信息）
    static func mono(size: CGFloat = 12) -> Font {
        .system(size: size, weight: .regular, design: .monospaced)
    }
    static func monoCaption(size: CGFloat = 11) -> Font {
        .system(size: size, weight: .regular, design: .monospaced)
    }
}

// MARK: - 调色板

/// 调色板：根据 `\.colorScheme` 自动给出对应颜色。
struct ThemePalette {
    let scheme: ColorScheme

    // 背景层
    var background: Color       { scheme == .dark ? Color(red: 0.10, green: 0.10, blue: 0.11) : Color(red: 0.97, green: 0.95, blue: 0.92) }
    var surface: Color          { scheme == .dark ? Color(red: 0.16, green: 0.16, blue: 0.18) : Color(red: 1.00, green: 0.99, blue: 0.97) }
    var cardBackground: Color   { scheme == .dark ? Color(red: 0.18, green: 0.18, blue: 0.20) : Color.white }
    var cardHover: Color        { scheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.05) }
    var editorBackground: Color { scheme == .dark ? Color(red: 0.13, green: 0.13, blue: 0.14) : Color.white }
    var sidebarBackground: Color { scheme == .dark ? Color(red: 0.12, green: 0.12, blue: 0.13) : Color(red: 0.96, green: 0.94, blue: 0.91) }

    // 文字层
    var ink: Color              { scheme == .dark ? Color(red: 0.96, green: 0.96, blue: 0.97) : Color(red: 0.12, green: 0.12, blue: 0.13) }
    var inkSecondary: Color     { scheme == .dark ? Color(red: 0.72, green: 0.72, blue: 0.74) : Color(red: 0.40, green: 0.40, blue: 0.42) }
    var inkTertiary: Color      { scheme == .dark ? Color(red: 0.52, green: 0.52, blue: 0.54) : Color(red: 0.60, green: 0.60, blue: 0.62) }

    // 强调色（两套都做适配）
    var accent: Color           { scheme == .dark ? Color(red: 0.94, green: 0.55, blue: 0.42) : Color(red: 0.74, green: 0.32, blue: 0.20) }
    var accentSoft: Color       { accent.opacity(0.16) }
    var success: Color          { scheme == .dark ? Color(red: 0.45, green: 0.75, blue: 0.47) : Color(red: 0.30, green: 0.58, blue: 0.32) }
    var warn: Color             { scheme == .dark ? Color(red: 0.95, green: 0.70, blue: 0.30) : Color(red: 0.85, green: 0.55, blue: 0.10) }
    var errorColor: Color       { scheme == .dark ? Color(red: 0.95, green: 0.50, blue: 0.50) : Color(red: 0.78, green: 0.22, blue: 0.22) }

    // 标签 / 徽章 / 边框
    var tagBackground: Color    { scheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.07) }
    var divider: Color          { scheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.12) }
    var selection: Color        { scheme == .dark ? accent.opacity(0.28) : accent.opacity(0.18) }

    // 终端控制台（始终深色，对比度好）
    var consoleBackground: Color { Color(red: 0.08, green: 0.08, blue: 0.09) }
    var consoleText: Color      { Color(red: 0.92, green: 0.92, blue: 0.93) }
    var consoleTextDim: Color   { Color(red: 0.55, green: 0.55, blue: 0.57) }

    // 预览面板（编辑区右侧的 Markdown 渲染结果）
    var previewBackground: Color { scheme == .dark ? Color(red: 0.14, green: 0.14, blue: 0.15) : Color(red: 1.00, green: 0.99, blue: 0.97) }
}

// MARK: - 公开 API

/// SwiftUI 环境：注入 `ThemePalette`。
private struct ThemeKey: EnvironmentKey {
    static let defaultValue: ThemePalette = ThemePalette(scheme: .light)
}

extension EnvironmentValues {
    var theme: ThemePalette {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

/// 应用根视图用的 modifier：把当前 `colorScheme` 注入到 `\.theme`。
extension View {
    func themed() -> some View {
        modifier(ThemedModifier())
    }
}

private struct ThemedModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    func body(content: Content) -> some View {
        content.environment(\.theme, ThemePalette(scheme: colorScheme))
    }
}
