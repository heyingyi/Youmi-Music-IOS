import SwiftUI

/// 定时关闭选项视图
struct SleepTimerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var themeManager: ThemeManager
    @StateObject private var sleepTimer = SleepTimerManager.shared
    @State private var showCustomPicker = false
    @State private var customMinutes: Int = 30
    
    // MARK: - 主题相关属性
    private var isStrangerTheme: Bool { themeManager.themeStyle == .strangerThings }
    private var accentColor: Color { isStrangerTheme ? Color(red: 1.0, green: 0.2, blue: 0.3) : .blue }
    
    // 预设时间选项
    private let presetMinutes = [15, 30, 45, 60, 90]
    
    var body: some View {
        NavigationView {
            List {
                // 当前状态
                if sleepTimer.isActive {
                    Section {
                        HStack {
                            Image(systemName: "moon.zzz.fill")
                                .foregroundColor(isStrangerTheme ? accentColor : .orange)
                            
                            if case .countdown = sleepTimer.mode {
                                Text("剩余 \(sleepTimer.formattedRemainingTime)")
                            } else if case .endOfTrack = sleepTimer.mode {
                                Text("播完当前歌曲后关闭")
                            }
                            
                            Spacer()
                        }
                    } header: {
                        Text("当前定时")
                    }
                }
                
                // 预设时间
                Section {
                    ForEach(presetMinutes, id: \.self) { minutes in
                        Button {
                            sleepTimer.setCountdown(minutes: minutes)
                            dismiss()
                        } label: {
                            HStack {
                                Text("\(minutes) 分钟")
                                    .foregroundColor(.primary)
                                Spacer()
                                if case .countdown(let m) = sleepTimer.mode, m == minutes {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(accentColor)
                                }
                            }
                        }
                    }
                } header: {
                    Text("定时时长")
                }
                
                // 特殊选项
                Section {
                    // 播完当前歌曲
                    Button {
                        sleepTimer.setEndOfTrack()
                        dismiss()
                    } label: {
                        HStack {
                            Text("播完当前歌曲")
                                .foregroundColor(.primary)
                            Spacer()
                            if case .endOfTrack = sleepTimer.mode {
                                Image(systemName: "checkmark")
                                    .foregroundColor(accentColor)
                            }
                        }
                    }
                    
                    // 自定义时间
                    Button {
                        showCustomPicker = true
                    } label: {
                        HStack {
                            Text("自定义时间")
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("更多选项")
                }
                
                // 关闭定时
                if sleepTimer.isActive {
                    Section {
                        Button(role: .destructive) {
                            sleepTimer.cancel()
                            dismiss()
                        } label: {
                            HStack {
                                Spacer()
                                Text("关闭定时")
                                Spacer()
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background {
                ThemedBackground()
                    .environmentObject(themeManager)
            }
            .immersiveNavigationChrome()
            .navigationTitle("定时关闭")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                    .foregroundColor(accentColor)
                }
            }
            .sheet(isPresented: $showCustomPicker) {
                CustomTimerPickerView(minutes: $customMinutes, accentColor: accentColor) {
                    sleepTimer.setCountdown(minutes: customMinutes)
                    showCustomPicker = false
                    dismiss()
                }
                .presentationDetents([.height(300)])
            }
        }
    }
}

/// 自定义时间选择器
struct CustomTimerPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var minutes: Int
    var accentColor: Color = .blue
    let onConfirm: () -> Void
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("选择时间")
                    .font(.headline)
                
                Picker("分钟", selection: $minutes) {
                    ForEach(1...180, id: \.self) { m in
                        Text("\(m) 分钟").tag(m)
                    }
                }
                .pickerStyle(.wheel)
                .frame(height: 150)
                
                Button {
                    onConfirm()
                } label: {
                    Text("确定")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(accentColor)
                        .cornerRadius(12)
                }
                .padding(.horizontal)
            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    SleepTimerView()
}
