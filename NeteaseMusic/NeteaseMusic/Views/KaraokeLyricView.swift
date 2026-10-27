import SwiftUI
import UIKit

// MARK: - ============================================
// MARK: - 高性能逐字歌词系统（Apple Music 风格）
// MARK: - 核心：每个字只启动一次 CABasicAnimation
// MARK: - ============================================

// MARK: - SwiftUI 包装器
struct KaraokeLyricsView: View {
    let lines: [YrcLine]
    let currentTime: Double
    let showTranslation: Bool
    let hasTranslation: Bool
    let onToggleTranslation: () -> Void
    let onSeek: (Double) -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            AppleMusicKaraokeView(
                lines: lines,
                showTranslation: showTranslation,
                onSeek: onSeek
            )
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .white, location: 0.08),
                        .init(color: .white, location: 0.85),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }
}

// MARK: - UIViewRepresentable
struct AppleMusicKaraokeView: UIViewRepresentable {
    let lines: [YrcLine]
    let showTranslation: Bool
    let onSeek: (Double) -> Void
    
    func makeUIView(context: Context) -> AppleMusicKaraokeScrollView {
        let view = AppleMusicKaraokeScrollView()
        view.onSeek = onSeek
        return view
    }
    
    func updateUIView(_ uiView: AppleMusicKaraokeScrollView, context: Context) {
        uiView.configure(lines: lines, showTranslation: showTranslation)
    }
}

// MARK: - 歌词滚动容器
class AppleMusicKaraokeScrollView: UIView {
    var onSeek: ((Double) -> Void)?
    
    private var scrollView: UIScrollView!
    private var contentView: UIView!
    private var lineViews: [AppleMusicLineView] = []
    private var lines: [YrcLine] = []
    private var showTranslation: Bool = true
    
    private var displayLink: CADisplayLink?
    private var currentLineIndex: Int = -1
    private var lastScrollTime: Double = 0
    /// lineTapped 后短暂锁定行索引，防止旧时间把它跳回去
    private var lineLockedUntil: Double = 0
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }
    
    private func setupUI() {
        backgroundColor = .clear
        
        scrollView = UIScrollView()
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.decelerationRate = .fast
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)
        
        contentView = UIView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentView)
        
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            
            contentView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor)
        ])
        
        startDisplayLink()
    }
    
    deinit {
        stopDisplayLink()
    }
    
    private func startDisplayLink() {
        guard displayLink == nil else { return }
        displayLink = CADisplayLink(target: self, selector: #selector(tick))
        displayLink?.preferredFrameRateRange = CAFrameRateRange(minimum: 80, maximum: 120, preferred: 120)
        displayLink?.add(to: .main, forMode: .common)
    }
    
    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }
    
    @objc private func tick() {
        let player = AudioPlayer.shared
        guard player.isPlaying else {
            // 暂停时：冻结当前行动画
            if currentLineIndex >= 0 && currentLineIndex < lineViews.count {
                lineViews[currentLineIndex].pauseAnimations()
            }
            return
        }
        
        let time = player.realtimePlaybackTime
        
        // 行索引锁定期间（刚点击跳转，等待 AVPlayer seek 完成）
        // 不更新行索引，也不用旧时间同步逐字进度
        let locked = CACurrentMediaTime() < lineLockedUntil
        
        if !locked {
            updateCurrentLine(time: time)
        }
        
        // 更新当前行的逐字进度
        if currentLineIndex >= 0 && currentLineIndex < lineViews.count {
            if locked {
                // 锁定期间不同步，保持 lineTapped 设置的初始状态
            } else {
                lineViews[currentLineIndex].syncTime(time)
            }
        }
    }
    
    func configure(lines: [YrcLine], showTranslation: Bool) {
        let changed = lines.count != self.lines.count
        self.lines = lines
        self.showTranslation = showTranslation
        
        if changed {
            rebuildViews()
        }
    }
    
    private func rebuildViews() {
        lineViews.forEach { $0.removeFromSuperview() }
        lineViews.removeAll()
        contentView.constraints.forEach { contentView.removeConstraint($0) }
        
        guard !lines.isEmpty else { return }
        
        var prev: UIView?
        let topPad: CGFloat = 180
        let bottomPad: CGFloat = 180
        let spacing: CGFloat = 28
        let hPad: CGFloat = 24
        
        for (i, line) in lines.enumerated() {
            let v = AppleMusicLineView(line: line, showTranslation: showTranslation)
            v.translatesAutoresizingMaskIntoConstraints = false
            v.tag = i
            contentView.addSubview(v)
            
            let tap = UITapGestureRecognizer(target: self, action: #selector(lineTapped(_:)))
            v.addGestureRecognizer(tap)
            v.isUserInteractionEnabled = true
            
            NSLayoutConstraint.activate([
                v.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: hPad),
                v.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -hPad),
                v.heightAnchor.constraint(equalToConstant: v.estimatedHeight)
            ])
            
            if let p = prev {
                v.topAnchor.constraint(equalTo: p.bottomAnchor, constant: spacing).isActive = true
            } else {
                v.topAnchor.constraint(equalTo: contentView.topAnchor, constant: topPad).isActive = true
            }
            
            lineViews.append(v)
            prev = v
        }
        
        if let last = lineViews.last {
            last.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -bottomPad).isActive = true
        }
        
        currentLineIndex = -1
    }
    
    @objc private func lineTapped(_ g: UITapGestureRecognizer) {
        guard let v = g.view else { return }
        let i = v.tag
        if i < lines.count {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            
            let seekTime = lines[i].startTime
            
            #if DEBUG
            print("🎵 [lineTapped] 点击第\(i)行, seekTime=\(seekTime)s, 歌词: \(lines[i].text.prefix(20))")
            #endif
            
            // 锁定行索引 0.5 秒，防止 tick 用旧的 realtimePlaybackTime 把行跳回去
            lineLockedUntil = CACurrentMediaTime() + 0.5
            
            // 立即重置旧行、激活新行
            let oldIdx = currentLineIndex
            currentLineIndex = i
            
            if oldIdx >= 0 && oldIdx < lineViews.count {
                lineViews[oldIdx].setActive(false, distance: abs(oldIdx - i))
            }
            lineViews[i].setActive(true, distance: 0)
            // 用 seek 目标时间同步逐字进度（所有字进度归零）
            lineViews[i].syncTime(seekTime)
            
            scrollTo(i)
            
            onSeek?(seekTime)
        }
    }
    
    private func updateCurrentLine(time: Double) {
        guard !lines.isEmpty else { return }
        
        var newIdx = 0
        for (i, line) in lines.enumerated().reversed() {
            if time >= line.startTime {
                newIdx = i
                break
            }
        }
        
        if newIdx != currentLineIndex {
            let oldIdx = currentLineIndex
            currentLineIndex = newIdx
            
            if oldIdx >= 0 && oldIdx < lineViews.count {
                lineViews[oldIdx].setActive(false, distance: abs(oldIdx - newIdx))
            }
            if newIdx >= 0 && newIdx < lineViews.count {
                lineViews[newIdx].setActive(true, distance: 0)
            }
            for i in max(0, newIdx - 4)...min(lineViews.count - 1, newIdx + 4) {
                if i != oldIdx && i != newIdx {
                    lineViews[i].setActive(false, distance: abs(i - newIdx))
                }
            }
            
            let now = CACurrentMediaTime()
            if now - lastScrollTime > 0.3 {
                lastScrollTime = now
                scrollTo(newIdx)
            }
        }
    }
    
    private func scrollTo(_ idx: Int) {
        guard idx >= 0 && idx < lineViews.count else { return }
        layoutIfNeeded()
        
        let v = lineViews[idx]
        let h = scrollView.bounds.height
        // Apple Music 风格：当前歌词偏上 1/3 位置
        var y = v.frame.midY - h * 0.35
        y = max(0, min(y, scrollView.contentSize.height - h))
        
        UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0) {
            self.scrollView.contentOffset = CGPoint(x: 0, y: y)
        }
    }
}


// MARK: - 单行歌词视图
class AppleMusicLineView: UIView {
    private let line: YrcLine
    private let showTranslation: Bool
    private let fontSize: CGFloat
    private var wordViews: [AppleMusicWordView] = []
    private var translationLabel: UILabel?
    private var isActive: Bool = false
    
    var estimatedHeight: CGFloat {
        showTranslation && line.translation != nil ? 80 : 40
    }
    
    init(line: YrcLine, showTranslation: Bool) {
        self.line = line
        self.showTranslation = showTranslation
        self.fontSize = AppleMusicLineView.fittedFontSize(for: line, base: 24, maxWidth: UIScreen.main.bounds.width - 48)
        super.init(frame: .zero)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError()
    }
    
    private func setupUI() {
        backgroundColor = .clear
        
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        addSubview(container)
        
        var totalW: CGFloat = 0
        
        for word in line.words {
            let wv = AppleMusicWordView(word: word, fontSize: fontSize)
            totalW += wv.wordWidth
            wordViews.append(wv)
        }
        
        var x: CGFloat = 0
        for wv in wordViews {
            wv.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(wv)
            
            NSLayoutConstraint.activate([
                wv.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: x),
                wv.topAnchor.constraint(equalTo: container.topAnchor),
                wv.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                wv.widthAnchor.constraint(equalToConstant: wv.wordWidth)
            ])
            x += wv.wordWidth
        }
        
        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: leadingAnchor),
            container.topAnchor.constraint(equalTo: topAnchor),
            container.widthAnchor.constraint(equalToConstant: totalW),
            container.heightAnchor.constraint(equalToConstant: fontSize + 8)
        ])
        
        if showTranslation, let trans = line.translation {
            let lbl = UILabel()
            lbl.text = trans
            lbl.font = .systemFont(ofSize: 15)
            lbl.textColor = .white.withAlphaComponent(0.5)
            lbl.textAlignment = .left
            lbl.numberOfLines = 2
            lbl.lineBreakMode = .byTruncatingTail
            lbl.translatesAutoresizingMaskIntoConstraints = false
            addSubview(lbl)
            translationLabel = lbl
            
            NSLayoutConstraint.activate([
                lbl.topAnchor.constraint(equalTo: container.bottomAnchor, constant: 6),
                lbl.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
                lbl.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8)
            ])
        }
        
        alpha = 0.4
    }

    private static func fittedFontSize(for line: YrcLine, base: CGFloat, maxWidth: CGFloat) -> CGFloat {
        guard maxWidth > 0 else { return base }
        let font = UIFont.systemFont(ofSize: base, weight: .bold)
        let totalW = line.words.reduce(CGFloat(0)) { acc, word in
            let text = word.text as NSString
            let size = text.size(withAttributes: [.font: font])
            return acc + ceil(size.width) + 1
        }
        if totalW <= maxWidth {
            return base
        }
        let scale = maxWidth / max(totalW, 1)
        return max(12, floor(base * scale))
    }
    
    func syncTime(_ time: Double) {
        guard isActive else { return }
        
        for (i, word) in line.words.enumerated() {
            wordViews[i].updateWithTime(time, word: word)
        }
    }
    
    func pauseAnimations() {
        for wv in wordViews {
            wv.pauseAnimation()
        }
    }
    
    func setActive(_ active: Bool, distance: Int) {
        isActive = active
        
        let a: CGFloat = active ? 1.0 : (distance <= 1 ? 0.5 : 0.3)
        let s: CGFloat = active ? 1.05 : 1.0
        
        UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0) {
            self.alpha = a
            self.transform = CGAffineTransform(scaleX: s, y: s)
        }
        
        UIView.animate(withDuration: 0.3) {
            self.translationLabel?.alpha = active ? 0.7 : 0.4
        }
        
        if !active {
            for wv in wordViews {
                wv.reset()
            }
        }
    }
}

// MARK: - 单字视图（核心：从左到右填充动画）
class AppleMusicWordView: UIView {
    let wordWidth: CGFloat
    
    private let baseLayer: CATextLayer
    private let highlightLayer: CATextLayer
    private let maskLayer: CALayer
    private let layerHeight: CGFloat
    
    // 动画状态
    private var animationStarted = false
    private var animationWordId: Double = -1
    private var lastSyncTime: Double = 0
    
    init(word: YrcWord, fontSize: CGFloat) {
        let font = UIFont.systemFont(ofSize: fontSize, weight: .bold)
        let text = word.text as NSString
        let size = text.size(withAttributes: [.font: font])
        wordWidth = ceil(size.width) + 1
        layerHeight = size.height + 8
        
        // 底层文字（灰色）
        baseLayer = CATextLayer()
        baseLayer.string = word.text
        baseLayer.font = CGFont(font.fontName as CFString)
        baseLayer.fontSize = fontSize
        baseLayer.foregroundColor = UIColor.white.withAlphaComponent(0.4).cgColor
        baseLayer.alignmentMode = .left
        baseLayer.contentsScale = UIScreen.main.scale
        baseLayer.frame = CGRect(x: 0, y: 4, width: wordWidth, height: size.height)
        
        // 高亮文字（白色）
        highlightLayer = CATextLayer()
        highlightLayer.string = word.text
        highlightLayer.font = CGFont(font.fontName as CFString)
        highlightLayer.fontSize = fontSize
        highlightLayer.foregroundColor = UIColor.white.cgColor
        highlightLayer.alignmentMode = .left
        highlightLayer.contentsScale = UIScreen.main.scale
        highlightLayer.frame = CGRect(x: 0, y: 4, width: wordWidth, height: size.height)
        
        // 遮罩层 - anchorPoint 设为左边，这样宽度变化时从左向右扩展
        maskLayer = CALayer()
        maskLayer.backgroundColor = UIColor.white.cgColor
        maskLayer.anchorPoint = CGPoint(x: 0, y: 0.5)  // 锚点在左边
        maskLayer.position = CGPoint(x: 0, y: layerHeight / 2)  // 位置在左边
        maskLayer.bounds = CGRect(x: 0, y: 0, width: 0, height: layerHeight)
        
        super.init(frame: .zero)
        
        layer.addSublayer(baseLayer)
        layer.addSublayer(highlightLayer)
        highlightLayer.mask = maskLayer
    }
    
    required init?(coder: NSCoder) {
        fatalError()
    }
    
    func updateWithTime(_ time: Double, word: YrcWord) {
        if time < word.startTime {
            if animationStarted && animationWordId == word.startTime {
                reset()
            }
            setProgressImmediate(0)
        } else if time >= word.endTime {
            maskLayer.removeAllAnimations()
            setProgressImmediate(1)
            animationStarted = false
        } else {
            // 当前正在播放这个字
            let progress = (time - word.startTime) / word.duration
            let expectedWidth = wordWidth * CGFloat(progress)
            
            if !animationStarted || animationWordId != word.startTime {
                // 首次进入：启动动画
                startAnimation(word: word, currentTime: time)
                lastSyncTime = time
            } else {
                // 已有动画：定期校准，防止 CAAnimation 和音频时钟漂移
                // 每 0.3 秒校准一次
                if time - lastSyncTime > 0.3 {
                    lastSyncTime = time
                    // 获取当前 mask 的实际宽度（presentation layer）
                    let presentationWidth = maskLayer.presentation()?.bounds.width ?? 0
                    let drift = abs(presentationWidth - expectedWidth)
                    // 漂移超过 2pt 时重新启动动画校准
                    if drift > 2.0 {
                        startAnimation(word: word, currentTime: time)
                    }
                }
            }
        }
    }
    
    private func startAnimation(word: YrcWord, currentTime: Double) {
        animationStarted = true
        animationWordId = word.startTime
        
        maskLayer.removeAllAnimations()
        
        let elapsed = currentTime - word.startTime
        let progress = elapsed / word.duration
        let currentWidth = wordWidth * CGFloat(progress)
        let remainingTime = word.endTime - currentTime
        
        // 设置最终状态
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        maskLayer.bounds = CGRect(x: 0, y: 0, width: wordWidth, height: layerHeight)
        CATransaction.commit()
        
        // 动画 bounds.size.width，因为 anchorPoint 在左边，所以会从左向右扩展
        let anim = CABasicAnimation(keyPath: "bounds.size.width")
        anim.fromValue = currentWidth
        anim.toValue = wordWidth
        anim.duration = max(0.01, remainingTime)
        anim.timingFunction = CAMediaTimingFunction(name: .linear)
        anim.fillMode = .forwards
        anim.isRemovedOnCompletion = false
        
        maskLayer.add(anim, forKey: "fill")
    }
    
    private func setProgressImmediate(_ progress: Double) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        maskLayer.bounds = CGRect(x: 0, y: 0, width: wordWidth * CGFloat(progress), height: layerHeight)
        CATransaction.commit()
    }
    
    func reset() {
        maskLayer.removeAllAnimations()
        setProgressImmediate(0)
        animationStarted = false
        animationWordId = -1
        lastSyncTime = 0
    }
    
    func pauseAnimation() {
        guard animationStarted else { return }
        // 暂停时：获取当前进度并设为静态，移除动画
        let currentWidth = maskLayer.presentation()?.bounds.width ?? maskLayer.bounds.width
        maskLayer.removeAllAnimations()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        maskLayer.bounds = CGRect(x: 0, y: 0, width: currentWidth, height: layerHeight)
        CATransaction.commit()
        // 标记需要重新启动动画
        animationStarted = false
    }
    
    func resumeIfPaused() {
        // 不需要特殊处理，下次 updateWithTime 会自动重新启动动画
    }
}

// MARK: - 当前歌词预览（底部显示）- 高性能 UIKit 实现
struct KaraokePreviewView: UIViewRepresentable {
    let line: YrcLine?
    let currentTime: Double  // 这个参数现在只用于触发更新，实际时间从 AudioPlayer 获取
    
    func makeUIView(context: Context) -> KaraokePreviewUIView {
        return KaraokePreviewUIView()
    }
    
    func updateUIView(_ uiView: KaraokePreviewUIView, context: Context) {
        uiView.configure(line: line)
    }
}

class KaraokePreviewUIView: UIView {
    private var wordViews: [PreviewWordUIView] = []
    private var containerView: UIView!
    private var displayLink: CADisplayLink?
    private var currentLine: YrcLine?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }
    
    private func setupUI() {
        backgroundColor = .clear
        
        containerView = UIView()
        containerView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(containerView)
        
        NSLayoutConstraint.activate([
            containerView.centerXAnchor.constraint(equalTo: centerXAnchor),
            containerView.centerYAnchor.constraint(equalTo: centerYAnchor),
            containerView.heightAnchor.constraint(equalToConstant: 20)
        ])
        
        startDisplayLink()
    }
    
    deinit {
        stopDisplayLink()
    }
    
    private func startDisplayLink() {
        guard displayLink == nil else { return }
        displayLink = CADisplayLink(target: self, selector: #selector(tick))
        displayLink?.preferredFrameRateRange = CAFrameRateRange(minimum: 80, maximum: 120, preferred: 120)
        displayLink?.add(to: .main, forMode: .common)
    }
    
    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }
    
    @objc private func tick() {
        guard let line = currentLine else { return }
        let player = AudioPlayer.shared
        guard player.isPlaying else { return }
        
        let time = player.realtimePlaybackTime
        
        for (i, word) in line.words.enumerated() where i < wordViews.count {
            wordViews[i].updateWithTime(time, word: word)
        }
    }
    
    func configure(line: YrcLine?) {
        guard line?.id != currentLine?.id else { return }
        currentLine = line
        
        // 清除旧视图
        wordViews.forEach { $0.removeFromSuperview() }
        wordViews.removeAll()
        
        guard let line = line else { return }
        
        let fontSize: CGFloat = 15
        var totalWidth: CGFloat = 0
        
        for word in line.words {
            let wv = PreviewWordUIView(word: word, fontSize: fontSize)
            totalWidth += wv.wordWidth
            wordViews.append(wv)
        }
        
        // 更新容器宽度
        for constraint in containerView.constraints where constraint.firstAttribute == .width {
            constraint.isActive = false
        }
        containerView.widthAnchor.constraint(equalToConstant: totalWidth).isActive = true
        
        // 布局
        var x: CGFloat = 0
        for wv in wordViews {
            wv.translatesAutoresizingMaskIntoConstraints = false
            containerView.addSubview(wv)
            
            NSLayoutConstraint.activate([
                wv.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: x),
                wv.topAnchor.constraint(equalTo: containerView.topAnchor),
                wv.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
                wv.widthAnchor.constraint(equalToConstant: wv.wordWidth)
            ])
            x += wv.wordWidth
        }
    }
}

class PreviewWordUIView: UIView {
    let wordWidth: CGFloat
    
    private let baseLayer: CATextLayer
    private let highlightLayer: CATextLayer
    private let maskLayer: CALayer
    private let layerHeight: CGFloat = 20
    
    private var animationStarted = false
    private var animationWordId: Double = -1
    
    init(word: YrcWord, fontSize: CGFloat) {
        let font = UIFont.systemFont(ofSize: fontSize, weight: .regular)
        let text = word.text as NSString
        let size = text.size(withAttributes: [.font: font])
        wordWidth = ceil(size.width) + 1
        
        baseLayer = CATextLayer()
        baseLayer.string = word.text
        baseLayer.font = CGFont(font.fontName as CFString)
        baseLayer.fontSize = fontSize
        baseLayer.foregroundColor = UIColor.white.withAlphaComponent(0.5).cgColor
        baseLayer.alignmentMode = .left
        baseLayer.contentsScale = UIScreen.main.scale
        baseLayer.frame = CGRect(x: 0, y: 2, width: wordWidth, height: size.height)
        
        highlightLayer = CATextLayer()
        highlightLayer.string = word.text
        highlightLayer.font = CGFont(font.fontName as CFString)
        highlightLayer.fontSize = fontSize
        highlightLayer.foregroundColor = UIColor.white.cgColor
        highlightLayer.alignmentMode = .left
        highlightLayer.contentsScale = UIScreen.main.scale
        highlightLayer.frame = CGRect(x: 0, y: 2, width: wordWidth, height: size.height)
        
        maskLayer = CALayer()
        maskLayer.backgroundColor = UIColor.white.cgColor
        maskLayer.anchorPoint = CGPoint(x: 0, y: 0.5)
        maskLayer.position = CGPoint(x: 0, y: layerHeight / 2)
        maskLayer.bounds = CGRect(x: 0, y: 0, width: 0, height: layerHeight)
        
        super.init(frame: .zero)
        
        layer.addSublayer(baseLayer)
        layer.addSublayer(highlightLayer)
        highlightLayer.mask = maskLayer
    }
    
    required init?(coder: NSCoder) {
        fatalError()
    }
    
    func updateWithTime(_ time: Double, word: YrcWord) {
        if time < word.startTime {
            if animationStarted { reset() }
            setProgressImmediate(0)
        } else if time >= word.endTime {
            maskLayer.removeAllAnimations()
            setProgressImmediate(1)
            animationStarted = false
        } else {
            if !animationStarted || animationWordId != word.startTime {
                startAnimation(word: word, currentTime: time)
            }
        }
    }
    
    private func startAnimation(word: YrcWord, currentTime: Double) {
        animationStarted = true
        animationWordId = word.startTime
        
        maskLayer.removeAllAnimations()
        
        let elapsed = currentTime - word.startTime
        let progress = elapsed / word.duration
        let currentWidth = wordWidth * CGFloat(progress)
        let remainingTime = word.endTime - currentTime
        
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        maskLayer.bounds = CGRect(x: 0, y: 0, width: wordWidth, height: layerHeight)
        CATransaction.commit()
        
        let anim = CABasicAnimation(keyPath: "bounds.size.width")
        anim.fromValue = currentWidth
        anim.toValue = wordWidth
        anim.duration = max(0.01, remainingTime)
        anim.timingFunction = CAMediaTimingFunction(name: .linear)
        anim.fillMode = .forwards
        anim.isRemovedOnCompletion = false
        
        maskLayer.add(anim, forKey: "fill")
    }
    
    private func setProgressImmediate(_ progress: Double) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        maskLayer.bounds = CGRect(x: 0, y: 0, width: wordWidth * CGFloat(progress), height: layerHeight)
        CATransaction.commit()
    }
    
    func reset() {
        maskLayer.removeAllAnimations()
        setProgressImmediate(0)
        animationStarted = false
        animationWordId = -1
    }
}

#Preview {
    ZStack {
        Color.black
        Text("Apple Music 风格逐字歌词")
            .foregroundColor(.white)
    }
}
