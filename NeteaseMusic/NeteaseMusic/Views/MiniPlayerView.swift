import SwiftUI

// MARK: - 液体玻璃效果扩展 (模拟 iOS 26 Liquid Glass)
extension View {
    /// 液体玻璃效果 - 圆角矩形
    func liquidGlass<S: Shape>(in shape: S) -> some View {
        LiquidGlassModifier(shape: shape, content: self)
    }
    
    /// 液体玻璃效果 - 圆形
    func liquidGlassCircle() -> some View {
        LiquidGlassCircleModifier(content: self)
    }
    
    /// 液体玻璃效果 - 胶囊形
    func liquidGlassCapsule() -> some View {
        LiquidGlassCapsuleModifier(content: self)
    }
}

// MARK: - 增强版液态玻璃修饰器
private struct LiquidGlassModifier<S: Shape, Content: View>: View {
    let shape: S
    let content: Content
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        content
            .background(
                ZStack {
                    // 层 1: 模糊背景
                    shape
                        .fill(.ultraThinMaterial)
                    
                    // 层 2: 主背景色
                    shape
                        .fill(
                            colorScheme == .dark
                                ? Color(white: 0.12).opacity(0.75)
                                : Color(white: 0.98).opacity(0.8)
                        )
                    
                    // 层 3: 顶部高光渐变（模拟玻璃反射）
                    shape
                        .fill(
                            LinearGradient(
                                colors: colorScheme == .dark
                                    ? [Color.white.opacity(0.2), Color.white.opacity(0.05), .clear]
                                    : [Color.white.opacity(0.9), Color.white.opacity(0.3), .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .mask(
                            shape.fill(
                                LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .center)
                            )
                        )
                    
                    // 层 4: 边缘高光描边
                    shape
                        .stroke(
                            LinearGradient(
                                colors: colorScheme == .dark
                                    ? [Color.white.opacity(0.35), Color.white.opacity(0.1), Color.white.opacity(0.05)]
                                    : [Color.white.opacity(0.95), Color.white.opacity(0.5), Color.white.opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                    
                    // 层 5: 内发光效果
                    shape
                        .stroke(
                            colorScheme == .dark
                                ? Color.white.opacity(0.08)
                                : Color.white.opacity(0.4),
                            lineWidth: 0.5
                        )
                        .padding(1.5)
                }
                .compositingGroup()
            )
            // 多层阴影增加深度
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.15), radius: 20, x: 0, y: 10)
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.2 : 0.08), radius: 8, x: 0, y: 4)
    }
}

private struct LiquidGlassCircleModifier<Content: View>: View {
    let content: Content
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        content
            .background(
                ZStack {
                    // 模糊背景
                    Circle()
                        .fill(.ultraThinMaterial)
                    
                    // 主背景
                    Circle()
                        .fill(
                            colorScheme == .dark
                                ? Color(white: 0.12).opacity(0.75)
                                : Color(white: 0.98).opacity(0.8)
                        )
                    
                    // 顶部高光
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: colorScheme == .dark
                                    ? [Color.white.opacity(0.25), .clear]
                                    : [Color.white.opacity(0.85), .clear],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                    
                    // 边缘高光
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: colorScheme == .dark
                                    ? [Color.white.opacity(0.35), Color.white.opacity(0.08)]
                                    : [Color.white.opacity(0.95), Color.white.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                }
                .compositingGroup()
            )
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.25 : 0.12), radius: 12, x: 0, y: 6)
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.15 : 0.06), radius: 4, x: 0, y: 2)
    }
}

private struct LiquidGlassCapsuleModifier<Content: View>: View {
    let content: Content
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        content
            .background(
                ZStack {
                    // 模糊背景
                    Capsule()
                        .fill(.ultraThinMaterial)
                    
                    // 主背景
                    Capsule()
                        .fill(
                            colorScheme == .dark
                                ? Color(white: 0.12).opacity(0.75)
                                : Color(white: 0.98).opacity(0.8)
                        )
                    
                    // 顶部高光
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: colorScheme == .dark
                                    ? [Color.white.opacity(0.2), .clear]
                                    : [Color.white.opacity(0.8), .clear],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                    
                    // 边缘高光
                    Capsule()
                        .stroke(
                            LinearGradient(
                                colors: colorScheme == .dark
                                    ? [Color.white.opacity(0.3), Color.white.opacity(0.06)]
                                    : [Color.white.opacity(0.9), Color.white.opacity(0.25)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                }
                .compositingGroup()
            )
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.2 : 0.1), radius: 12, x: 0, y: 5)
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.12 : 0.05), radius: 4, x: 0, y: 2)
    }
}

// MARK: - 液体玻璃迷你播放器
struct MiniPlayerView: View {
    @ObservedObject private var audioPlayer = AudioPlayer.shared
    @EnvironmentObject var themeManager: ThemeManager
    @State private var showPlayer = false

    var body: some View {
        HStack(spacing: 10) {
            // 封面和歌曲信息区域 - 使用 Button 确保点击可靠
            Button {
                HapticFeedback.light()
                showPlayer = true
            } label: {
                HStack(spacing: 12) {
                    // 封面
                    miniPlayerCover
                    
                    // 歌曲信息
                    VStack(alignment: .leading, spacing: 2) {
                        Text(audioPlayer.currentTrack?.name ?? "未播放")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(textColor)
                            .lineLimit(1)
                        
                        Text(audioPlayer.currentTrack?.artistName ?? "")
                            .font(.system(size: 13))
                            .foregroundColor(secondaryTextColor)
                            .lineLimit(1)
                    }
                    
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 56)
                .contentShape(Rectangle())
            }
            .buttonStyle(MiniPlayerInfoButtonStyle())
            
            // 控制按钮
            HStack(spacing: 0) {
                // 播放/暂停按钮
                Button {
                    HapticFeedback.light()
                    audioPlayer.togglePlayPause()
                } label: {
                    ZStack {
                        if audioPlayer.isLoading {
                            ProgressView()
                                .frame(width: 24, height: 24)
                        } else {
                            Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(.primary)
                        }
                    }
                    .frame(width: 52, height: 52)
                    .contentShape(Rectangle())
                }
                .buttonStyle(MiniPlayerInfoButtonStyle())

                // 下一首按钮
                Button {
                    HapticFeedback.light()
                    audioPlayer.playNext()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.primary)
                        .frame(width: 52, height: 52)
                        .contentShape(Rectangle())
                }
                .buttonStyle(MiniPlayerInfoButtonStyle())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(miniPlayerBackground)
        .contentShape(RoundedRectangle(cornerRadius: 22))
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .fullScreenCover(isPresented: $showPlayer) {
            PlayerView()
        }
    }
    
    private var textColor: Color {
        themeManager.themeStyle == .strangerThings ? .white : .primary
    }
    
    private var secondaryTextColor: Color {
        themeManager.themeStyle == .strangerThings ? .white.opacity(0.6) : .secondary
    }
    
    // MARK: - 封面视图
    @ViewBuilder
    private var miniPlayerCover: some View {
        Group {
            if let coverUrl = audioPlayer.currentTrack?.coverUrl,
               let url = URL(string: coverUrl) {
                CachedAsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    coverPlaceholder
                }
                .id(coverUrl)
            } else {
                coverPlaceholder
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
    
    private var coverPlaceholder: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color(.systemGray5))
            .overlay(
                Image(systemName: "music.note")
                    .font(.system(size: 18))
                    .foregroundColor(.secondary)
            )
    }
    
    // MARK: - 迷你播放器背景
    @ViewBuilder
    private var miniPlayerBackground: some View {
        if themeManager.themeStyle == .strangerThings {
            ThemedMiniPlayerBackground()
                .allowsHitTesting(false)
        } else if themeManager.liquidGlassEnabled, #available(iOS 26.0, *) {
            RoundedRectangle(cornerRadius: 22)
                .fill(.clear)
                .glassEffect(.regular)
                .allowsHitTesting(false)
        } else if themeManager.liquidGlassEnabled {
            RoundedRectangle(cornerRadius: 22)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 22)
                        .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
                .allowsHitTesting(false)
        } else {
            RoundedRectangle(cornerRadius: 22)
                .fill(Color(.secondarySystemBackground).opacity(0.96))
                .shadow(color: .black.opacity(0.12), radius: 16, x: 0, y: 8)
                .allowsHitTesting(false)
        }
    }
}

// MARK: - 迷你播放器按钮样式
struct MiniPlayerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.85 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - 迷你播放器信息区域按钮样式
struct MiniPlayerInfoButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

#Preview {
    VStack {
        Spacer()
        MiniPlayerView()
    }
    .background(Color.gray.opacity(0.3))
}
