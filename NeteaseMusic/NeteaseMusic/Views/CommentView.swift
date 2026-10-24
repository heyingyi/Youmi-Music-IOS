import SwiftUI

// MARK: - 评论排序类型
enum CommentSortType: Int, CaseIterable {
    case recommend = 1  // 推荐
    case hot = 2        // 热度
    case time = 3       // 时间（最新）
    
    var title: String {
        switch self {
        case .recommend: return "推荐"
        case .hot: return "最热"
        case .time: return "最新"
        }
    }
}

// MARK: - 评论视图
struct CommentView: View {
    let trackId: Int
    let trackName: String
    
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var themeManager: ThemeManager
    @State private var comments: [Comment] = []
    @State private var isLoading = true
    @State private var isLoadingMore = false
    @State private var pageNo = 1
    @State private var cursor: String? = nil
    @State private var hasMore = true
    @State private var totalCount = 0
    @State private var sortType: CommentSortType = .hot
    
    // 评论输入相关
    @State private var commentText = ""
    @State private var isSending = false
    @State private var replyingTo: Comment? = nil
    @State private var showLoginAlert = false
    @FocusState private var isInputFocused: Bool
    
    private let musicService = MusicService.shared
    private let authService = AuthService.shared
    private let pageSize = 20
    
    // 主题相关
    private var isStrangerTheme: Bool { themeManager.isStrangerTheme }
    private var textColor: Color { themeManager.textColor }
    private var secondaryTextColor: Color { themeManager.secondaryTextColor }

    private var accentColor: Color { isStrangerTheme ? Color(red: 1.0, green: 0.2, blue: 0.3) : .blue }
    
    var body: some View {
        NavigationView {
            ZStack {
                ThemedBackground()
                    .environmentObject(themeManager)
                
                VStack(spacing: 0) {
                    if isLoading && comments.isEmpty {
                        loadingView
                    } else if comments.isEmpty {
                        emptyView
                    } else {
                        commentList
                    }
                    commentInputBar
                }
            }
            .immersiveNavigationChrome()
            .navigationTitle("评论")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("关闭") { dismiss() }
                        .foregroundColor(isStrangerTheme ? Color(red: 1.0, green: 0.2, blue: 0.3) : nil)
                }
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 2) {
                        Text("评论")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(textColor)
                        if totalCount > 0 {
                            Text("\(totalCount)条")
                                .font(.system(size: 11))
                                .foregroundColor(secondaryTextColor)
                        }
                    }
                }
            }
            .alert("需要登录", isPresented: $showLoginAlert) {
                Button("确定", role: .cancel) { }
            } message: {
                Text("请先登录后再发表评论")
            }
        }
        .task { await loadComments() }
    }
    
    // MARK: - 加载中视图
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
                .tint(isStrangerTheme ? Color(red: 1.0, green: 0.2, blue: 0.3) : nil)
            Text("加载评论中...")
                .font(.system(size: 14))
                .foregroundColor(secondaryTextColor)
        }
    }
    
    // MARK: - 空视图
    private var emptyView: some View {
        VStack(spacing: 20) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 50, weight: .light))
                .foregroundColor(secondaryTextColor)
            Text("暂无评论")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(secondaryTextColor)
            Text("快来抢沙发吧")
                .font(.system(size: 14))
                .foregroundColor(secondaryTextColor.opacity(0.7))
        }
    }
    
    // MARK: - 评论列表
    private var commentList: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 0) {
                // 歌曲信息
                HStack {
                    Text(trackName)
                        .font(.system(size: 14))
                        .foregroundColor(secondaryTextColor)
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                
                // 排序选择器
                sortPicker
                
                // 评论列表
                ForEach(comments) { comment in
                    CommentRow(
                        comment: comment,
                        trackId: trackId,
                        isStrangerTheme: isStrangerTheme,
                        onReply: { replyToComment($0) },
                        onLike: { c, liked in Task { await likeComment(c, isLiked: liked) } }
                    )
                    if comment.id != comments.last?.id {
                        Divider().padding(.leading, 62)
                    }
                }
                
                // 加载更多
                if hasMore { loadMoreButton }
                
                Spacer(minLength: 80)
            }
        }
        .refreshable { await refreshComments() }
    }
    
    // MARK: - 排序选择器
    private var sortPicker: some View {
        HStack(spacing: 16) {
            ForEach(CommentSortType.allCases, id: \.rawValue) { type in
                Button {
                    if sortType != type {
                        sortType = type
                        Task { await refreshComments() }
                    }
                } label: {
                    Text(type.title)
                        .font(.system(size: 14, weight: sortType == type ? .semibold : .regular))
                        .foregroundColor(sortType == type ? accentColor : secondaryTextColor)
                        .padding(.vertical, 8)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
    }
    
    // MARK: - 点赞评论
    private func likeComment(_ comment: Comment, isLiked: Bool) async {
        guard authService.isLoggedIn() else { return }
        do {
            _ = try await musicService.likeComment(id: trackId, commentId: comment.commentId, like: isLiked)
        } catch {
            #if DEBUG
            print("Like comment error: \(error)")
            #endif
        }
    }
    
    // MARK: - 加载更多按钮
    private var loadMoreButton: some View {
        Button { Task { await loadMoreComments() } } label: {
            HStack {
                if isLoadingMore {
                    ProgressView().scaleEffect(0.8).tint(isStrangerTheme ? Color(red: 1.0, green: 0.2, blue: 0.3) : nil)
                } else {
                    Text("加载更多评论").font(.system(size: 14, weight: .medium))
                }
            }
            .foregroundColor(secondaryTextColor)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        }
        .disabled(isLoadingMore)
    }

    
    // MARK: - 评论输入框
    private var commentInputBar: some View {
        VStack(spacing: 0) {
            Divider()
            
            if let replyTo = replyingTo {
                HStack {
                    Text("回复 @\(replyTo.user.nickname)")
                        .font(.system(size: 12))
                        .foregroundColor(secondaryTextColor)
                    Spacer()
                    Button { replyingTo = nil } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(secondaryTextColor)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
            }
            
            HStack(spacing: 12) {
                TextField(replyingTo != nil ? "回复 @\(replyingTo!.user.nickname)" : "发一条友善的评论", text: $commentText)
                    .font(.system(size: 15))
                    .foregroundColor(textColor)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 20).fill(.ultraThinMaterial))
                    .focused($isInputFocused)
                
                Button { Task { await sendComment() } } label: {
                    if isSending {
                        ProgressView().scaleEffect(0.8).tint(.white).frame(width: 36, height: 36)
                    } else {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                    }
                }
                .background(Circle().fill(commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray : accentColor))
                .disabled(commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
        }
    }
    
    // MARK: - 发送评论
    private func sendComment() async {
        guard authService.isLoggedIn() else {
            showLoginAlert = true
            return
        }
        let content = commentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        
        isSending = true
        do {
            let response = try await musicService.sendComment(id: trackId, content: content, commentId: replyingTo?.commentId)
            await MainActor.run {
                if response.code == 200, let newComment = response.comment {
                    comments.insert(newComment, at: 0)
                    totalCount += 1
                }
                commentText = ""
                replyingTo = nil
                isInputFocused = false
                isSending = false
            }
        } catch {
            #if DEBUG
            print("Send comment error: \(error)")
            #endif
            await MainActor.run { isSending = false }
        }
    }
    
    // MARK: - 回复评论
    func replyToComment(_ comment: Comment) {
        replyingTo = comment
        isInputFocused = true
    }
    
    // MARK: - 刷新评论
    private func refreshComments() async {
        pageNo = 1
        cursor = nil
        comments = []
        await loadComments()
    }
    
    // MARK: - 加载评论
    private func loadComments() async {
        isLoading = true
        do {
            let response = try await musicService.getCommentsNew(id: trackId, sortType: sortType.rawValue, pageNo: pageNo, pageSize: pageSize, cursor: cursor)
            await MainActor.run {
                if let data = response.data {
                    comments = data.comments ?? []
                    totalCount = data.totalCount ?? 0
                    hasMore = data.hasMore ?? false
                    cursor = data.cursor
                    pageNo = 2
                }
                isLoading = false
            }
        } catch {
            #if DEBUG
            print("Load comments error: \(error)")
            #endif
            await MainActor.run { isLoading = false }
        }
    }
    
    // MARK: - 加载更多
    private func loadMoreComments() async {
        guard !isLoadingMore, hasMore else { return }
        isLoadingMore = true
        do {
            let response = try await musicService.getCommentsNew(id: trackId, sortType: sortType.rawValue, pageNo: pageNo, pageSize: pageSize, cursor: cursor)
            await MainActor.run {
                if let data = response.data {
                    comments.append(contentsOf: data.comments ?? [])
                    hasMore = data.hasMore ?? false
                    cursor = data.cursor
                    pageNo += 1
                }
                isLoadingMore = false
            }
        } catch {
            #if DEBUG
            print("Load more comments error: \(error)")
            #endif
            await MainActor.run { isLoadingMore = false }
        }
    }
}


// MARK: - 评论行
struct CommentRow: View {
    let comment: Comment
    let trackId: Int
    var isStrangerTheme: Bool = false
    var onReply: ((Comment) -> Void)? = nil
    var onLike: ((Comment, Bool) -> Void)? = nil
    
    @State private var isLiked = false
    @State private var likeCount: Int
    @State private var showReplies = false
    @State private var floorReplies: [FloorComment] = []
    @State private var isLoadingReplies = false
    @State private var hasMoreReplies = false
    @State private var replyTime = 0
    
    private let musicService = MusicService.shared
    
    init(comment: Comment, trackId: Int, isStrangerTheme: Bool = false, onReply: ((Comment) -> Void)? = nil, onLike: ((Comment, Bool) -> Void)? = nil) {
        self.comment = comment
        self.trackId = trackId
        self.isStrangerTheme = isStrangerTheme
        self.onReply = onReply
        self.onLike = onLike
        self._likeCount = State(initialValue: comment.likedCount ?? 0)
    }
    
    private var textColor: Color { isStrangerTheme ? .white : .primary }
    private var secondaryTextColor: Color { isStrangerTheme ? .white.opacity(0.6) : .secondary }
    private var accentColor: Color { isStrangerTheme ? Color(red: 0.2, green: 0.6, blue: 1.0) : .blue }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                // 头像
                CachedAsyncImage(url: URL(string: comment.user.avatarUrl ?? ""), targetSize: CGSize(width: 38, height: 38)) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Circle()
                        .fill(LinearGradient(colors: [Color(.systemGray4), Color(.systemGray5)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .overlay(Image(systemName: "person.fill").font(.system(size: 16)).foregroundColor(.white.opacity(0.8)))
                }
                .frame(width: 38, height: 38)
                .clipShape(Circle())
                
                VStack(alignment: .leading, spacing: 8) {
                    // 用户信息和点赞
                    HStack {
                        Text(comment.user.nickname)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(textColor)
                        Spacer()
                        Button {
                            isLiked.toggle()
                            likeCount += isLiked ? 1 : -1
                            onLike?(comment, isLiked)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: isLiked ? "heart.fill" : "heart")
                                    .font(.system(size: 12))
                                    .foregroundColor(isLiked ? .red : secondaryTextColor)
                                if likeCount > 0 {
                                    Text(formatLikeCount(likeCount))
                                        .font(.system(size: 11))
                                        .foregroundColor(secondaryTextColor)
                                }
                            }
                        }
                    }
                    
                    // 评论内容
                    Text(comment.content)
                        .font(.system(size: 14))
                        .foregroundColor(textColor)
                        .lineSpacing(4)
                    
                    // 回复区域
                    replySection
                    
                    // 时间、位置和回复按钮
                    HStack(spacing: 8) {
                        Text(comment.timeText)
                            .font(.system(size: 11))
                            .foregroundColor(secondaryTextColor.opacity(0.7))
                        if let location = comment.ipLocation?.location {
                            Text(location)
                                .font(.system(size: 11))
                                .foregroundColor(secondaryTextColor.opacity(0.7))
                        }
                        Spacer()
                        if onReply != nil {
                            Button { onReply?(comment) } label: {
                                Text("回复")
                                    .font(.system(size: 11))
                                    .foregroundColor(secondaryTextColor)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
    }
    
    // MARK: - 回复区域
    @ViewBuilder
    private var replySection: some View {
        if !showReplies {
            if comment.hasReplies {
                VStack(alignment: .leading, spacing: 6) {
                    if let replies = comment.beReplied, let firstReply = replies.first {
                        HStack(alignment: .top, spacing: 0) {
                            Text("@\(firstReply.user.nickname): ")
                                .font(.system(size: 13))
                                .foregroundColor(accentColor)
                            Text(firstReply.content)
                                .font(.system(size: 13))
                                .foregroundColor(secondaryTextColor)
                                .lineLimit(2)
                        }
                    }
                    Button { Task { await loadReplies() } } label: {
                        HStack(spacing: 4) {
                            if isLoadingReplies {
                                ProgressView().scaleEffect(0.6)
                            } else {
                                let count = comment.replyCount ?? (comment.beReplied?.count ?? 0)
                                Text(count > 0 ? "查看全部\(count)条回复" : "查看回复")
                                    .font(.system(size: 12))
                                Image(systemName: "chevron.down").font(.system(size: 10))
                            }
                        }
                        .foregroundColor(accentColor)
                    }
                    .disabled(isLoadingReplies)
                }
                .padding(10)
                .background(.ultraThinMaterial)
                .cornerRadius(8)
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                if floorReplies.isEmpty && isLoadingReplies {
                    HStack { Spacer(); ProgressView().scaleEffect(0.8); Spacer() }.padding(.vertical, 16)
                } else {
                    ForEach(floorReplies) { reply in
                        FloorReplyRow(reply: reply, isStrangerTheme: isStrangerTheme)
                        if reply.id != floorReplies.last?.id {
                            Divider().padding(.leading, 36)
                        }
                    }
                    if hasMoreReplies {
                        Button { Task { await loadMoreReplies() } } label: {
                            HStack {
                                if isLoadingReplies { ProgressView().scaleEffect(0.7) }
                                else {
                                    Text("查看更多回复").font(.system(size: 12))
                                    Image(systemName: "chevron.down").font(.system(size: 10))
                                }
                            }
                            .foregroundColor(accentColor)
                            .padding(.vertical, 10)
                        }
                        .disabled(isLoadingReplies)
                    }
                }
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showReplies = false }
                } label: {
                    HStack(spacing: 4) {
                        Text("收起").font(.system(size: 12))
                        Image(systemName: "chevron.up").font(.system(size: 10))
                    }
                    .foregroundColor(secondaryTextColor)
                    .padding(.vertical, 8)
                }
            }
            .padding(10)
            .background(.ultraThinMaterial)
            .cornerRadius(8)
        }
    }
    
    private func loadReplies() async {
        guard !isLoadingReplies else { return }
        isLoadingReplies = true
        do {
            let response = try await musicService.getCommentFloor(id: trackId, commentId: comment.commentId)
            await MainActor.run {
                if let data = response.data {
                    floorReplies = data.comments ?? []
                    hasMoreReplies = data.hasMore ?? false
                    replyTime = data.time ?? 0
                    withAnimation(.easeInOut(duration: 0.2)) { showReplies = true }
                }
                isLoadingReplies = false
            }
        } catch {
            await MainActor.run { isLoadingReplies = false }
        }
    }
    
    private func loadMoreReplies() async {
        guard !isLoadingReplies, hasMoreReplies else { return }
        isLoadingReplies = true
        do {
            let response = try await musicService.getCommentFloor(id: trackId, commentId: comment.commentId, time: replyTime)
            await MainActor.run {
                if let data = response.data {
                    floorReplies.append(contentsOf: data.comments ?? [])
                    hasMoreReplies = data.hasMore ?? false
                    replyTime = data.time ?? 0
                }
                isLoadingReplies = false
            }
        } catch {
            await MainActor.run { isLoadingReplies = false }
        }
    }
    
    private func formatLikeCount(_ count: Int) -> String {
        if count >= 10000 { return String(format: "%.1f万", Double(count) / 10000) }
        return "\(count)"
    }
}


// MARK: - 楼层回复行
struct FloorReplyRow: View {
    let reply: FloorComment
    var isStrangerTheme: Bool = false
    
    private var textColor: Color { isStrangerTheme ? .white : .primary }
    private var secondaryTextColor: Color { isStrangerTheme ? .white.opacity(0.6) : .secondary }
    private var accentColor: Color { isStrangerTheme ? Color(red: 0.2, green: 0.6, blue: 1.0) : .blue }
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            CachedAsyncImage(url: URL(string: reply.user.avatarUrl ?? ""), targetSize: CGSize(width: 24, height: 24)) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Circle().fill(Color(.systemGray4))
            }
            .frame(width: 24, height: 24)
            .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(reply.user.nickname)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(textColor)
                    if let beRepliedUser = reply.beRepliedUser {
                        Text("回复")
                            .font(.system(size: 12))
                            .foregroundColor(secondaryTextColor)
                        Text("@\(beRepliedUser.nickname)")
                            .font(.system(size: 12))
                            .foregroundColor(accentColor)
                    }
                }
                
                Text(reply.content)
                    .font(.system(size: 13))
                    .foregroundColor(textColor)
                    .lineSpacing(3)
                
                HStack(spacing: 6) {
                    Text(reply.timeText)
                        .font(.system(size: 10))
                        .foregroundColor(secondaryTextColor.opacity(0.7))
                    if let location = reply.ipLocation?.location {
                        Text(location)
                            .font(.system(size: 10))
                            .foregroundColor(secondaryTextColor.opacity(0.7))
                    }
                    Spacer()
                    if let likeCount = reply.likedCount, likeCount > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "heart").font(.system(size: 10))
                            Text("\(likeCount)").font(.system(size: 10))
                        }
                        .foregroundColor(secondaryTextColor)
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }
}

#Preview {
    CommentView(trackId: 1901371647, trackName: "测试歌曲")
        .environmentObject(ThemeManager.shared)
}
