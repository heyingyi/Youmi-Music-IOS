import SwiftUI

// MARK: - 怪奇物语主题组件

// MARK: - 霓虹发光文字
struct NeonText: View {
    let text: String
    var fontSize: CGFloat = 24
    var fontWeight: Font.Weight = .bold
    var color: Color = Color(red: 1.0, green: 0.2, blue: 0.3)
    var glowRadius: CGFloat = 10
    
    @State private var flickerOpacity: Double = 1.0
    @State private var flickerTimer: Timer?
    @EnvironmentObject var themeManager: ThemeManager
    
    var body: some View {
        ZStack {
            // 发光层（多层叠加增强效果）
            if themeManager.enableGlowEffect {
                Text(text)
                    .font(.system(size: fontSize, weight: fontWeight))
                    .foregroundColor(color)
                    .blur(radius: glowRadius * 1.5)
                    .opacity(flickerOpacity * 0.5)
                
                Text(text)
                    .font(.system(size: fontSize, weight: fontWeight))
                    .foregroundColor(color)
                    .blur(radius: glowRadius)
                    .opacity(flickerOpacity * 0.7)
                
                Text(text)
                    .font(.system(size: fontSize, weight: fontWeight))
                    .foregroundColor(color)
                    .blur(radius: glowRadius * 0.5)
                    .opacity(flickerOpacity * 0.9)
            }
            
            // 主文字
            Text(text)
                .font(.system(size: fontSize, weight: fontWeight))
                .foregroundColor(.white)
                .opacity(flickerOpacity)
        }
        .onAppear {
            if themeManager.enableFlickerEffect {
                startFlicker()
            }
        }
        .onDisappear {
            flickerTimer?.invalidate()
            flickerTimer = nil
        }
    }
    
    private func startFlicker() {
        // 随机闪烁效果
        flickerTimer = Timer.scheduledTimer(withTimeInterval: Double.random(in: 2...5), repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.05)) {
                flickerOpacity = 0.7
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                withAnimation(.easeInOut(duration: 0.05)) {
                    flickerOpacity = 1.0
                }
            }
        }
    }
}

// MARK: - 霓虹边框卡片
struct NeonCard<Content: View>: View {
    let content: Content
    var cornerRadius: CGFloat = 16
    var borderWidth: CGFloat = 2
    var glowColor: Color = Color(red: 1.0, green: 0.2, blue: 0.3)
    
    @EnvironmentObject var themeManager: ThemeManager
    @State private var glowIntensity: Double = 0.6
    
    init(cornerRadius: CGFloat = 16, borderWidth: CGFloat = 2, glowColor: Color = Color(red: 1.0, green: 0.2, blue: 0.3), @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.borderWidth = borderWidth
        self.glowColor = glowColor
        self.content = content()
    }
    
    var body: some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color(red: 0.08, green: 0.04, blue: 0.12).opacity(0.95))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(
                        LinearGradient(
                            colors: [glowColor, glowColor.opacity(0.5)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: borderWidth
                    )
                    .blur(radius: themeManager.enableGlowEffect ? 4 : 0)
                    .opacity(glowIntensity)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(glowColor.opacity(0.8), lineWidth: 1)
            )
            .shadow(color: glowColor.opacity(themeManager.enableGlowEffect ? 0.4 : 0), radius: 15, x: 0, y: 0)
            .onAppear {
                if themeManager.enableGlowEffect {
                    withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                        glowIntensity = 1.0
                    }
                }
            }
    }
}

// MARK: - 颠倒世界粒子效果
struct UpsideDownParticles: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.scenePhase) private var scenePhase
    @State private var particles: [Particle] = []
    @State private var animationTimer: Timer?
    @State private var isVisible: Bool = true
    
    struct Particle: Identifiable {
        let id = UUID()
        var x: CGFloat
        var y: CGFloat
        var size: CGFloat
        var opacity: Double
        var speed: Double
    }
    
    var body: some View {
        GeometryReader { geo in
            // 使用 Canvas 替代 ForEach，大幅提升性能
            Canvas { context, size in
                for particle in particles {
                    let rect = CGRect(
                        x: particle.x - particle.size / 2,
                        y: particle.y - particle.size / 2,
                        width: particle.size,
                        height: particle.size
                    )
                    context.fill(
                        Circle().path(in: rect),
                        with: .color(Color.white.opacity(particle.opacity))
                    )
                }
            }
            .onAppear {
                if themeManager.enableParticles {
                    generateParticles(in: geo.size)
                    startAnimation(in: geo.size)
                }
            }
            .onDisappear {
                stopAnimation()
            }
            .onChangeCompat(of: scenePhase) { _, newPhase in
                // App 进入后台时暂停动画
                if newPhase == .active && isVisible {
                    startAnimation(in: geo.size)
                } else {
                    stopAnimation()
                }
            }
        }
        .allowsHitTesting(false)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            stopAnimation()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            // 延迟恢复，避免切换时的卡顿
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if isVisible {
                    // 需要重新获取 size，这里简化处理
                }
            }
        }
    }
    
    private func generateParticles(in size: CGSize) {
        particles = (0..<20).map { _ in  // 减少粒子数量从 30 到 20
            Particle(
                x: CGFloat.random(in: 0...size.width),
                y: CGFloat.random(in: 0...size.height),
                size: CGFloat.random(in: 1...3),
                opacity: Double.random(in: 0.1...0.4),
                speed: Double.random(in: 0.3...1.5)  // 降低速度
            )
        }
    }
    
    private func startAnimation(in size: CGSize) {
        guard animationTimer == nil else { return }
        // 降低更新频率到 0.15 秒（约 6-7 fps，足够流畅且省电）
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { _ in
            for i in particles.indices {
                particles[i].y -= CGFloat(particles[i].speed)
                
                // 重置到底部
                if particles[i].y < -10 {
                    particles[i].y = size.height + 10
                    particles[i].x = CGFloat.random(in: 0...size.width)
                }
            }
        }
    }
    
    private func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
    }
}

// MARK: - 霓虹进度条
struct NeonProgressBar: View {
    let progress: Double
    var height: CGFloat = 4
    var color: Color = Color(red: 1.0, green: 0.2, blue: 0.3)
    
    @EnvironmentObject var themeManager: ThemeManager
    
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // 背景轨道
                Capsule()
                    .fill(Color.white.opacity(0.1))
                    .frame(height: height)
                
                // 发光效果
                if themeManager.enableGlowEffect {
                    Capsule()
                        .fill(color)
                        .frame(width: geo.size.width * progress, height: height)
                        .blur(radius: 8)
                        .opacity(0.6)
                }
                
                // 进度条
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [color, color.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geo.size.width * progress, height: height)
                
                // 头部发光点
                if progress > 0 && themeManager.enableGlowEffect {
                    Circle()
                        .fill(color)
                        .frame(width: height * 2, height: height * 2)
                        .blur(radius: 4)
                        .offset(x: geo.size.width * progress - height)
                }
            }
        }
        .frame(height: height)
    }
}

// MARK: - 霓虹按钮
struct NeonButton: View {
    let title: String
    var icon: String? = nil
    var color: Color = Color(red: 1.0, green: 0.2, blue: 0.3)
    let action: () -> Void
    
    @EnvironmentObject var themeManager: ThemeManager
    @State private var isPressed = false
    
    var body: some View {
        Button(action: {
            let impact = UIImpactFeedbackGenerator(style: .medium)
            impact.impactOccurred()
            action()
        }) {
            HStack(spacing: 8) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(
                ZStack {
                    // 发光背景
                    if themeManager.enableGlowEffect {
                        Capsule()
                            .fill(color.opacity(0.3))
                            .blur(radius: 10)
                    }
                    
                    // 主背景
                    Capsule()
                        .fill(Color(red: 0.1, green: 0.05, blue: 0.15))
                    
                    // 边框
                    Capsule()
                        .stroke(color, lineWidth: 2)
                }
            )
            .shadow(color: themeManager.enableGlowEffect ? color.opacity(0.5) : .clear, radius: 10, x: 0, y: 0)
        }
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .animation(.spring(response: 0.3), value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}

// MARK: - 信号干扰过渡效果
struct GlitchTransition: ViewModifier {
    let isActive: Bool
    @State private var offset: CGFloat = 0
    @State private var redOffset: CGFloat = 0
    @State private var blueOffset: CGFloat = 0
    
    func body(content: Content) -> some View {
        ZStack {
            if isActive {
                // 红色通道偏移
                content
                    .colorMultiply(.red)
                    .opacity(0.8)
                    .offset(x: redOffset)
                
                // 蓝色通道偏移
                content
                    .colorMultiply(.blue)
                    .opacity(0.8)
                    .offset(x: blueOffset)
            }
            
            content
                .offset(x: offset)
        }
        .onAppear {
            if isActive {
                startGlitch()
            }
        }
    }
    
    private func startGlitch() {
        withAnimation(.easeInOut(duration: 0.05)) {
            offset = CGFloat.random(in: -5...5)
            redOffset = CGFloat.random(in: -3...3)
            blueOffset = CGFloat.random(in: -3...3)
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.easeInOut(duration: 0.05)) {
                offset = 0
                redOffset = 0
                blueOffset = 0
            }
        }
    }
}

extension View {
    func glitchEffect(isActive: Bool) -> some View {
        modifier(GlitchTransition(isActive: isActive))
    }
}

// MARK: - 灯泡闪烁效果（致敬剧中的灯泡通讯）
struct FlickeringLight: View {
    var color: Color = .yellow
    var size: CGFloat = 20
    
    @State private var isOn = true
    @State private var intensity: Double = 1.0
    @State private var flickerTimer: Timer?
    
    var body: some View {
        ZStack {
            // 发光
            Circle()
                .fill(color)
                .frame(width: size * 2, height: size * 2)
                .blur(radius: size)
                .opacity(isOn ? intensity * 0.6 : 0)
            
            // 灯泡
            Circle()
                .fill(isOn ? color : Color.gray.opacity(0.3))
                .frame(width: size, height: size)
                .opacity(isOn ? intensity : 0.3)
        }
        .onAppear {
            startFlickering()
        }
        .onDisappear {
            flickerTimer?.invalidate()
            flickerTimer = nil
        }
    }
    
    private func startFlickering() {
        // 降低闪烁频率
        flickerTimer = Timer.scheduledTimer(withTimeInterval: Double.random(in: 0.3...0.8), repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.05)) {
                if Double.random(in: 0...1) > 0.7 {
                    isOn.toggle()
                }
                intensity = Double.random(in: 0.6...1.0)
            }
        }
    }
}

// MARK: - 怪奇物语主题背景
struct StrangerThingsBackground: View {
    var showScanlines: Bool = true
    var scanlineOpacity: Double = 0.08
    
    @EnvironmentObject var themeManager: ThemeManager
    
    var body: some View {
        ZStack {
            // 深色基底
            Color(red: 0.03, green: 0.01, blue: 0.05)
            
            // 渐变光晕
            GeometryReader { geo in
                ZStack {
                    // 红色光晕（左上）
                    Ellipse()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color(red: 1.0, green: 0.2, blue: 0.3).opacity(0.15),
                                    Color(red: 1.0, green: 0.2, blue: 0.3).opacity(0.05),
                                    .clear
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: geo.size.width * 0.6
                            )
                        )
                        .frame(width: geo.size.width * 1.2, height: geo.size.height * 0.5)
                        .offset(x: -geo.size.width * 0.3, y: -geo.size.height * 0.1)
                    
                    // 蓝色光晕（右下）
                    Ellipse()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color(red: 0.2, green: 0.6, blue: 1.0).opacity(0.12),
                                    Color(red: 0.2, green: 0.6, blue: 1.0).opacity(0.04),
                                    .clear
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: geo.size.width * 0.5
                            )
                        )
                        .frame(width: geo.size.width * 1.0, height: geo.size.height * 0.4)
                        .offset(x: geo.size.width * 0.3, y: geo.size.height * 0.4)
                }
            }
            
            CustomWallpaperLayer()

            // 粒子效果
            if themeManager.enableParticles {
                UpsideDownParticles()
            }
            
            // 扫描线效果
            if showScanlines {
                ScanlineLayer(opacity: scanlineOpacity)
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - 扫描线层（轻量级）
struct ScanlineLayer: View {
    var opacity: Double = 0.08
    var spacing: CGFloat = 4
    
    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                for y in stride(from: 0, to: size.height, by: spacing) {
                    let rect = CGRect(x: 0, y: y, width: size.width, height: 1)
                    context.fill(Path(rect), with: .color(Color.black.opacity(opacity)))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - 预览
#Preview {
    ZStack {
        StrangerThingsBackground()
        
        VStack(spacing: 30) {
            NeonText(text: "STRANGER THINGS", fontSize: 28)
            
            NeonCard {
                VStack(spacing: 12) {
                    Text("颠倒世界")
                        .font(.headline)
                        .foregroundColor(.white)
                    Text("The Upside Down")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
                .padding(20)
            }
            
            NeonProgressBar(progress: 0.6)
                .frame(width: 200)
            
            NeonButton(title: "进入", icon: "bolt.fill") {
                print("Entered")
            }
            
            HStack(spacing: 20) {
                FlickeringLight(color: .red)
                FlickeringLight(color: .yellow)
                FlickeringLight(color: .blue)
            }
        }
        .padding()
    }
    .environmentObject(ThemeManager.shared)
}


// MARK: - 主题感知背景（自动根据当前主题切换）
struct ThemedBackground: View {
    var standardColors: [Color] = [.purple.opacity(0.08), .blue.opacity(0.06), .cyan.opacity(0.04)]
    @EnvironmentObject var themeManager: ThemeManager
    
    var body: some View {
        Group {
            switch themeManager.themeStyle {
            case .standard:
                LiquidGlassBackground(colors: standardColors)
            case .strangerThings:
                StrangerThingsBackground()
            }
        }
    }
}

// MARK: - 主题感知卡片
struct ThemedCard<Content: View>: View {
    let content: Content
    var cornerRadius: CGFloat = 16
    
    @EnvironmentObject var themeManager: ThemeManager
    
    init(cornerRadius: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.content = content()
    }
    
    var body: some View {
        Group {
            switch themeManager.themeStyle {
            case .standard:
                content
                    .glassEffectRounded(cornerRadius: cornerRadius)
            case .strangerThings:
                NeonCard(cornerRadius: cornerRadius) {
                    content
                }
            }
        }
    }
}

// MARK: - 主题感知进度条
struct ThemedProgressBar: View {
    let progress: Double
    var height: CGFloat = 4
    
    @EnvironmentObject var themeManager: ThemeManager
    
    var body: some View {
        Group {
            switch themeManager.themeStyle {
            case .standard:
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.3))
                            .frame(height: height)
                        
                        Capsule()
                            .fill(Color.white)
                            .frame(width: geo.size.width * progress, height: height)
                    }
                }
                .frame(height: height)
                
            case .strangerThings:
                NeonProgressBar(progress: progress, height: height)
            }
        }
    }
}

// MARK: - 主题感知按钮
struct ThemedPillButton: View {
    let title: String
    var icon: String? = nil
    let action: () -> Void
    
    @EnvironmentObject var themeManager: ThemeManager
    
    var body: some View {
        Group {
            switch themeManager.themeStyle {
            case .standard:
                LiquidGlassPillButton(title: title, icon: icon, action: action)
            case .strangerThings:
                NeonButton(title: title, icon: icon, action: action)
            }
        }
    }
}

// MARK: - 主题感知文字标题
struct ThemedTitle: View {
    let text: String
    var fontSize: CGFloat = 24
    
    @EnvironmentObject var themeManager: ThemeManager
    
    var body: some View {
        Group {
            switch themeManager.themeStyle {
            case .standard:
                Text(text)
                    .font(.system(size: fontSize, weight: .bold))
                    .foregroundColor(.primary)
            case .strangerThings:
                NeonText(text: text, fontSize: fontSize)
            }
        }
    }
}

// MARK: - 主题感知 Section
struct ThemedSection<Content: View>: View {
    let title: String?
    let content: Content
    
    @EnvironmentObject var themeManager: ThemeManager
    
    init(title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title = title {
                Group {
                    switch themeManager.themeStyle {
                    case .standard:
                        Text(title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.secondary)
                    case .strangerThings:
                        Text(title.uppercased())
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(Color(red: 1.0, green: 0.2, blue: 0.3).opacity(0.8))
                            .tracking(2)
                    }
                }
                .padding(.horizontal, 20)
            }
            
            ThemedCard {
                content
            }
            .padding(.horizontal, 16)
        }
    }
}


// MARK: - 主题感知 TabBar 背景（圆角矩形）
struct ThemedTabBarBackground: View {
    var cornerRadius: CGFloat = 32
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject var themeManager: ThemeManager
    
    var body: some View {
        Group {
            switch themeManager.themeStyle {
            case .standard:
                standardBackground
            case .strangerThings:
                strangerThingsBackground
            }
        }
    }
    
    @ViewBuilder
    private var standardBackground: some View {
        if #available(iOS 26.0, *) {
            // iOS 26+ 使用原生液态玻璃，加点tint让浅色模式更明显
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(.clear)
                .glassEffect(.regular.tint(colorScheme == .dark ? .clear : Color.white.opacity(0.3)))
                .allowsHitTesting(false) // 确保不阻挡点击
        } else {
            // iOS 26 以下使用自定义实现
            legacyStandardBackground
        }
    }
    
    private var legacyStandardBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(.ultraThinMaterial)
            
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(
                    colorScheme == .dark
                        ? Color(white: 0.1).opacity(0.7)
                        : Color(white: 0.98).opacity(0.75)
                )
            
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(
                    LinearGradient(
                        colors: colorScheme == .dark
                            ? [Color.white.opacity(0.18), Color.white.opacity(0.03), .clear]
                            : [Color.white.opacity(0.9), Color.white.opacity(0.4), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .mask(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .center))
                )
            
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(
                    LinearGradient(
                        colors: colorScheme == .dark
                            ? [Color.white.opacity(0.4), Color.white.opacity(0.12), Color.white.opacity(0.05)]
                            : [Color.white.opacity(1.0), Color.white.opacity(0.6), Color.white.opacity(0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
        }
        .compositingGroup()
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.4 : 0.15), radius: 25, x: 0, y: 12)
    }
    
    private var strangerThingsBackground: some View {
        ZStack {
            // 深色背景
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color(red: 0.05, green: 0.02, blue: 0.08).opacity(0.95))
            
            // 霓虹边框
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color(red: 1.0, green: 0.2, blue: 0.3).opacity(0.8),
                            Color(red: 1.0, green: 0.2, blue: 0.3).opacity(0.3),
                            Color(red: 0.2, green: 0.6, blue: 1.0).opacity(0.3)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
            
            // 发光效果
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(Color(red: 1.0, green: 0.2, blue: 0.3).opacity(0.4), lineWidth: 2)
                .blur(radius: 4)
        }
        .compositingGroup()
        .shadow(color: Color(red: 1.0, green: 0.2, blue: 0.3).opacity(0.3), radius: 15, x: 0, y: 0)
    }
}

// MARK: - 主题感知 TabBar 背景（圆形）
struct ThemedCircleBackground: View {
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject var themeManager: ThemeManager
    
    var body: some View {
        Group {
            switch themeManager.themeStyle {
            case .standard:
                standardCircle
            case .strangerThings:
                strangerThingsCircle
            }
        }
    }
    
    @ViewBuilder
    private var standardCircle: some View {
        if #available(iOS 26.0, *) {
            // iOS 26+ 使用原生液态玻璃，加点tint让浅色模式更明显
            Circle()
                .fill(.clear)
                .glassEffect(.regular.tint(colorScheme == .dark ? .clear : Color.white.opacity(0.3)))
                .allowsHitTesting(false) // 确保不阻挡点击
        } else {
            // iOS 26 以下使用自定义实现
            legacyStandardCircle
        }
    }
    
    private var legacyStandardCircle: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
            
            Circle()
                .fill(
                    colorScheme == .dark
                        ? Color(white: 0.1).opacity(0.7)
                        : Color(white: 0.98).opacity(0.75)
                )
            
            Circle()
                .fill(
                    LinearGradient(
                        colors: colorScheme == .dark
                            ? [Color.white.opacity(0.25), .clear]
                            : [Color.white.opacity(0.9), .clear],
                        startPoint: .top,
                        endPoint: .center
                    )
                )
            
            Circle()
                .stroke(
                    LinearGradient(
                        colors: colorScheme == .dark
                            ? [Color.white.opacity(0.4), Color.white.opacity(0.1)]
                            : [Color.white.opacity(1.0), Color.white.opacity(0.35)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
        }
        .compositingGroup()
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.12), radius: 15, x: 0, y: 8)
    }
    
    private var strangerThingsCircle: some View {
        ZStack {
            Circle()
                .fill(Color(red: 0.05, green: 0.02, blue: 0.08).opacity(0.95))
            
            Circle()
                .stroke(
                    LinearGradient(
                        colors: [
                            Color(red: 1.0, green: 0.2, blue: 0.3).opacity(0.6),
                            Color(red: 0.2, green: 0.6, blue: 1.0).opacity(0.4)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
            
            Circle()
                .stroke(Color(red: 1.0, green: 0.2, blue: 0.3).opacity(0.3), lineWidth: 2)
                .blur(radius: 3)
        }
        .compositingGroup()
        .shadow(color: Color(red: 1.0, green: 0.2, blue: 0.3).opacity(0.25), radius: 10, x: 0, y: 0)
    }
}

// MARK: - 主题感知 Tab 按钮颜色
struct ThemedTabColors {
    let themeStyle: ThemeStyle
    
    var selectedColor: Color {
        switch themeStyle {
        case .standard:
            return .red
        case .strangerThings:
            return Color(red: 1.0, green: 0.2, blue: 0.3)
        }
    }
    
    var unselectedColor: Color {
        switch themeStyle {
        case .standard:
            return .primary
        case .strangerThings:
            return .white.opacity(0.6)
        }
    }
    
    var secondaryColor: Color {
        switch themeStyle {
        case .standard:
            return .secondary
        case .strangerThings:
            return .white.opacity(0.4)
        }
    }
}

// MARK: - 主题感知迷你播放器背景
struct ThemedMiniPlayerBackground: View {
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject var themeManager: ThemeManager
    
    var body: some View {
        Group {
            switch themeManager.themeStyle {
            case .standard:
                standardMiniPlayerBackground
            case .strangerThings:
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(red: 0.08, green: 0.04, blue: 0.12).opacity(0.95))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color(red: 1.0, green: 0.2, blue: 0.3).opacity(0.5),
                                        Color(red: 0.2, green: 0.6, blue: 1.0).opacity(0.3)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: Color(red: 1.0, green: 0.2, blue: 0.3).opacity(0.2), radius: 8, x: 0, y: 0)
            }
        }
    }
    
    @ViewBuilder
    private var standardMiniPlayerBackground: some View {
        if #available(iOS 26.0, *) {
            // iOS 26+ 使用原生液态玻璃，加点tint让浅色模式更明显
            RoundedRectangle(cornerRadius: 16)
                .fill(.clear)
                .glassEffect(.regular.tint(colorScheme == .dark ? .clear : Color.white.opacity(0.3)))
                .allowsHitTesting(false)  // 确保不阻挡点击
        } else {
            // iOS 26 以下使用自定义实现
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(colorScheme == .dark ? 0.1 : 0.3), lineWidth: 0.5)
                )
                .allowsHitTesting(false)  // 确保不阻挡点击
        }
    }
}

// MARK: - 主题感知迷你播放器背景 (Capsule 版本)
struct ThemedCapsuleMiniPlayerBackground: View {
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject var themeManager: ThemeManager
    
    var body: some View {
        Group {
            switch themeManager.themeStyle {
            case .standard:
                standardCapsuleBackground
            case .strangerThings:
                Capsule()
                    .fill(Color(red: 0.08, green: 0.04, blue: 0.12).opacity(0.95))
                    .overlay(
                        Capsule()
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color(red: 1.0, green: 0.2, blue: 0.3).opacity(0.5),
                                        Color(red: 0.2, green: 0.6, blue: 1.0).opacity(0.3)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: Color(red: 1.0, green: 0.2, blue: 0.3).opacity(0.2), radius: 8, x: 0, y: 0)
                    .allowsHitTesting(false)
            }
        }
    }
    
    @ViewBuilder
    private var standardCapsuleBackground: some View {
        if #available(iOS 26.0, *) {
            Capsule()
                .fill(.clear)
                .glassEffect(.regular.tint(colorScheme == .dark ? .clear : Color.white.opacity(0.3)))
                .allowsHitTesting(false)
        } else {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(colorScheme == .dark ? 0.1 : 0.3), lineWidth: 0.5)
                )
                .allowsHitTesting(false)
        }
    }
}

// MARK: - 字母灯墙 (Christmas Lights Wall)
/// Joyce 家的经典场景 - 眉梢灯与字母通讯
struct ChristmasLightsWall: View {
    let message: String
    var animationSpeed: Double = 0.5
    var showAlphabet: Bool = true
    
    @State private var activeLetter: Character? = nil
    @State private var bulbStates: [Character: BulbState] = [:]
    @State private var messageIndex: Int = 0
    @State private var flickerTimer: Timer?
    @State private var isAnimating: Bool = false
    
    private let alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    
    // 灯泡状态
    enum BulbState {
        case off, dim, flickering, bright
    }
    
    // 老式圣诞灯颜色 - 暖色调
    private func bulbColor(for char: Character) -> Color {
        let colors: [Color] = [
            Color(red: 1.0, green: 0.85, blue: 0.4),   // 暖黄
            Color(red: 1.0, green: 0.6, blue: 0.3),    // 橙色
            Color(red: 0.9, green: 0.3, blue: 0.2),    // 暗红
            Color(red: 0.4, green: 0.8, blue: 0.5),    // 暗绿
            Color(red: 0.5, green: 0.6, blue: 0.9),    // 暗蓝
        ]
        let index = Int(char.asciiValue ?? 0) % colors.count
        return colors[index]
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 电线
            wireTop
            
            if showAlphabet {
                VStack(spacing: 0) {
                    alphabetRow(String(alphabet.prefix(9)), rowIndex: 0)
                    alphabetRow(String(alphabet.dropFirst(9).prefix(9)), rowIndex: 1)
                    alphabetRow(String(alphabet.dropFirst(18)), rowIndex: 2)
                }
            } else {
                messageOnlyView
            }
        }
        .background(wallTexture)
        .onAppear {
            initializeBulbStates()
            startAmbientFlickering()
            startMessageAnimation()
        }
        .onDisappear {
            flickerTimer?.invalidate()
            flickerTimer = nil
            isAnimating = false
        }
    }
    
    // MARK: - 墙壁纹理
    private var wallTexture: some View {
        ZStack {
            // 暗色墙壁
            Color(red: 0.12, green: 0.1, blue: 0.08)
            
            // 纹理噪点
            GeometryReader { geo in
                Canvas { context, size in
                    for _ in 0..<200 {
                        let x = CGFloat.random(in: 0...size.width)
                        let y = CGFloat.random(in: 0...size.height)
                        let rect = CGRect(x: x, y: y, width: 1, height: 1)
                        context.fill(Path(rect), with: .color(Color.white.opacity(Double.random(in: 0.01...0.03))))
                    }
                }
            }
        }
    }
    
    // MARK: - 顶部电线
    private var wireTop: some View {
        GeometryReader { geo in
            Path { path in
                path.move(to: CGPoint(x: 0, y: 10))
                // 不规则的电线
                var x: CGFloat = 0
                while x < geo.size.width {
                    let nextX = x + CGFloat.random(in: 20...40)
                    let midY = CGFloat.random(in: 8...15)
                    path.addQuadCurve(
                        to: CGPoint(x: min(nextX, geo.size.width), y: 10),
                        control: CGPoint(x: (x + nextX) / 2, y: midY)
                    )
                    x = nextX
                }
            }
            .stroke(Color.black.opacity(0.8), lineWidth: 2)
        }
        .frame(height: 20)
    }
    
    // MARK: - 字母行
    private func alphabetRow(_ letters: String, rowIndex: Int) -> some View {
        ZStack(alignment: .top) {
            // 横向电线
            GeometryReader { geo in
                Path { path in
                    path.move(to: CGPoint(x: 0, y: 0))
                    var x: CGFloat = 0
                    while x < geo.size.width {
                        let nextX = x + CGFloat.random(in: 15...30)
                        path.addLine(to: CGPoint(x: min(nextX, geo.size.width), y: CGFloat.random(in: -2...2)))
                        x = nextX
                    }
                }
                .stroke(Color.black.opacity(0.7), lineWidth: 1.5)
            }
            .frame(height: 4)
            
            // 灯泡和字母
            HStack(spacing: 0) {
                ForEach(Array(letters.enumerated()), id: \.offset) { index, char in
                    letterWithBulb(char: char, globalIndex: rowIndex * 9 + index)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, 4)
        }
        .frame(height: 75)
    }
    
    // MARK: - 单个灯泡+字母
    private func letterWithBulb(char: Character, globalIndex: Int) -> some View {
        let isActive = activeLetter == char
        let state = bulbStates[char] ?? .dim
        let color = bulbColor(for: char)
        
        // 垂直电线长度随机
        let wireLength: CGFloat = CGFloat(15 + (globalIndex % 3) * 5 + Int.random(in: 0...8))
        
        return VStack(spacing: 0) {
            // 垂直电线
            Rectangle()
                .fill(Color.black.opacity(0.7))
                .frame(width: 1.5, height: wireLength)
            
            // 灯泡
            ZStack {
                // 发光效果
                if isActive || state == .bright {
                    Circle()
                        .fill(color.opacity(0.6))
                        .frame(width: 28, height: 28)
                        .blur(radius: 12)
                    
                    Circle()
                        .fill(color.opacity(0.8))
                        .frame(width: 18, height: 18)
                        .blur(radius: 6)
                }
                
                // 灯泡底座
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(white: 0.15))
                    .frame(width: 8, height: 6)
                    .offset(y: -8)
                
                // 灯泡本体
                Ellipse()
                    .fill(bulbFillColor(char: char, isActive: isActive, state: state))
                    .frame(width: 12, height: 14)
                
                // 玻璃反光
                if isActive || state == .bright {
                    Ellipse()
                        .fill(Color.white.opacity(0.4))
                        .frame(width: 4, height: 5)
                        .offset(x: -2, y: -2)
                }
            }
            
            // 手写字母
            Text(String(char))
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundColor(letterColor(isActive: isActive, state: state))
                .shadow(color: isActive ? color.opacity(0.8) : .clear, radius: 8)
                .rotationEffect(.degrees(Double(globalIndex % 5) * 3 - 6))  // 固定的随机感
                .offset(x: CGFloat(globalIndex % 3) - 1, y: CGFloat(globalIndex % 2))  // 固定偏移
                .padding(.top, 4)
        }
    }
    
    // 灯泡填充颜色
    private func bulbFillColor(char: Character, isActive: Bool, state: BulbState) -> Color {
        let baseColor = bulbColor(for: char)
        if isActive {
            return baseColor
        }
        switch state {
        case .off:
            return Color(white: 0.2)
        case .dim:
            return baseColor.opacity(0.3)
        case .flickering:
            return baseColor.opacity(0.5)
        case .bright:
            return baseColor.opacity(0.9)
        }
    }
    
    // 字母颜色
    private func letterColor(isActive: Bool, state: BulbState) -> Color {
        if isActive {
            return .white
        }
        switch state {
        case .off:
            return Color(white: 0.25)
        case .dim:
            return Color(white: 0.4)
        case .flickering:
            return Color(white: 0.5)
        case .bright:
            return Color(white: 0.7)
        }
    }
    
    // MARK: - 只显示消息
    private var messageOnlyView: some View {
        HStack(spacing: 12) {
            ForEach(Array(message.uppercased().enumerated()), id: \.offset) { index, char in
                if char.isLetter {
                    letterWithBulb(char: char, globalIndex: index)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
    
    // MARK: - 动画
    private func initializeBulbStates() {
        for char in alphabet {
            // 随机初始化灯泡状态 - 有些坏掉了
            let random = Double.random(in: 0...1)
            if random < 0.15 {
                bulbStates[char] = .off  // 15% 坏掉
            } else if random < 0.5 {
                bulbStates[char] = .dim  // 35% 暗淡
            } else if random < 0.8 {
                bulbStates[char] = .flickering  // 30% 闪烁
            } else {
                bulbStates[char] = .bright  // 20% 正常亮
            }
        }
    }
    
    private func startAmbientFlickering() {
        // 随机闪烁效果 - 降低频率
        flickerTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { _ in
            for char in alphabet {
                if bulbStates[char] == .flickering {
                    if Double.random(in: 0...1) > 0.7 {
                        withAnimation(.easeInOut(duration: 0.05)) {
                            bulbStates[char] = Bool.random() ? .dim : .bright
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            withAnimation(.easeInOut(duration: 0.05)) {
                                bulbStates[char] = .flickering
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func startMessageAnimation() {
        let chars = Array(message.uppercased().filter { $0.isLetter })
        guard !chars.isEmpty else { return }
        isAnimating = true
        
        func showNextLetter() {
            guard isAnimating else { return }
            let char = chars[messageIndex]
            
            // 点亮当前字母
            withAnimation(.easeIn(duration: 0.1)) {
                activeLetter = char
            }
            
            // 熄灭
            DispatchQueue.main.asyncAfter(deadline: .now() + animationSpeed) {
                guard self.isAnimating else { return }
                withAnimation(.easeOut(duration: 0.15)) {
                    activeLetter = nil
                }
                
                // 下一个字母
                messageIndex = (messageIndex + 1) % chars.count
                
                // 如果循环完成，暂停一下
                let delay = messageIndex == 0 ? 1.5 : 0.2
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    showNextLetter()
                }
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            showNextLetter()
        }
    }
}

// MARK: - 扫描线滤镜 (CRT Scanlines)
/// 80年代老电视的横线效果
struct ScanlineOverlay: ViewModifier {
    var lineSpacing: CGFloat = 3
    var lineOpacity: Double = 0.15
    var animated: Bool = false
    
    @State private var offset: CGFloat = 0
    
    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    Canvas { context, size in
                        // 绘制扫描线
                        for y in stride(from: offset, to: size.height, by: lineSpacing) {
                            let rect = CGRect(x: 0, y: y, width: size.width, height: 1)
                            context.fill(
                                Path(rect),
                                with: .color(Color.black.opacity(lineOpacity))
                            )
                        }
                    }
                    .allowsHitTesting(false)
                }
            )
            .overlay(
                // 轻微的色差效果
                LinearGradient(
                    colors: [
                        Color.red.opacity(0.03),
                        Color.clear,
                        Color.blue.opacity(0.03)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .allowsHitTesting(false)
            )
            .onAppear {
                if animated {
                    withAnimation(.linear(duration: 0.1).repeatForever(autoreverses: false)) {
                        offset = lineSpacing
                    }
                }
            }
    }
}

extension View {
    /// 添加 CRT 扫描线效果
    func scanlineEffect(lineSpacing: CGFloat = 3, opacity: Double = 0.15, animated: Bool = false) -> some View {
        modifier(ScanlineOverlay(lineSpacing: lineSpacing, lineOpacity: opacity, animated: animated))
    }
}

// MARK: - VHS 录像带效果
struct VHSEffect: ViewModifier {
    @State private var noiseOffset: CGFloat = 0
    @State private var trackingOffset: CGFloat = 0
    @State private var trackingTimer: Timer?
    
    func body(content: Content) -> some View {
        content
            .overlay(
                // 噪点
                GeometryReader { geo in
                    Canvas { context, size in
                        for _ in 0..<100 {
                            let x = CGFloat.random(in: 0...size.width)
                            let y = CGFloat.random(in: 0...size.height)
                            let rect = CGRect(x: x, y: y, width: 1, height: 1)
                            context.fill(
                                Path(rect),
                                with: .color(Color.white.opacity(Double.random(in: 0...0.1)))
                            )
                        }
                    }
                }
                .allowsHitTesting(false)
            )
            .scanlineEffect(lineSpacing: 2, opacity: 0.1)
            // 跟踪线效果
            .overlay(
                Rectangle()
                    .fill(Color.white.opacity(0.1))
                    .frame(height: 2)
                    .offset(y: trackingOffset)
                    .allowsHitTesting(false)
            )
            .onAppear {
                // 随机跟踪线动画 - 降低频率
                trackingTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in
                    if Double.random(in: 0...1) > 0.9 {
                        trackingOffset = CGFloat.random(in: -200...200)
                    }
                }
            }
            .onDisappear {
                trackingTimer?.invalidate()
                trackingTimer = nil
            }
    }
}

extension View {
    func vhsEffect() -> some View {
        modifier(VHSEffect())
    }
}

// MARK: - 次元裂缝 (Dimensional Rift)
/// 通往颠倒世界的裂缝动画
struct DimensionalRift: View {
    var width: CGFloat = 200
    var height: CGFloat = 300
    var isActive: Bool = true
    
    @State private var pulseScale: CGFloat = 1.0
    @State private var rotationAngle: Double = 0
    @State private var particleOffset: CGFloat = 0
    @State private var glowIntensity: Double = 0.5
    @State private var particleTimer: Timer?
    @State private var rotationTimer: Timer?
    
    // 裂缝颜色
    private let riftRed = Color(red: 0.9, green: 0.1, blue: 0.2)
    private let riftOrange = Color(red: 1.0, green: 0.4, blue: 0.1)
    private let innerDark = Color(red: 0.05, green: 0.02, blue: 0.08)
    
    var body: some View {
        ZStack {
            // 外层发光
            ellipseLayer(scale: 1.3, blur: 40, opacity: 0.3)
            ellipseLayer(scale: 1.2, blur: 25, opacity: 0.4)
            ellipseLayer(scale: 1.1, blur: 15, opacity: 0.5)
            
            // 裂缝边缘 - 燃烧效果
            ZStack {
                // 燃烧效果层
                ForEach(0..<8, id: \.self) { i in
                    riftEdge(index: i)
                }
            }
            .scaleEffect(pulseScale)
            
            // 内部黑暗
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [innerDark, innerDark.opacity(0.9), Color.black],
                        center: .center,
                        startRadius: 0,
                        endRadius: width * 0.4
                    )
                )
                .frame(width: width * 0.7, height: height * 0.85)
                .scaleEffect(pulseScale * 0.95)
            
            // 内部粒子
            if isActive {
                riftParticles
            }
            
            // 中心深渊
            Ellipse()
                .fill(Color.black)
                .frame(width: width * 0.5, height: height * 0.65)
                .scaleEffect(pulseScale * 0.9)
        }
        .frame(width: width, height: height)
        .onAppear {
            if isActive {
                startAnimations()
            }
        }
        .onDisappear {
            stopAnimations()
        }
    }
    
    private func ellipseLayer(scale: CGFloat, blur: CGFloat, opacity: Double) -> some View {
        Ellipse()
            .fill(
                RadialGradient(
                    colors: [riftRed.opacity(opacity), riftOrange.opacity(opacity * 0.5), .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: width * 0.6
                )
            )
            .frame(width: width * scale, height: height * scale)
            .blur(radius: blur)
            .opacity(glowIntensity)
    }
    
    private func riftEdge(index: Int) -> some View {
        let angle = Double(index) * 45.0 + rotationAngle * 0.1
        let offset = sin(angle * .pi / 180) * 5
        
        return Ellipse()
            .stroke(
                AngularGradient(
                    colors: [riftRed, riftOrange, riftRed.opacity(0.5), .clear, riftRed],
                    center: .center,
                    startAngle: .degrees(Double(index) * 45),
                    endAngle: .degrees(Double(index) * 45 + 360)
                ),
                lineWidth: 3 + CGFloat(index) * 0.5
            )
            .frame(width: width * 0.8 + CGFloat(index) * 4, height: height * 0.9 + CGFloat(index) * 4)
            .blur(radius: CGFloat(index) * 1.5 + 2)
            .offset(x: offset, y: offset * 0.5)
            .opacity(0.6 - Double(index) * 0.05)
    }
    
    private var riftParticles: some View {
        GeometryReader { geo in
            ForEach(0..<15, id: \.self) { i in
                Circle()
                    .fill(i % 2 == 0 ? riftRed : riftOrange)
                    .frame(width: CGFloat.random(in: 2...6))
                    .offset(
                        x: cos(Double(i) * 24 + particleOffset) * width * 0.3,
                        y: sin(Double(i) * 24 + particleOffset) * height * 0.35
                    )
                    .blur(radius: 2)
                    .opacity(Double.random(in: 0.3...0.8))
            }
        }
        .frame(width: width, height: height)
    }
    
    private func startAnimations() {
        // 脉冲动画
        withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
            pulseScale = 1.05
        }
        
        // 发光强度
        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
            glowIntensity = 0.8
        }
        
        // 粒子旋转 - 降低频率
        particleTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [self] _ in
            particleOffset += 0.2
        }
        
        // 边缘旋转 - 降低频率
        rotationTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [self] _ in
            rotationAngle += 1.5
        }
    }
    
    private func stopAnimations() {
        particleTimer?.invalidate()
        particleTimer = nil
        rotationTimer?.invalidate()
        rotationTimer = nil
    }
}

// MARK: - 裂缝过渡效果
struct RiftTransitionOverlay: View {
    @Binding var isActive: Bool
    var onComplete: (() -> Void)? = nil
    
    @State private var riftScale: CGFloat = 0
    @State private var overlayOpacity: Double = 0
    
    var body: some View {
        ZStack {
            // 黑色遮罩
            Color.black
                .opacity(overlayOpacity)
                .ignoresSafeArea()
            
            // 裂缝
            DimensionalRift(width: 150 * riftScale, height: 250 * riftScale, isActive: true)
                .scaleEffect(riftScale)
        }
        .allowsHitTesting(false)
        .onChange(of: isActive) { newValue in
            if newValue {
                performTransition()
            }
        }
    }
    
    private func performTransition() {
        // 裂缝扩张
        withAnimation(.easeIn(duration: 0.5)) {
            riftScale = 3
        }
        
        // 黑屏
        withAnimation(.easeIn(duration: 0.3).delay(0.3)) {
            overlayOpacity = 1
        }
        
        // 完成回调
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            onComplete?()
            
            // 重置
            withAnimation(.easeOut(duration: 0.3)) {
                overlayOpacity = 0
                riftScale = 0
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isActive = false
            }
        }
    }
}

// MARK: - 颜倒世界滤镜
struct UpsideDownFilter: ViewModifier {
    var intensity: Double = 0.5
    
    func body(content: Content) -> some View {
        content
            // 冷色调
            .overlay(
                Color(red: 0.1, green: 0.2, blue: 0.3)
                    .opacity(intensity * 0.3)
                    .allowsHitTesting(false)
            )
            // 去饱和
            .saturation(1 - intensity * 0.4)
            // 轻微降亮度
            .brightness(-intensity * 0.1)
            // 扫描线
            .scanlineEffect(lineSpacing: 4, opacity: intensity * 0.1)
    }
}

extension View {
    /// 应用颜倒世界滤镜效果
    func upsideDownFilter(intensity: Double = 0.5) -> some View {
        modifier(UpsideDownFilter(intensity: intensity))
    }
}

// MARK: - 预览
#Preview("Stranger Things Effects") {
    ZStack {
        StrangerThingsBackground()
        
        ScrollView {
            VStack(spacing: 40) {
                // 字母灯墙
                VStack(spacing: 8) {
                    Text("字母灯墙")
                        .font(.caption)
                        .foregroundColor(.gray)
                    ChristmasLightsWall(message: "RUN", showAlphabet: true)
                }
                .padding()
                .background(Color.black.opacity(0.5))
                .cornerRadius(16)
                
                // 次元裂缝
                VStack(spacing: 8) {
                    Text("次元裂缝")
                        .font(.caption)
                        .foregroundColor(.gray)
                    DimensionalRift(width: 150, height: 200)
                }
                
                // 扫描线效果
                VStack(spacing: 8) {
                    Text("扫描线效果")
                        .font(.caption)
                        .foregroundColor(.gray)
                    
                    Image(systemName: "tv")
                        .font(.system(size: 60))
                        .foregroundColor(.white)
                        .frame(width: 150, height: 100)
                        .background(Color.gray.opacity(0.3))
                        .cornerRadius(8)
                        .scanlineEffect(animated: true)
                }
            }
            .padding()
        }
    }
    .environmentObject(ThemeManager.shared)
}
