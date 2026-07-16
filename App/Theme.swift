import SwiftUI

/// 设计 token：纸面感的写作桌面。
enum Theme {
    // 背景
    static let background    = Color(nsColor: .windowBackgroundColor)
    static let cream         = Color(red: 0.97, green: 0.95, blue: 0.92)        // 暖白
    static let cardBackground = Color(nsColor: .controlBackgroundColor)
    static let cardHover     = Color.gray.opacity(0.08)
    static let consoleBackground = Color(red: 0.10, green: 0.10, blue: 0.11)   // 终端暗色
    static let editorBackground = Color(nsColor: .textBackgroundColor)

    // 文字
    static let ink           = Color(red: 0.12, green: 0.12, blue: 0.13)
    static let inkSecondary  = Color(red: 0.40, green: 0.40, blue: 0.42)
    static let inkTertiary   = Color(red: 0.60, green: 0.60, blue: 0.62)

    // 强调
    static let accent        = Color(red: 0.74, green: 0.32, blue: 0.20)        // 砖红 / 朱砂
    static let accentSoft    = Color(red: 0.74, green: 0.32, blue: 0.20).opacity(0.12)
    static let success       = Color(red: 0.30, green: 0.58, blue: 0.32)
    static let warn          = Color(red: 0.85, green: 0.55, blue: 0.10)
    static let error         = Color(red: 0.78, green: 0.22, blue: 0.22)

    // 标签 / 徽章
    static let tagBackground = Color.gray.opacity(0.14)
    static let divider       = Color.gray.opacity(0.22)
    static let selection     = Color.accentColor.opacity(0.18)

    // 字体
    static let serifTitle    = Font.system(.title, design: .serif).weight(.semibold)
    static let serifBody     = Font.system(.body, design: .serif)
    static let mono          = Font.system(.body, design: .monospaced)
    static let monoCaption   = Font.system(.caption, design: .monospaced)
}
