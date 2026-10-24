import SwiftUI

struct ProfileCardView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.colorScheme) var colorScheme
    @State private var showLogoutAlert = false
    
    // MARK: - 主题相关属性
    private var isStrangerTheme: Bool { themeManager.isStrangerTheme }
    private var textColor: Color { themeManager.textColor }
    private var secondaryTextColor: Color { themeManager.secondaryTextColor }
    private var accentColor: Color { isStrangerTheme ? Color(red: 1.0, green: 0.2, blue: 0.3) : .red }

    
    var body: some View {
        ScrollView(showsIndicators: false) {
            if let profile = authViewModel.currentUser {
                VStack(spacing: 0) {
                    // 背景和头像区域
                    profileHeader(profile: profile)
                    
                    // 统计卡片
                    statsCard(profile: profile)
                        .padding(.top, -40)
                        .zIndex(1)
                    
                    // 详细信息
                    detailsSection(profile: profile)
                        .padding(.top, 16)
                    
                    // 退出登录
                    logoutSection
                        .padding(.top, 24)
                        .padding(.bottom, 100)
                }
            } else {
                loadingView
            }
        }
        .background {
            ThemedBackground()
                .environmentObject(themeManager)
        }
        .immersiveNavigationChrome()
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await authViewModel.fetchCurrentUser()
        }
        .task {
            if authViewModel.currentUser == nil {
                await authViewModel.fetchCurrentUser()
            }
        }
        .alert("确认退出", isPresented: $showLogoutAlert) {
            Button("取消", role: .cancel) {}
            Button("退出", role: .destructive) {
                Task { await authViewModel.logout() }
            }
        } message: {
            Text("确定要退出当前账号吗？")
        }
    }
    
    // MARK: - 加载视图
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text("加载中...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 400)
    }
    
    // MARK: - 头部区域
    private func profileHeader(profile: UserProfile) -> some View {
        ZStack(alignment: .bottom) {
            // 背景图
            GeometryReader { geo in
                if let bgUrl = profile.backgroundUrl, 
                   let url = URL(string: bgUrl.replacingOccurrences(of: "http://", with: "https://")) {
                    CachedAsyncImage(url: url) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geo.size.width, height: 280)
                            .clipped()
                    } placeholder: {
                        defaultGradient
                    }
                } else {
                    defaultGradient
                }
            }
            .frame(height: 280)
            
            // 渐变遮罩
            LinearGradient(
                colors: [.clear, .black.opacity(0.6)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 150)
            .offset(y: 65)
            
            // 用户信息
            VStack(spacing: 12) {
                // 头像
                avatarView(profile: profile)
                
                // 昵称和标识
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Text(profile.nickname)
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        
                        // 认证标识
                        if let vipType = profile.vipType, vipType > 0 {
                            vipBadge(type: vipType)
                        }
                    }
                    
                    // 等级和签名
                    HStack(spacing: 12) {
                        if let level = profile.level {
                            levelBadge(level: level)
                        }
                        
                        if let signature = profile.signature, !signature.isEmpty {
                            Text(signature)
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.8))
                                .lineLimit(1)
                        }
                    }
                }
            }
            .padding(.bottom, 60)
        }
    }
    
    // 默认渐变背景
    private var defaultGradient: some View {
        LinearGradient(
            colors: [Color.red, Color.orange.opacity(0.8)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .frame(height: 280)
    }
    
    // 头像视图
    private func avatarView(profile: UserProfile) -> some View {
        Group {
            if let avatarUrl = profile.avatarUrl, 
               let url = URL(string: avatarUrl.replacingOccurrences(of: "http://", with: "https://")) {
                CachedAsyncImage(url: url, targetSize: CGSize(width: 100, height: 100)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                        .overlay(ProgressView())
                }
            } else {
                Image(systemName: "person.circle.fill")
                    .resizable()
                    .foregroundColor(.white.opacity(0.8))
            }
        }
        .frame(width: 90, height: 90)
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(
                    LinearGradient(
                        colors: [.white, .white.opacity(0.5)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 3
                )
        )
        .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
    }
    
    // VIP 徽章
    private func vipBadge(type: Int) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "opticaldisc.fill")
                .font(.system(size: 10))
            Text("黑胶VIP")
                .font(.system(size: 10, weight: .bold))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [Color.black, Color.gray.opacity(0.8)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
        )
    }
    
    // 等级徽章
    private func levelBadge(level: Int) -> some View {
        Text("Lv.\(level)")
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.25))
            )
    }
    
    // MARK: - 统计卡片
    private func statsCard(profile: UserProfile) -> some View {
        HStack(spacing: 0) {
            statItem(value: profile.follows ?? 0, title: "关注")
            statDivider
            statItem(value: profile.followeds ?? 0, title: "粉丝")
            statDivider
            statItem(value: profile.eventCount ?? 0, title: "动态")
        }
        .padding(.vertical, 20)
        .glassEffectRounded(cornerRadius: 20)
        .shadow(color: isStrangerTheme ? accentColor.opacity(0.2) : .black.opacity(0.08), radius: 20, x: 0, y: 10)
        .overlay(
            Group {
                if isStrangerTheme {
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(accentColor.opacity(0.5), lineWidth: 1)
                }
            }
        )
        .padding(.horizontal, 20)
    }
    
    private var statDivider: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.2))
            .frame(width: 1, height: 40)
    }
    
    private func statItem(value: Int, title: String) -> some View {
        VStack(spacing: 6) {
            Text(formatNumber(value))
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(textColor)
            Text(title)
                .font(.caption)
                .foregroundColor(secondaryTextColor)
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - 详细信息区域
    private func detailsSection(profile: UserProfile) -> some View {
        VStack(spacing: 12) {
            // 音乐数据
            detailCard {
                VStack(spacing: 0) {
                    detailRow(
                        icon: "music.note.list",
                        iconColor: .red,
                        title: "歌单",
                        value: "\(profile.playlistCount ?? 0) 个"
                    )
                    Divider().padding(.leading, 50)
                    detailRow(
                        icon: "headphones",
                        iconColor: .purple,
                        title: "累计听歌",
                        value: "\(formatNumber(profile.listenSongs ?? 0)) 首"
                    )
                }
            }
            
            // 个人信息
            detailCard {
                VStack(spacing: 0) {
                    if let gender = profile.gender, gender > 0 {
                        detailRow(
                            icon: gender == 1 ? "person.fill" : "person.fill",
                            iconColor: gender == 1 ? .blue : .pink,
                            title: "性别",
                            value: profile.genderText
                        )
                        Divider().padding(.leading, 50)
                    }
                    
                    if let birthday = profile.birthday, birthday > 0 {
                        detailRow(
                            icon: "gift.fill",
                            iconColor: .orange,
                            title: "生日",
                            value: formatBirthday(birthday)
                        )
                    }
                }
            }
        }
        .padding(.horizontal, 20)
    }
    
    private func detailCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .glassEffectRounded(cornerRadius: 16)
            .overlay(
                Group {
                    if isStrangerTheme {
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(accentColor.opacity(0.3), lineWidth: 1)
                    }
                }
            )
    }
    
    private func detailRow(icon: String, iconColor: Color, title: String, value: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(isStrangerTheme ? accentColor : iconColor)
                .frame(width: 36, height: 36)
                .background(
                    Circle()
                        .fill(isStrangerTheme ? accentColor.opacity(0.2) : iconColor.opacity(0.12))
                )
            
            Text(title)
                .font(.subheadline)
                .foregroundColor(textColor)
            
            Spacer()
            
            Text(value)
                .font(.subheadline)
                .foregroundColor(secondaryTextColor)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
    
    // MARK: - 退出登录
    private var logoutSection: some View {
        Button(action: { showLogoutAlert = true }) {
            HStack {
                Spacer()
                Text("退出登录")
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(accentColor)
                Spacer()
            }
            .padding(.vertical, 16)
            .glassEffectRounded(cornerRadius: 16)
            .overlay(
                Group {
                    if isStrangerTheme {
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(accentColor.opacity(0.3), lineWidth: 1)
                    }
                }
            )
        }
        .padding(.horizontal, 20)
    }
    
    // MARK: - 辅助方法
    private func formatNumber(_ num: Int) -> String {
        if num >= 100000000 {
            return String(format: "%.1f亿", Double(num) / 100000000)
        } else if num >= 10000 {
            return String(format: "%.1f万", Double(num) / 10000)
        }
        return "\(num)"
    }
    
    private func formatBirthday(_ timestamp: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp / 1000))
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy 年 M 月 d 日"
        return formatter.string(from: date)
    }
}

#Preview {
    let viewModel = AuthViewModel()
    viewModel.currentUser = UserProfile(
        userId: 12345,
        nickname: "Max7-Days",
        avatarUrl: "https://p2.music.126.net/WM3pJlR4PDnEjxwmVUpR9Q==/109951170070202266.jpg",
        backgroundUrl: nil,
        signature: "world",
        gender: 1,
        birthday: 631123200000,
        city: nil,
        province: nil,
        followed: false,
        followeds: 18,
        follows: 5,
        playlistCount: 3,
        eventCount: 1,
        vipType: 11,
        level: 10,
        listenSongs: 22548
    )
    return NavigationStack {
        ProfileCardView()
            .environmentObject(viewModel)
    }
}
