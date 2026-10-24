import SwiftUI

// MARK: - 云盘页面
struct CloudDiskView: View {
    @ObservedObject private var audioPlayer = AudioPlayer.shared
    @EnvironmentObject var themeManager: ThemeManager
    @State private var songs: [CloudDiskSong] = []
    @State private var isLoading = true
    @State private var totalCount: Int = 0
    @State private var usedSize: String = ""
    @State private var maxSize: String = ""
    @State private var hasMore = false
    @State private var isLoadingMore = false
    
    var body: some View {
        ZStack {
            ThemedBackground()
                .environmentObject(themeManager)
            ScrollView {
                VStack(spacing: 0) {
                    cloudDiskHeader
                    playAllButton

                    if isLoading {
                        ProgressView()
                            .padding(.top, 40)
                    } else if songs.isEmpty {
                        emptyView
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                                CloudDiskSongRow(song: song, index: index + 1) {
                                    playSong(song, index: index)
                                }
                                if index < songs.count - 1 {
                                    Divider().padding(.leading, 60)
                                }
                            }

                            if hasMore {
                                Button(action: { Task { await loadMore() } }) {
                                    if isLoadingMore {
                                        ProgressView()
                                            .padding(.vertical, 20)
                                    } else {
                                        Text("加载更多")
                                            .font(.system(size: 14))
                                            .foregroundColor(.secondary)
                                            .padding(.vertical, 20)
                                    }
                                }
                                .disabled(isLoadingMore)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.bottom, 100)
            }
        }
        .immersiveNavigationChrome()
        .navigationTitle("我的云盘")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadCloudDisk() }
    }

    // MARK: - 头部
    private var cloudDiskHeader: some View {
        VStack(spacing: 12) {
            ZStack {
                LinearGradient(
                    colors: [.blue, .cyan],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: "cloud.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.white)
            }
            .frame(width: 180, height: 180)
            .cornerRadius(12)
            .shadow(color: .blue.opacity(0.3), radius: 10, x: 0, y: 5)
            
            Text("\(totalCount) 首歌曲")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            if !usedSize.isEmpty && !maxSize.isEmpty {
                Text("已用 \(formatSize(usedSize)) / \(formatSize(maxSize))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 20)
    }
    
    // MARK: - 播放全部
    private var playAllButton: some View {
        Button(action: playAll) {
            HStack {
                Image(systemName: "play.fill")
                Text("播放全部")
                Text("(\(songs.count))").foregroundColor(.white.opacity(0.8))
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                LinearGradient(colors: [.blue, .cyan], startPoint: .leading, endPoint: .trailing)
            )
            .cornerRadius(25)
        }
        .padding(.horizontal, 40)
        .padding(.bottom, 20)
        .disabled(songs.isEmpty)
    }
    
    // MARK: - 空状态
    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "cloud")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.5))
            Text("云盘暂无歌曲")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 320)
        .padding(.top, 60)
    }
    
    // MARK: - 数据加载
    private func loadCloudDisk() async {
        do {
            let response = try await MusicService.shared.getCloudDisk(limit: 50, offset: 0)
            songs = response.data ?? []
            totalCount = response.count ?? songs.count
            usedSize = response.size ?? ""
            maxSize = response.maxSize ?? ""
            hasMore = response.hasMore ?? false
        } catch {
            #if DEBUG
            print("加载云盘失败: \(error)")
            #endif
        }
        isLoading = false
    }
    
    private func loadMore() async {
        guard !isLoadingMore else { return }
        isLoadingMore = true
        do {
            let response = try await MusicService.shared.getCloudDisk(limit: 50, offset: songs.count)
            songs.append(contentsOf: response.data ?? [])
            hasMore = response.hasMore ?? false
        } catch {
            #if DEBUG
            print("加载更多云盘歌曲失败: \(error)")
            #endif
        }
        isLoadingMore = false
    }
    
    // MARK: - 播放
    private func playSong(_ song: CloudDiskSong, index: Int) {
        let tracks = songs.map { $0.toTrack() }
        audioPlayer.setPlaylist(tracks, startAt: index)
    }
    
    private func playAll() {
        guard !songs.isEmpty else { return }
        let tracks = songs.map { $0.toTrack() }
        audioPlayer.setPlaylist(tracks, startAt: 0)
    }
    
    // MARK: - 格式化空间大小
    private func formatSize(_ sizeStr: String) -> String {
        guard let bytes = Double(sizeStr) else { return sizeStr }
        let gb = bytes / 1024.0 / 1024.0 / 1024.0
        if gb >= 1 {
            return String(format: "%.1fGB", gb)
        }
        let mb = bytes / 1024.0 / 1024.0
        return String(format: "%.0fMB", mb)
    }
}

// MARK: - 云盘歌曲行
struct CloudDiskSongRow: View {
    let song: CloudDiskSong
    let index: Int
    let onTap: () -> Void
    @ObservedObject private var audioPlayer = AudioPlayer.shared
    
    private var isPlaying: Bool {
        audioPlayer.currentTrack?.id == song.songId
    }
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Text("\(index)")
                    .font(.system(size: 14))
                    .foregroundColor(isPlaying ? .blue : .secondary)
                    .frame(width: 30)
                
                // 封面
                if let coverUrl = song.simpleSong?.al?.picUrl,
                   let url = URL(string: coverUrl.replacingOccurrences(of: "http://", with: "https://")) {
                    AsyncImage(url: url) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Rectangle().fill(Color.gray.opacity(0.2))
                    }
                    .frame(width: 44, height: 44)
                    .cornerRadius(6)
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.gray.opacity(0.15))
                        .frame(width: 44, height: 44)
                        .overlay(
                            Image(systemName: "cloud.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.gray.opacity(0.5))
                        )
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(song.songName)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(isPlaying ? .blue : .primary)
                        .lineLimit(1)
                    
                    HStack(spacing: 4) {
                        Text(song.artist ?? "未知艺术家")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                        
                        if !song.fileSizeText.isEmpty {
                            Text("·")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(song.fileSizeText)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Spacer()
                
                if isPlaying {
                    if #available(iOS 17.0, *) {
                        Image(systemName: "waveform")
                            .font(.system(size: 14))
                            .foregroundColor(.blue)
                            .symbolEffect(.variableColor.iterative)
                    } else {
                        Image(systemName: "waveform")
                            .font(.system(size: 14))
                            .foregroundColor(.blue)
                    }
                }
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
