import SwiftUI

struct PlayHistoryView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @StateObject private var localStorage = LocalStorageService.shared
    @ObservedObject private var audioPlayer = AudioPlayer.shared
    @State private var history: [Track] = []
    @State private var showClearAlert = false
    
    // 主题相关
    private var isStrangerTheme: Bool { themeManager.isStrangerTheme }
    private var textColor: Color { themeManager.textColor }
    private var secondaryTextColor: Color { themeManager.secondaryTextColor }
    private var accentColor: Color { isStrangerTheme ? Color(red: 1.0, green: 0.2, blue: 0.3) : .orange }
    private var listRowFill: Color {
        if themeManager.showsCustomWallpaper {
            return Color.clear
        }
        return isStrangerTheme ? Color(red: 0.08, green: 0.04, blue: 0.12) : Color(.systemBackground).opacity(0.55)
    }
    
    var body: some View {
        ZStack {
            ThemedBackground()
                .environmentObject(themeManager)
            Group {
                if history.isEmpty {
                    emptyView
                } else {
                    trackList
                }
            }
        }
        .immersiveNavigationChrome()
        .navigationTitle("最近播放")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if !history.isEmpty {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(action: playAll) {
                            Label("播放全部", systemImage: "play.fill")
                        }
                        
                        Button(role: .destructive, action: { showClearAlert = true }) {
                            Label("清空历史", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 16))
                    }
                }
            }
        }
        .alert("清空播放历史", isPresented: $showClearAlert) {
            Button("取消", role: .cancel) { }
            Button("清空", role: .destructive) {
                clearHistory()
            }
        } message: {
            Text("确定要清空所有播放历史吗？")
        }
        .onAppear {
            loadHistory()
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
                
                Image(systemName: "clock")
                    .font(.system(size: 40, weight: .light))
                    .foregroundColor(accentColor.opacity(0.6))
            }
            
            VStack(spacing: 8) {
                Text("暂无播放记录")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(textColor)
                
                Text("播放的歌曲会显示在这里")
                    .font(.system(size: 14))
                    .foregroundColor(secondaryTextColor)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - 歌曲列表
    private var trackList: some View {
        List {
            // 播放全部
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
                        
                        Text("\(history.count) 首歌曲")
                            .font(.system(size: 12))
                            .foregroundColor(secondaryTextColor)
                    }
                    
                    Spacer()
                }
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
            .listRowBackground(listRowFill)
            
            // 歌曲列表
            ForEach(Array(history.enumerated()), id: \.element.id) { index, track in
                HistoryTrackRow(
                    track: track,
                    isPlaying: audioPlayer.currentTrack?.id == track.id,
                    isFavorite: localStorage.isFavorite(track.id),
                    isStrangerTheme: isStrangerTheme,
                    onPlay: { playTrack(at: index) },
                    onToggleFavorite: { toggleFavorite(track) },
                    onRemove: { removeFromHistory(track) }
                )
                .listRowBackground(listRowFill)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }
    
    // MARK: - 方法
    private func loadHistory() {
        history = localStorage.getHistory()
    }
    
    private func playAll() {
        guard !history.isEmpty else { return }
        audioPlayer.setPlaylist(history, startAt: 0)
    }
    
    private func playTrack(at index: Int) {
        guard index < history.count else { return }
        audioPlayer.setPlaylist(history, startAt: index)
    }
    
    private func toggleFavorite(_ track: Track) {
        _ = localStorage.toggleFavorite(track)
    }
    
    private func removeFromHistory(_ track: Track) {
        withAnimation {
            localStorage.removeFromHistory(track.id)
            history.removeAll { $0.id == track.id }
        }
    }
    
    private func clearHistory() {
        withAnimation {
            localStorage.clearHistory()
            history = []
        }
    }
}

// MARK: - 历史歌曲行
struct HistoryTrackRow: View {
    let track: Track
    let isPlaying: Bool
    let isFavorite: Bool
    var isStrangerTheme: Bool = false
    let onPlay: () -> Void
    let onToggleFavorite: () -> Void
    let onRemove: () -> Void
    
    private var textColor: Color { isStrangerTheme ? .white : .primary }
    private var secondaryTextColor: Color { isStrangerTheme ? .white.opacity(0.6) : .secondary }
    private var accentColor: Color { isStrangerTheme ? Color(red: 1.0, green: 0.2, blue: 0.3) : .red }
    
    var body: some View {
        Button(action: onPlay) {
            HStack(spacing: 12) {
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
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive, action: onRemove) {
                Label("删除", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading) {
            Button(action: onToggleFavorite) {
                Label(
                    isFavorite ? "取消收藏" : "收藏",
                    systemImage: isFavorite ? "heart.slash" : "heart"
                )
            }
            .tint(isFavorite ? .gray : accentColor)
        }
    }
}

#Preview {
    NavigationStack {
        PlayHistoryView()
    }
}
