import SwiftUI
import UIKit

// MARK: - 外观模式
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system = "跟随系统"
    case light = "浅色模式"
    case dark = "深色模式"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }
    
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

// MARK: - 主题风格
enum ThemeStyle: String, CaseIterable, Identifiable {
    case standard = "默认"
    case strangerThings = "颠倒世界"
    
    var id: String { rawValue }
    
    var displayName: String { rawValue }
    
    var icon: String {
        switch self {
        case .standard: return "paintpalette.fill"
        case .strangerThings: return "bolt.fill"
        }
    }
    
    var description: String {
        switch self {
        case .standard: return "简洁优雅的默认风格"
        case .strangerThings: return "80年代复古霓虹风格"
        }
    }
}

// MARK: - 主题协议
protocol AppTheme {
    // 主色调
    var accentColor: Color { get }
    var accentGradient: [Color] { get }
    
    // 背景色
    var primaryBackground: Color { get }
    var secondaryBackground: Color { get }
    var cardBackground: Color { get }
    
    // 文字颜色
    var primaryText: Color { get }
    var secondaryText: Color { get }
    var tertiaryText: Color { get }
    
    // 特效颜色
    var glowColor: Color { get }
    var highlightColor: Color { get }
    
    // 播放器专用
    var playerGradient: [Color] { get }
    var progressBarColor: Color { get }
    var progressBarGlow: Color { get }
    
    // 动画配置
    var enableGlowEffect: Bool { get }
    var enableFlickerEffect: Bool { get }
    var enableParticles: Bool { get }
}

// MARK: - 默认主题
struct StandardTheme: AppTheme {
    var accentColor: Color { .purple }
    var accentGradient: [Color] { [.pink, .purple] }
    
    var primaryBackground: Color { Color(.systemBackground) }
    var secondaryBackground: Color { Color(.secondarySystemBackground) }
    var cardBackground: Color { Color(.tertiarySystemBackground) }
    
    var primaryText: Color { .primary }
    var secondaryText: Color { .secondary }
    var tertiaryText: Color { Color(.tertiaryLabel) }
    
    var glowColor: Color { .purple.opacity(0.3) }
    var highlightColor: Color { .white }
    
    var playerGradient: [Color] { [.indigo, .purple, .black] }
    var progressBarColor: Color { .white }
    var progressBarGlow: Color { .clear }
    
    var enableGlowEffect: Bool { false }
    var enableFlickerEffect: Bool { false }
    var enableParticles: Bool { false }
}

// MARK: - 怪奇物语主题
struct StrangerThingsTheme: AppTheme {
    // 霓虹红 + 电光蓝
    var accentColor: Color { Color(red: 1.0, green: 0.2, blue: 0.3) } // 霓虹红
    var accentGradient: [Color] { [
        Color(red: 1.0, green: 0.2, blue: 0.3),  // 霓虹红
        Color(red: 0.2, green: 0.6, blue: 1.0)   // 电光蓝
    ] }
    
    // 深色背景
    var primaryBackground: Color { Color(red: 0.05, green: 0.02, blue: 0.08) } // 近乎纯黑带紫
    var secondaryBackground: Color { Color(red: 0.08, green: 0.04, blue: 0.12) }
    var cardBackground: Color { Color(red: 0.1, green: 0.05, blue: 0.15).opacity(0.9) }
    
    // 文字颜色
    var primaryText: Color { .white }
    var secondaryText: Color { Color(white: 0.7) }
    var tertiaryText: Color { Color(white: 0.5) }
    
    // 霓虹发光效果
    var glowColor: Color { Color(red: 1.0, green: 0.2, blue: 0.3).opacity(0.6) }
    var highlightColor: Color { Color(red: 0.2, green: 0.6, blue: 1.0) }
    
    // 播放器
    var playerGradient: [Color] { [
        Color(red: 0.1, green: 0.02, blue: 0.15),
        Color(red: 0.05, green: 0.02, blue: 0.1),
        .black
    ] }
    var progressBarColor: Color { Color(red: 1.0, green: 0.2, blue: 0.3) }
    var progressBarGlow: Color { Color(red: 1.0, green: 0.2, blue: 0.3).opacity(0.8) }
    
    // 特效开关
    var enableGlowEffect: Bool { true }
    var enableFlickerEffect: Bool { true }
    var enableParticles: Bool { true }
}

// MARK: - 主题管理器
class ThemeManager: ObservableObject {
    static let shared = ThemeManager()
    
    @Published var appearanceMode: AppearanceMode = .system {
        didSet {
            UserDefaults.standard.set(appearanceMode.rawValue, forKey: "appearance_mode")
        }
    }
    
    @Published var themeStyle: ThemeStyle = .standard {
        didSet {
            UserDefaults.standard.set(themeStyle.rawValue, forKey: "theme_style")
            updateCurrentTheme()
        }
    }
    
    @Published private(set) var currentTheme: AppTheme = StandardTheme()

    @Published var liquidGlassEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(liquidGlassEnabled, forKey: "liquid_glass_enabled")
        }
    }

    @Published var customBackgroundEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(customBackgroundEnabled, forKey: "custom_background_enabled")
        }
    }

    @Published var backgroundOpacity: Double = 0.55 {
        didSet {
            UserDefaults.standard.set(backgroundOpacity, forKey: "custom_background_opacity")
        }
    }

    @Published var backgroundFrost: Double = 0.35 {
        didSet {
            UserDefaults.standard.set(backgroundFrost, forKey: "custom_background_frost")
        }
    }

    @Published var customBackgroundImage: UIImage? = nil
    
    init() {
        // 加载外观模式
        if let modeRaw = UserDefaults.standard.string(forKey: "appearance_mode"),
           let mode = AppearanceMode(rawValue: modeRaw) {
            self.appearanceMode = mode
        }
        
        // 加载主题风格
        if let styleRaw = UserDefaults.standard.string(forKey: "theme_style"),
           let style = ThemeStyle(rawValue: styleRaw) {
            self.themeStyle = style
        }

        if UserDefaults.standard.object(forKey: "liquid_glass_enabled") != nil {
            liquidGlassEnabled = UserDefaults.standard.bool(forKey: "liquid_glass_enabled")
        }
        customBackgroundEnabled = UserDefaults.standard.bool(forKey: "custom_background_enabled")
        let savedOpacity = UserDefaults.standard.double(forKey: "custom_background_opacity")
        if savedOpacity > 0 {
            backgroundOpacity = min(max(savedOpacity, 0.15), 1.0)
        }
        let savedFrost = UserDefaults.standard.double(forKey: "custom_background_frost")
        if UserDefaults.standard.object(forKey: "custom_background_frost") != nil {
            backgroundFrost = min(max(savedFrost, 0), 1.0)
        }
        customBackgroundImage = Self.loadBackgroundImage()
        
        updateCurrentTheme()
    }
    
    var colorScheme: ColorScheme? {
        appearanceMode.colorScheme
    }
    
    private func updateCurrentTheme() {
        switch themeStyle {
        case .standard:
            currentTheme = StandardTheme()
        case .strangerThings:
            currentTheme = StrangerThingsTheme()
        }
    }
    
    // 便捷访问当前主题属性
    var accentColor: Color { currentTheme.accentColor }
    var accentGradient: [Color] { currentTheme.accentGradient }
    var glowColor: Color { currentTheme.glowColor }
    var enableGlowEffect: Bool { currentTheme.enableGlowEffect }
    var enableFlickerEffect: Bool { currentTheme.enableFlickerEffect }
    var enableParticles: Bool { currentTheme.enableParticles }

    // MARK: - 便捷主题颜色（消除各 View 中重复的主题判断逻辑）

    var isStrangerTheme: Bool { themeStyle == .strangerThings }
    var textColor: Color { currentTheme.primaryText }
    var secondaryTextColor: Color { currentTheme.secondaryText }
    var backgroundColor: Color { currentTheme.primaryBackground }
    var cardBackgroundColor: Color { currentTheme.cardBackground }
    var placeholderBackground: Color { isStrangerTheme ? Color(red: 0.1, green: 0.05, blue: 0.15) : Color(.systemGray5) }

    func setCustomBackground(_ image: UIImage) {
        customBackgroundImage = image
        customBackgroundEnabled = true
        Self.saveBackgroundImage(image)
    }

    func clearCustomBackground() {
        customBackgroundImage = nil
        customBackgroundEnabled = false
        try? FileManager.default.removeItem(at: Self.backgroundFileURL)
    }

    private static var backgroundFileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("custom_app_background.jpg")
    }

    private static func saveBackgroundImage(_ image: UIImage) {
        let resized = image.preparedForBackground()
        guard let data = resized.jpegData(compressionQuality: 0.82) else { return }
        try? data.write(to: backgroundFileURL, options: .atomic)
    }

    private static func loadBackgroundImage() -> UIImage? {
        guard let data = try? Data(contentsOf: backgroundFileURL) else { return nil }
        return UIImage(data: data)
    }
}

private extension UIImage {
    func preparedForBackground(maxDimension: CGFloat = 1800) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxDimension else { return self }
        let scale = maxDimension / longest
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

// MARK: - 主题环境键
struct ThemeKey: EnvironmentKey {
    static let defaultValue: AppTheme = StandardTheme()
}

extension EnvironmentValues {
    var appTheme: AppTheme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

// MARK: - View 扩展
extension View {
    func withAppTheme(_ theme: AppTheme) -> some View {
        environment(\.appTheme, theme)
    }
}
