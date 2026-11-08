import SwiftUI

// MARK: - 流光 Shimmer 修饰器
struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -1.5
    let speed: Double
    let angle: Double
    
    init(speed: Double = 1.2, angle: Double = 20) {
        self.speed = speed
        self.angle = angle
    }
    
    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    let width = geo.size.width
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .white.opacity(0.35), location: 0.4),
                            .init(color: .white.opacity(0.5), location: 0.5),
                            .init(color: .white.opacity(0.35), location: 0.6),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: width * 1.5)
                    .rotationEffect(.degrees(angle))
                    .offset(x: width * phase)
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .onAppear {
                withAnimation(
                    .linear(duration: speed)
                    .repeatForever(autoreverses: false)
                ) {
                    phase = 2.5
                }
            }
    }
}

extension View {
    func shimmer(speed: Double = 1.2, angle: Double = 20) -> some View {
        modifier(ShimmerModifier(speed: speed, angle: angle))
    }
}

// MARK: - 通用骨架占位块
struct SkeletonBlock: View {
    let width: CGFloat?
    let height: CGFloat
    let cornerRadius: CGFloat
    @Environment(\.colorScheme) var colorScheme
    
    init(width: CGFloat? = nil, height: CGFloat = 14, cornerRadius: CGFloat = 6) {
        self.width = width
        self.height = height
        self.cornerRadius = cornerRadius
    }
    
    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06))
            .frame(width: width, height: height)
            .shimmer()
    }
}


// MARK: - 分步入场动画修饰器
struct StaggeredEntrance: ViewModifier {
    let index: Int
    let baseDelay: Double
    let duration: Double
    @State private var appeared = false
    
    init(index: Int, baseDelay: Double = 0.06, duration: Double = 0.5) {
        self.index = index
        self.baseDelay = baseDelay
        self.duration = duration
    }
    
    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 24)
            .scaleEffect(appeared ? 1 : 0.95)
            .onAppear {
                withAnimation(
                    .spring(response: duration, dampingFraction: 0.8)
                    .delay(Double(index) * baseDelay)
                ) {
                    appeared = true
                }
            }
    }
}

extension View {
    func staggeredEntrance(index: Int, baseDelay: Double = 0.06, duration: Double = 0.5) -> some View {
        modifier(StaggeredEntrance(index: index, baseDelay: baseDelay, duration: duration))
    }
}

// MARK: - Banner 骨架屏
struct BannerSkeletonView: View {
    @Environment(\.colorScheme) var colorScheme
    
    private var cardWidth: CGFloat {
        min(UIScreen.main.bounds.width * 0.75, 380)
    }
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 16)
                        .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
                        .frame(width: cardWidth, height: cardWidth * 0.6)
                        .overlay(
                            VStack(alignment: .leading, spacing: 8) {
                                Spacer()
                                SkeletonBlock(width: 120, height: 20, cornerRadius: 4)
                                SkeletonBlock(width: 180, height: 14, cornerRadius: 4)
                            }
                            .padding(16),
                            alignment: .bottomLeading
                        )
                        .shimmer(speed: 1.4)
                }
            }
            .padding(.horizontal, 20)
        }
    }
}

// MARK: - 横向卡片骨架屏（最近播放 / 推荐歌单通用）
struct HorizontalCardSkeletonView: View {
    let count: Int
    let cardWidth: CGFloat
    @Environment(\.colorScheme) var colorScheme
    
    init(count: Int = 5, cardWidth: CGFloat? = nil) {
        self.count = count
        self.cardWidth = cardWidth ?? min(UIScreen.main.bounds.width * 0.38, 180)
    }
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(0..<count, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 8) {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
                            .frame(width: cardWidth, height: cardWidth)
                            .shimmer(speed: 1.4)
                        
                        SkeletonBlock(width: cardWidth * 0.8, height: 14)
                        SkeletonBlock(width: cardWidth * 0.5, height: 12)
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }
}

// MARK: - 歌曲列表骨架屏（PlaylistDetail / 搜索结果）
struct TrackListSkeletonView: View {
    let count: Int
    @Environment(\.colorScheme) var colorScheme
    
    init(count: Int = 8) {
        self.count = count
    }
    
    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<count, id: \.self) { index in
                HStack(spacing: 12) {
                    // 封面
                    RoundedRectangle(cornerRadius: 8)
                        .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
                        .frame(width: 48, height: 48)
                        .shimmer()
                    
                    VStack(alignment: .leading, spacing: 6) {
                        SkeletonBlock(width: TrackListSkeletonView.titleWidths[index % TrackListSkeletonView.titleWidths.count], height: 14)
                        SkeletonBlock(width: TrackListSkeletonView.subtitleWidths[index % TrackListSkeletonView.subtitleWidths.count], height: 12)
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
            }
        }
    }

    // 固定宽度序列，避免每次渲染随机抖动
    private static let titleWidths: [CGFloat] = [160, 140, 180, 120, 200, 150, 170, 130]
    private static let subtitleWidths: [CGFloat] = [100, 120, 90, 110, 130, 80, 140, 100]
}

// MARK: - 网格骨架屏（LibraryView 云端歌单）
struct GridSkeletonView: View {
    let count: Int
    let columns: [GridItem]
    @Environment(\.colorScheme) var colorScheme
    
    init(count: Int = 4, columns: [GridItem] = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]) {
        self.count = count
        self.columns = columns
    }
    
    var body: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(0..<count, id: \.self) { index in
                VStack(alignment: .leading, spacing: 8) {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
                        .aspectRatio(1, contentMode: .fit)
                        .shimmer(speed: 1.4)
                    
                    SkeletonBlock(height: 14)
                    SkeletonBlock(width: index % 2 == 0 ? 72 : 56, height: 12)
                }
            }
        }
        .padding(.horizontal, 20)
    }
}
