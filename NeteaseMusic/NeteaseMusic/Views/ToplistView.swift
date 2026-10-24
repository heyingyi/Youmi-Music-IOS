import SwiftUI

struct ToplistView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @State private var toplists: [ToplistItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    
    private let musicService = MusicService.shared
    
    // 主题相关
    private var isStrangerTheme: Bool { themeManager.isStrangerTheme }
    private var textColor: Color { themeManager.textColor }
    private var secondaryTextColor: Color { themeManager.secondaryTextColor }

    
    // 官方榜单 ID
    private let officialIds = [19723756, 3779629, 2884035, 3778678] // 飙升榜、新歌榜、原创榜、热歌榜
    
    var officialToplists: [ToplistItem] {
        toplists.filter { officialIds.contains($0.id) }
    }
    
    var globalToplists: [ToplistItem] {
        toplists.filter { !officialIds.contains($0.id) }
    }
    
    var body: some View {
        ZStack {
            ThemedBackground()
                .environmentObject(themeManager)
            ScrollView(showsIndicators: false) {
                VStack(spacing: 28) {
                    if !officialToplists.isEmpty {
                        officialSection
                    }

                    if !globalToplists.isEmpty {
                        globalSection
                    }
                }
                .padding(.top, 16)
                .padding(.bottom, 100)
            }
        }
        .immersiveNavigationChrome()
        .navigationTitle("排行榜")
        .navigationBarTitleDisplayMode(.large)
        .task {
            await loadToplists()
        }
        .refreshable {
            await loadToplists()
        }
        .overlay {
            if isLoading {
                loadingView
            } else if let error = errorMessage {
                errorView(error)
            }
        }
    }
    
    // MARK: - 官方榜
    private var officialSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(title: "官方榜", icon: "crown.fill", color: .orange)
            
            VStack(spacing: 12) {
                ForEach(officialToplists) { item in
                    NavigationLink(destination: PlaylistDetailView(
                        playlistId: item.id,
                        playlistName: item.name,
                        coverUrl: item.coverImgUrl
                    )) {
                        OfficialToplistCard(item: item)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 16)
        }
    }
    
    // MARK: - 全球榜
    private var globalSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(title: "全球榜", icon: "globe", color: .blue)
            
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 16) {
                ForEach(globalToplists) { item in
                    NavigationLink(destination: PlaylistDetailView(
                        playlistId: item.id,
                        playlistName: item.name,
                        coverUrl: item.coverImgUrl
                    )) {
                        GlobalToplistCard(item: item)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 16)
        }
    }
    
    // MARK: - Section Header
    private func sectionHeader(title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(colors: [color, color.opacity(0.7)], startPoint: .top, endPoint: .bottom)
                )
            
            Text(title)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(textColor)
            
            Spacer()
        }
        .padding(.horizontal, 20)
    }
    
    // MARK: - Loading View
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.3)
                .tint(isStrangerTheme ? Color(red: 1.0, green: 0.2, blue: 0.3) : nil)
            Text("加载排行榜...")
                .font(.system(size: 15))
                .foregroundColor(secondaryTextColor)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Error View
    private func errorView(_ error: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50))
                .foregroundStyle(
                    LinearGradient(colors: [.orange, .red], startPoint: .top, endPoint: .bottom)
                )
            
            Text("加载失败")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(textColor)
            
            Text(error)
                .font(.system(size: 14))
                .foregroundColor(secondaryTextColor)
                .multilineTextAlignment(.center)
            
            Button(action: {
                Task { await loadToplists() }
            }) {
                Text("重新加载")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 12)
                    .background(
                        LinearGradient(
                            colors: isStrangerTheme 
                                ? [Color(red: 1.0, green: 0.2, blue: 0.3), Color(red: 0.8, green: 0.1, blue: 0.2)]
                                : [.red, .pink],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Load Data
    private func loadToplists() async {
        isLoading = true
        errorMessage = nil
        
        do {
            toplists = try await musicService.getToplist()
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
}

// MARK: - 官方榜单卡片
struct OfficialToplistCard: View {
    let item: ToplistItem
    
    var body: some View {
        HStack(spacing: 14) {
            // 封面
            ZStack(alignment: .bottomTrailing) {
                if let url = item.coverImgUrl, let imageUrl = URL(string: url) {
                    CachedAsyncImage(url: imageUrl, targetSize: CGSize(width: 80, height: 80)) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Rectangle()
                            .fill(LinearGradient(colors: [Color(.systemGray4), Color(.systemGray5)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    }
                } else {
                    Rectangle()
                        .fill(LinearGradient(colors: [Color(.systemGray4), Color(.systemGray5)], startPoint: .topLeading, endPoint: .bottomTrailing))
                }
            }
            .frame(width: 80, height: 80)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.1), radius: 6, x: 0, y: 3)
            
            // 歌曲列表
            VStack(alignment: .leading, spacing: 6) {
                Text(item.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                
                if let tracks = item.tracks?.prefix(3) {
                    ForEach(Array(tracks.enumerated()), id: \.offset) { index, track in
                        HStack(spacing: 6) {
                            Text("\(index + 1)")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(index == 0 ? .red : .secondary)
                                .frame(width: 16)
                            
                            Text("\(track.first) - \(track.second)")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
            
            Spacer()
            
            // 箭头
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.gray.opacity(0.5))
        }
        .padding(14)
        .glassEffectRounded(cornerRadius: 16)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
    }
}

// MARK: - 全球榜单卡片
struct GlobalToplistCard: View {
    let item: ToplistItem
    
    var body: some View {
        VStack(spacing: 10) {
            // 封面
            ZStack(alignment: .bottomLeading) {
                if let url = item.coverImgUrl, let imageUrl = URL(string: url) {
                    CachedAsyncImage(url: imageUrl, targetSize: CGSize(width: 100, height: 100)) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Rectangle()
                            .fill(LinearGradient(colors: [Color(.systemGray4), Color(.systemGray5)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    }
                } else {
                    Rectangle()
                        .fill(LinearGradient(colors: [Color(.systemGray4), Color(.systemGray5)], startPoint: .topLeading, endPoint: .bottomTrailing))
                }
                
                // 更新频率标签
                if let freq = item.updateFrequency {
                    Text(freq)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .padding(6)
                }
            }
            .frame(height: 100)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
            
            // 名称
            Text(item.name)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
    }
}

#Preview {
    NavigationView {
        ToplistView()
    }
}
