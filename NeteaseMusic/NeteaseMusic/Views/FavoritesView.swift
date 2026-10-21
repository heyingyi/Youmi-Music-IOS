import SwiftUI

struct FavoritesView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @StateObject private var localStorage = LocalStorageService.shared
    @ObservedObject private var audioPlayer = AudioPlayer.shared
    @State private var favorites: [Track] = []
    @State private var searchText = ""
    
    // 主题相关
    private var isStrangerTheme: Bool { themeManager.isStrangerTheme }
    private var textColor: Color { themeManager.textColor }
    private var secondaryTextColor: Color { themeManager.secondaryTextColor }
    private var accentColor: Color { isStrangerTheme ? Color(red: 1.0, green: 0.2, blue: 0.3) : .red }
    private var listRowFill: Color {
        if themeManager.customBackgroundEnabled, themeManager.customBackgroundImage != nil {
            return Color.clear
        }
        return isStrangerTheme ? Color(red: 0.08, green: 0.04, blue: 0.12) : Color(.systemBackground).opacity(0.55)
    }
    
    // 过滤后的歌曲列表
    private var filteredFavorites: [Track] {
        if searchText.isEmpty {
            return favorites
        }
        let query = searchText.lowercased()
        return favorites.filter {
            $0.name.lowercased().contains(query) ||
            $0.artistName.lowercased().contains(query) ||
            $0.albumName.lowercased().contains(query)
        }
    }
    
    var body: some View {
        Group {
            if favorites.isEmpty {
                emptyView
            } else {
                trackList
            }
        }
        .background(ThemedBackground().environmentObject(themeManager))
        .navigationTitle("我喜欢的音乐")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText, prompt: "搜索歌曲、歌手、专辑")
        .toolbar {
            if !favorites.isEmpty {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: playAll) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(accentColor)
                    }
                }
            }
        }
        .onAppear {
            loadFavorites()
        }
    }
    
    // MARK: - 空状态视图
    private var emptyView: some View {
        VStack(spacing: 20) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(accentColor.opacity(0.1))
                    .frame(width: 100, height: 100)
                
                Image(systemName: "heart")
                    .font(.system(size: 40, weight: .light))
                    .foregroundColor(accentColor.opacity(0.6))
            }
            
            VStack(spacing: 8) {
                Text("暂无收藏")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(textColor)
                
                Text("快去发现喜欢的音乐吧")
                    .font(.system(size: 14))
                    .foregroundColor(secondaryTextColor)
            }
            
            Spacer()
        }
    }
    
    // MARK: - 歌曲列表
    private var trackList: some View {
        List {
            // 播放全部（搜索时隐藏）
            if searchText.isEmpty {
                Button(action: playAll) {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(accentColor)
                                .frame(width: 40, height: 40)
                            
                            Image(systemName: "play.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.white)
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("播放全部")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(textColor)
                            
                            Text("\(favorites.count) 首歌曲")
                                .font(.system(size: 12))
                                .foregroundColor(secondaryTextColor)
                        }
                        
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                    .listRowBackground(listRowFill)
            }
            
            // 搜索结果为空
            if !searchText.isEmpty && filteredFavorites.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 40))
                            .foregroundColor(secondaryTextColor.opacity(0.5))
                        Text("未找到 \"\(searchText)\"")
                            .font(.system(size: 15))
                            .foregroundColor(secondaryTextColor)
                    }
                    .padding(.vertical, 40)
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }
            
            // 歌曲列表
            ForEach(Array(filteredFavorites.enumerated()), id: \.element.id) { index, track in
                let originalIndex = favorites.firstIndex(where: { $0.id == track.id }) ?? index
                FavoriteTrackRow(
                    track: track,
                    index: originalIndex + 1,
                    isPlaying: audioPlayer.currentTrack?.id == track.id,
                    isStrangerTheme: isStrangerTheme,
                    onRemove: { removeFavorite(track) }
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    playTrack(at: originalIndex)
                }
                    .listRowBackground(listRowFill)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }
    
    // MARK: - 方法
    private func loadFavorites() {
        favorites = localStorage.getFavorites()
    }
    
    private func playAll() {
        guard !favorites.isEmpty else { return }
        audioPlayer.setPlaylist(favorites, startAt: 0)
    }
    
    private func playTrack(at index: Int) {
        guard index < favorites.count else { return }
        audioPlayer.setPlaylist(favorites, startAt: index)
    }
    
    private func removeFavorite(_ track: Track) {
        withAnimation {
            localStorage.removeFavorite(track.id)
            favorites.removeAll { $0.id == track.id }
        }
    }
}

// MARK: - 收藏歌曲行
struct FavoriteTrackRow: View {
    let track: Track
    let index: Int
    let isPlaying: Bool
    var isStrangerTheme: Bool = false
    let onRemove: () -> Void
    
    private var textColor: Color { isStrangerTheme ? .white : .primary }
    private var secondaryTextColor: Color { isStrangerTheme ? .white.opacity(0.6) : .secondary }
    private var accentColor: Color { isStrangerTheme ? Color(red: 1.0, green: 0.2, blue: 0.3) : .red }

    var body: some View {
        HStack(spacing: 12) {
            // 序号
            Text("\(index)")
                .font(.system(size: 14))
                .foregroundColor(isPlaying ? accentColor : secondaryTextColor)
                .frame(width: 24)

            // 封面
            if let coverUrl = track.coverUrl, let url = URL(string: coverUrl) {
                CachedAsyncImage(url: url, targetSize: CGSize(width: 50, height: 50)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(.systemGray5))
                }
                .frame(width: 50, height: 50)
                .cornerRadius(6)
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(.systemGray5))
                    .frame(width: 50, height: 50)
                    .overlay(
                        Image(systemName: "music.note")
                            .foregroundColor(.gray)
                    )
            }

            // 歌曲信息
            VStack(alignment: .leading, spacing: 4) {
                Text(track.name)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(isPlaying ? accentColor : textColor)
                    .lineLimit(1)

                Text(track.artistName)
                    .font(.system(size: 13))
                    .foregroundColor(secondaryTextColor)
                    .lineLimit(1)
            }

            Spacer()

            // 时长
            if track.dt != nil {
                Text(track.durationText)
                    .font(.system(size: 12))
                    .foregroundColor(secondaryTextColor)
            }
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive, action: onRemove) {
                Label("取消收藏", systemImage: "heart.slash")
            }
        }
    }
}

#Preview {
    NavigationStack {
        FavoritesView()
    }
}
