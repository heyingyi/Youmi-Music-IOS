import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

// MARK: - Apple Music 液态玻璃风格设置页
struct SettingsView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @ObservedObject private var audioPlayer = AudioPlayer.shared
    @StateObject private var sourceConfig = MusicSourceConfig.shared
    @Environment(\.dismiss) var dismiss
    
    // 次元裂缝过渡动画
    @State private var showRiftTransition = false
    @State private var pendingThemeStyle: ThemeStyle? = nil
    
    // 缓存管理
    @StateObject private var cacheManager = CacheManager.shared
    @State private var showClearCacheAlert = false
    @State private var selectedCacheType: CacheType = .all
    @State private var clearCacheSuccess = false
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var showBackgroundPicker = false

    var body: some View {
        ZStack {
            themedBackground
                .allowsHitTesting(false)

            ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                // 音源设置
                liquidGlassMusicSourceSection

                liquidGlassCustomSourceSection
                
                // 播放设置
                liquidGlassPlaybackSection
                
                // 外观设置
                liquidGlassAppearanceSection
                
                // 缓存管理
                liquidGlassCacheSection
            }
            .padding(.bottom, 120)
        }
        .immersiveNavigationChrome()
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.large)
        .photosPicker(isPresented: $showBackgroundPicker, selection: $selectedPhotoItem, matching: .images)
        .onChangeCompat(of: selectedPhotoItem) { _, newItem in
            guard let newItem else { return }
            Task { await loadPickedBackground(from: newItem) }
        }
        .alert(selectedCacheType == .downloaded ? "删除所有下载" : "清除缓存", isPresented: $showClearCacheAlert) {
            Button("取消", role: .cancel) { }
            Button("确定", role: .destructive) {
                Task {
                    let success = await cacheManager.clearCache(type: selectedCacheType)
                    await MainActor.run {
                        clearCacheSuccess = success
                    }
                }
            }
        } message: {
            if selectedCacheType == .downloaded {
                Text("确定要删除所有已下载的歌曲吗？此操作不可撤销。")
            } else {
                Text("将清除图片、音频流、动态封面等缓存，不会删除已下载的歌曲。")
            }
        }
            
            // 次元裂缝过渡效果
            RiftTransitionOverlay(isActive: $showRiftTransition) {
                // 过渡完成后切换主题
                if let style = pendingThemeStyle {
                    themeManager.themeStyle = style
                    pendingThemeStyle = nil
                }
            }
        }
    }
    
    // MARK: - 带裂缝动画的主题切换
    private func switchThemeWithRift(to style: ThemeStyle) {
        // 收起键盘
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        
        // 只有切换到颜倒世界主题时才显示裂缝动画
        if style == .strangerThings && themeManager.themeStyle != .strangerThings {
            pendingThemeStyle = style
            showRiftTransition = true
        } else {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                themeManager.themeStyle = style
            }
        }
    }
    
    // MARK: - 主题感知背景
    @ViewBuilder
    private var themedBackground: some View {
        if themeManager.showsCustomWallpaper {
            CustomWallpaperLayer()
        } else {
            switch themeManager.themeStyle {
            case .standard:
                LiquidGlassBackground(colors: [.purple.opacity(0.08), .blue.opacity(0.06), .cyan.opacity(0.04)])
            case .strangerThings:
                StrangerThingsBackground()
            }
        }
    }
    
    // MARK: - 音源设置
    private var liquidGlassMusicSourceSection: some View {
        themedSection(title: "音源") {
            VStack(alignment: .leading, spacing: 16) {
                Text("音质选择")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(themeTextColor)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(MusicQuality.allCases) { quality in
                            themedQualityChip(
                                title: quality.displayName,
                                isSelected: sourceConfig.quality == quality
                            ) {
                                withAnimation(.spring(response: 0.3)) {
                                    sourceConfig.quality = quality
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 16)
            }
        }
    }

    private var liquidGlassCustomSourceSection: some View {
        themedSection(title: "自定义音源") {
            VStack(alignment: .leading, spacing: 0) {
                LiquidGlassToggleRow(
                    title: "启用自定义音源",
                    subtitle: "官方地址失败后使用 HTTP 模板或 lx/GitHub JS 插件",
                    icon: "link",
                    iconColor: .blue,
                    isOn: $sourceConfig.enableCustomSource
                )

                if sourceConfig.enableCustomSource {
                    themedDivider
                    VStack(alignment: .leading, spacing: 8) {
                        Text("接口模板")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                        TextField("https://.../{id} 或 GitHub JS 插件地址", text: $sourceConfig.customSourceTemplate)
                            .font(.system(size: 14, design: .monospaced))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(10)
                            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))

                        Text("JSON 路径")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                        TextField("url 或 data.url", text: $sourceConfig.customSourceJSONPath)
                            .font(.system(size: 14, design: .monospaced))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(10)
                            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))

                        Text("HTTP 占位符：{id} {songId} {quality} {br} {source}。也可填 lx 音源 JS，例如 GitHub blob/raw 链接。")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
        }
    }
    
    // MARK: - 主题感知音质芯片
    @ViewBuilder
    private func themedQualityChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        switch themeManager.themeStyle {
        case .standard:
            LiquidGlassQualityChip(title: title, isSelected: isSelected, action: action)
        case .strangerThings:
            Button(action: {
                let impact = UIImpactFeedbackGenerator(style: .light)
                impact.impactOccurred()
                action()
            }) {
                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(isSelected ? .white : .white.opacity(0.7))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(isSelected 
                                ? Color(red: 1.0, green: 0.2, blue: 0.3)
                                : Color(white: 0.15)
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                isSelected 
                                    ? Color(red: 1.0, green: 0.2, blue: 0.3).opacity(0.8)
                                    : Color.white.opacity(0.1),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: isSelected ? Color(red: 1.0, green: 0.2, blue: 0.3).opacity(0.5) : .clear, radius: 8, x: 0, y: 0)
            }
            .buttonStyle(.plain)
        }
    }
    
    // MARK: - 主题文字颜色
    private var themeTextColor: Color {
        themeManager.themeStyle == .strangerThings ? .white : .primary
    }
    
    // MARK: - 主题感知 Section
    @ViewBuilder
    private func themedSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section 标题
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
            
            // Section 内容
            Group {
                switch themeManager.themeStyle {
                case .standard:
                    content()
                        .glassEffectRounded(cornerRadius: 16)
                case .strangerThings:
                    content()
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color(red: 0.08, green: 0.04, blue: 0.12).opacity(0.95))
                                .allowsHitTesting(false)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(
                                    LinearGradient(
                                        colors: [Color(red: 1.0, green: 0.2, blue: 0.3), Color(red: 1.0, green: 0.2, blue: 0.3).opacity(0.3)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                                .allowsHitTesting(false)
                        )
                        .shadow(color: Color(red: 1.0, green: 0.2, blue: 0.3).opacity(0.2), radius: 10, x: 0, y: 0)
                }
            }
            .padding(.horizontal, 16)
        }
    }
    
    // MARK: - 主题感知分割线
    @ViewBuilder
    private var themedDivider: some View {
        switch themeManager.themeStyle {
        case .standard:
            LiquidGlassDivider()
        case .strangerThings:
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color(red: 1.0, green: 0.2, blue: 0.3).opacity(0.3), Color(red: 0.2, green: 0.6, blue: 1.0).opacity(0.3)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)
        }
    }

    // MARK: - 播放设置
    private var liquidGlassPlaybackSection: some View {
        themedSection(title: "播放") {
            VStack(spacing: 0) {
                switch themeManager.themeStyle {
                case .standard:
                    LiquidGlassToggleRow(
                        title: "允许与其他应用同时播放",
                        subtitle: "锁屏/通知栏/控制中心/车载会不显示播放的歌曲",
                        icon: "speaker.wave.2.fill",
                        iconColor: .orange,
                        isOn: $audioPlayer.allowMixWithOthers
                    )
                case .strangerThings:
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color(red: 1.0, green: 0.5, blue: 0.0))
                                .frame(width: 36, height: 36)
                            Image(systemName: "speaker.wave.2.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("允许与其他应用同时播放")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.white)
                            Text("锁屏/通知栏/控制中心/车载会不显示播放的歌曲")
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.5))
                                .lineLimit(2)
                        }
                        Spacer()
                        Toggle("", isOn: $audioPlayer.allowMixWithOthers)
                            .labelsHidden()
                            .tint(Color(red: 1.0, green: 0.2, blue: 0.3))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
        }
    }

    // MARK: - 液态玻璃外观设置
    private var liquidGlassAppearanceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Group {
                switch themeManager.themeStyle {
                case .standard:
                    Text("外观")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)
                case .strangerThings:
                    Text("外观".uppercased())
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Color(red: 1.0, green: 0.2, blue: 0.3).opacity(0.8))
                        .tracking(2)
                }
            }
            .padding(.horizontal, 20)

            VStack(alignment: .leading, spacing: 20) {
                // 颜倒世界主题装饰 - 字母灯墙
                if themeManager.themeStyle == .strangerThings {
                    VStack(spacing: 0) {
                        ChristmasLightsWall(message: "RUN", animationSpeed: 0.5, showAlphabet: false)
                            .frame(height: 90)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color(red: 1.0, green: 0.2, blue: 0.3).opacity(0.3), lineWidth: 1)
                            )
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 8)
                }
                
                // 主题风格选择
                VStack(alignment: .leading, spacing: 12) {
                    Text("主题风格")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(themeTextColor)
                        .padding(.horizontal, 16)
                        .padding(.top, themeManager.themeStyle == .strangerThings ? 0 : 16)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(ThemeStyle.allCases) { style in
                                ThemeStyleCard(
                                    style: style,
                                    isSelected: themeManager.themeStyle == style
                                ) {
                                    switchThemeWithRift(to: style)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
                
                themedDivider
                    .padding(.horizontal, 16)
                
                // 外观模式选择
                VStack(alignment: .leading, spacing: 12) {
                    Text("外观模式")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(themeTextColor)
                        .padding(.horizontal, 16)

                    HStack(spacing: 12) {
                        ForEach(AppearanceMode.allCases) { mode in
                            LiquidGlassAppearanceButton(
                                mode: mode,
                                isSelected: themeManager.appearanceMode == mode
                            ) {
                                withAnimation(.spring(response: 0.3)) {
                                    themeManager.appearanceMode = mode
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                }

                themedDivider
                    .padding(.horizontal, 16)

                appearanceToggleRow(
                    title: "液态玻璃",
                    subtitle: "卡片毛玻璃效果，iOS 17.3.1 可用",
                    icon: "drop.fill",
                    iconColor: .cyan,
                    isOn: $themeManager.liquidGlassEnabled
                )

                themedDivider
                    .padding(.horizontal, 16)

                customBackgroundControls
                    .padding(.bottom, 8)
            }
            .background {
                if themeManager.themeStyle == .strangerThings {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(red: 0.08, green: 0.04, blue: 0.12).opacity(0.95))
                        .allowsHitTesting(false)
                }
            }
            .modifier(AppearanceCardGlassModifier())
            .padding(.horizontal, 16)
        }
    }

    @ViewBuilder
    private func appearanceToggleRow(
        title: String,
        subtitle: String,
        icon: String,
        iconColor: Color,
        isOn: Binding<Bool>
    ) -> some View {
        switch themeManager.themeStyle {
        case .standard:
            LiquidGlassToggleRow(
                title: title,
                subtitle: subtitle,
                icon: icon,
                iconColor: iconColor,
                isOn: isOn
            )
        case .strangerThings:
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(iconColor)
                        .frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.5))
                        .lineLimit(2)
                }
                Spacer()
                Toggle("", isOn: isOn)
                    .labelsHidden()
                    .tint(Color(red: 1.0, green: 0.2, blue: 0.3))
                    .zIndex(1)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
    }

    private var customBackgroundControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            appearanceToggleRow(
                title: "自定义背景",
                subtitle: "用相册图片作为页面背景",
                icon: "photo.fill",
                iconColor: .pink,
                isOn: $themeManager.customBackgroundEnabled
            )

            HStack(spacing: 12) {
                Button {
                    showBackgroundPicker = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .semibold))
                        Text(themeManager.customBackgroundImage == nil ? "选择图片" : "更换图片")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(themeManager.isStrangerTheme ? .white : .primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(themeManager.isStrangerTheme ? Color.white.opacity(0.12) : Color(.tertiarySystemFill))
                    )
                }
                .buttonStyle(.borderless)

                if themeManager.customBackgroundImage != nil {
                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            themeManager.clearCustomBackground()
                        }
                    } label: {
                        Text("清除")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.red)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.red.opacity(0.12))
                            )
                    }
                    .buttonStyle(.borderless)
                    .zIndex(2)
                }
            }
            .padding(.horizontal, 16)

            if let preview = themeManager.customBackgroundImage {
                Color.clear
                    .frame(height: 92)
                    .overlay {
                        Image(uiImage: preview)
                            .resizable()
                            .scaledToFill()
                    }
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .allowsHitTesting(false)
                    .padding(.horizontal, 16)
            }

            if themeManager.customBackgroundEnabled, themeManager.customBackgroundImage != nil {
                appearanceSliderRow(
                    title: "背景透明度",
                    value: $themeManager.backgroundOpacity,
                    range: 0.15...1.0,
                    icon: "circle.lefthalf.filled",
                    iconColor: .indigo
                )
                appearanceSliderRow(
                    title: "磨砂效果",
                    value: $themeManager.backgroundFrost,
                    range: 0...1.0,
                    icon: "aqi.medium",
                    iconColor: .teal
                )
            }
        }
    }

    private func appearanceSliderRow(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        icon: String,
        iconColor: Color
    ) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(iconColor)
                        .frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                }
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(themeTextColor)
                Spacer()
                Text("\(Int(value.wrappedValue * 100))%")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(themeManager.isStrangerTheme ? Color(red: 1.0, green: 0.2, blue: 0.3) : .purple)
                    .frame(width: 50, alignment: .trailing)
            }
            Slider(value: value, in: range, step: 0.01)
                .tint(themeManager.isStrangerTheme ? Color(red: 1.0, green: 0.2, blue: 0.3) : .purple)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func loadPickedBackground(from item: PhotosPickerItem) async {
        let image = await PickedBackgroundImage.load(from: item)
        await MainActor.run {
            if let image {
                themeManager.setCustomBackground(image)
            }
            selectedPhotoItem = nil
        }
    }
    
    // MARK: - 缓存管理
    private var liquidGlassCacheSection: some View {
        themedSection(title: "存储") {
            VStack(spacing: 0) {
                // 缓存大小显示
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("总占用空间")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(themeTextColor)
                        
                        Text("图片、音频、下载歌曲等")
                            .font(.system(size: 13))
                            .foregroundColor(themeManager.themeStyle == .strangerThings ? .white.opacity(0.6) : .secondary)
                    }
                    
                    Spacer()
                    
                    if cacheManager.isCalculating {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Text(CacheManager.formatSize(cacheManager.totalCacheSize))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(themeManager.themeStyle == .strangerThings 
                                ? Color(red: 1.0, green: 0.2, blue: 0.3) 
                                : .red)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                
                // 详细分类
                if !cacheManager.storageDetails.isEmpty {
                    themedDivider
                    
                    ForEach(cacheManager.storageDetails) { detail in
                        HStack {
                            Image(systemName: detail.icon)
                                .font(.system(size: 14))
                                .foregroundColor(themeManager.themeStyle == .strangerThings ? .white.opacity(0.6) : .secondary)
                                .frame(width: 24)
                            
                            Text(detail.name)
                                .font(.system(size: 14))
                                .foregroundColor(themeManager.themeStyle == .strangerThings ? .white.opacity(0.8) : .primary)
                            
                            Spacer()
                            
                            Text(CacheManager.formatSize(detail.size))
                                .font(.system(size: 14))
                                .foregroundColor(themeManager.themeStyle == .strangerThings ? .white.opacity(0.6) : .secondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }
                }
                
                themedDivider
                
                // 清除缓存按钮（不包含已下载歌曲）
                Button {
                    HapticFeedback.medium()
                    selectedCacheType = .all
                    showClearCacheAlert = true
                } label: {
                    HStack {
                        Image(systemName: "trash")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.orange)
                        
                        Text("清除缓存")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.orange)
                        
                        Spacer()
                        
                        if cacheManager.isClearing {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Text("不含下载")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(cacheManager.isClearing)
                
                // 如果有已下载歌曲，显示单独的删除按钮
                if cacheManager.storageDetails.contains(where: { $0.type == .downloaded }) {
                    themedDivider
                    
                    Button {
                        HapticFeedback.medium()
                        selectedCacheType = .downloaded
                        showClearCacheAlert = true
                    } label: {
                        HStack {
                            Image(systemName: "trash")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.red)
                            
                            Text("删除所有下载")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.red)
                            
                            Spacer()
                            
                            if let downloaded = cacheManager.storageDetails.first(where: { $0.type == .downloaded }) {
                                Text(CacheManager.formatSize(downloaded.size))
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                            }
                            
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(cacheManager.isClearing)
                }
            }
        }
    }
}

// MARK: - 液态玻璃外观模式按钮
struct LiquidGlassAppearanceButton: View {
    let mode: AppearanceMode
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        Button(action: {
            let impact = UIImpactFeedbackGenerator(style: .light)
            impact.impactOccurred()
            action()
        }) {
            VStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(.ultraThinMaterial)

                    if isSelected {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(
                                RadialGradient(
                                    colors: [Color.accentColor.opacity(0.2), .clear],
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: 40
                                )
                            )
                    }
                    
                    // 边框
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(
                            isSelected
                                ? Color.accentColor.opacity(0.5)
                                : (colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.06)),
                            lineWidth: isSelected ? 2 : 1
                        )
                    
                    Image(systemName: mode.icon)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundColor(isSelected ? .accentColor : .secondary)
                }
                .frame(width: 72, height: 52)
                .shadow(color: isSelected ? Color.accentColor.opacity(0.2) : .black.opacity(colorScheme == .dark ? 0.15 : 0.05), radius: 10, x: 0, y: 5)

                Text(mode.rawValue)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(isSelected ? .accentColor : .secondary)
            }
        }
        .buttonStyle(LiquidGlassButtonStyle())
    }
}

// MARK: - 液态玻璃设置行
struct LiquidGlassSettingsRow: View {
    let title: String
    let value: String
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.primary)
            Spacer()
            Text(value)
                .font(.system(size: 15))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

// MARK: - 液态玻璃开关行
struct LiquidGlassToggleRow: View {
    let title: String
    let subtitle: String
    let icon: String
    let iconColor: Color
    @Binding var isOn: Bool
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        HStack(spacing: 14) {
            // 图标
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        LinearGradient(
                            colors: [iconColor, iconColor.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 36, height: 36)

                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
            }

            // 文字
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.primary)

                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(.purple)
                .zIndex(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

// MARK: - 液态玻璃滑块行
struct LiquidGlassSliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let unit: String
    let icon: String
    let iconColor: Color
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                // 图标
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(
                            LinearGradient(
                                colors: [iconColor, iconColor.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 36, height: 36)

                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                }

                // 标题
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.primary)

                Spacer()

                // 数值显示
                Text("\(Int(value))\(unit)")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.purple)
                    .frame(width: 50, alignment: .trailing)
            }

            // 滑块
            Slider(value: $value, in: range, step: 1)
                .tint(.purple)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - 音质选择芯片
struct LiquidGlassQualityChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        Button(action: {
            let impact = UIImpactFeedbackGenerator(style: .light)
            impact.impactOccurred()
            action()
        }) {
            Text(title)
                .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                .foregroundColor(isSelected ? .white : .primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(isSelected 
                            ? Color.purple
                            : (colorScheme == .dark ? Color(white: 0.2) : Color(white: 0.95))
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            isSelected 
                                ? Color.clear 
                                : (colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05)),
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 主题风格选择卡片
struct ThemeStyleCard: View {
    let style: ThemeStyle
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.colorScheme) var colorScheme
    
    private var previewColors: [Color] {
        switch style {
        case .standard:
            return [.purple, .pink]
        case .strangerThings:
            return [Color(red: 1.0, green: 0.2, blue: 0.3), Color(red: 0.2, green: 0.6, blue: 1.0)]
        }
    }
    
    private var backgroundColor: Color {
        switch style {
        case .standard:
            return colorScheme == .dark ? Color(white: 0.15) : Color(white: 0.95)
        case .strangerThings:
            return Color(red: 0.05, green: 0.02, blue: 0.08)
        }
    }
    
    var body: some View {
        Button(action: {
            let impact = UIImpactFeedbackGenerator(style: .medium)
            impact.impactOccurred()
            action()
        }) {
            VStack(spacing: 12) {
                // 预览区域
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(backgroundColor)
                        .frame(width: 100, height: 70)
                    
                    // 主题预览效果
                    if style == .strangerThings {
                        // 颜倒世界主题预览 - 带裂缝和扫描线
                        ZStack {
                            // 微型裂缝效果
                            Ellipse()
                                .fill(
                                    RadialGradient(
                                        colors: [previewColors[0].opacity(0.6), previewColors[0].opacity(0.2), .clear],
                                        center: .center,
                                        startRadius: 0,
                                        endRadius: 25
                                    )
                                )
                                .frame(width: 40, height: 55)
                                .blur(radius: 3)
                            
                            // 裂缝边缘
                            Ellipse()
                                .stroke(previewColors[0], lineWidth: 2)
                                .frame(width: 30, height: 45)
                                .blur(radius: 2)
                            
                            // 内部黑暗
                            Ellipse()
                                .fill(Color.black)
                                .frame(width: 20, height: 35)
                            
                            // 小粒子
                            ForEach(0..<5, id: \.self) { i in
                                Circle()
                                    .fill(previewColors[i % 2])
                                    .frame(width: 2)
                                    .offset(
                                        x: CGFloat.random(in: -15...15),
                                        y: CGFloat.random(in: -20...20)
                                    )
                                    .blur(radius: 1)
                            }
                        }
                        .scanlineEffect(lineSpacing: 2, opacity: 0.2)
                    } else {
                        // 默认主题预览
                        VStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(
                                    LinearGradient(colors: previewColors, startPoint: .leading, endPoint: .trailing)
                                )
                                .frame(width: 60, height: 8)
                            
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color.gray.opacity(0.3))
                                    .frame(width: 20, height: 20)
                                VStack(alignment: .leading, spacing: 2) {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Color.gray.opacity(0.4))
                                        .frame(width: 35, height: 4)
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Color.gray.opacity(0.2))
                                        .frame(width: 25, height: 3)
                                }
                            }
                        }
                    }
                    
                    // 选中边框
                    if isSelected {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                LinearGradient(colors: previewColors, startPoint: .topLeading, endPoint: .bottomTrailing),
                                lineWidth: 2.5
                            )
                            .frame(width: 100, height: 70)
                    }
                }
                .shadow(color: isSelected ? previewColors[0].opacity(0.3) : .black.opacity(0.1), radius: isSelected ? 10 : 5, x: 0, y: 3)
                
                // 标题和描述
                VStack(spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: style.icon)
                            .font(.system(size: 10))
                        Text(style.displayName)
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(isSelected ? previewColors[0] : .primary)
                    
                    Text(style.description)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(width: 110)
        }
        .buttonStyle(LiquidGlassButtonStyle())
    }
}

private struct AppearanceCardGlassModifier: ViewModifier {
    @ObservedObject private var themeManager = ThemeManager.shared

    @ViewBuilder
    func body(content: Content) -> some View {
        if themeManager.themeStyle == .standard {
            content.glassEffectRounded(cornerRadius: 16)
        } else {
            content
        }
    }
}

private struct PickedBackgroundImage: Transferable {
    let image: UIImage

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .image) { data in
            guard let image = UIImage(data: data) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            return PickedBackgroundImage(image: image)
        }
    }

    static func load(from item: PhotosPickerItem) async -> UIImage? {
        if let picked = try? await item.loadTransferable(type: PickedBackgroundImage.self) {
            return picked.image
        }
        if let data = try? await item.loadTransferable(type: Data.self),
           let image = UIImage(data: data) {
            return image
        }
        return nil
    }
}

#Preview {
    NavigationView {
        SettingsView()
            .environmentObject(ThemeManager.shared)
    }
}
