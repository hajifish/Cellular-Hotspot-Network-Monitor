import AppKit

// MARK: - 可测纯逻辑（浮窗实现与自测共用同一份映射，非平行副本）

/// 浮窗可见性状态机（脱离真窗口可测）：面板以同一实例驱动 isPanelVisible 语义，
/// 自测直接驱动该模型断言 show / dismiss / 二次 show 的状态翻转。
struct AlertBannerVisibility: Equatable {
    enum Phase: Equatable {
        case hidden      // 未展示 / 已完全收起
        case shown       // 展示中（接受悬停暂停倒计时）
        case fadingOut   // 淡出动画进行中（不再接受暂停，重复 dismiss 幂等）
    }

    private(set) var phase: Phase = .hidden

    /// 横幅是否在屏上（展示中或淡出中；orderOut 之后为 false）
    var isPanelVisible: Bool { phase != .hidden }

    /// 是否接受悬停暂停倒计时（淡出中不接受，避免复活已收起的横幅）
    var acceptsHoverPause: Bool { phase == .shown }

    mutating func show() { phase = .shown }
    mutating func beginFadeOut() { if phase == .shown { phase = .fadingOut } }
    mutating func finishDismiss() { phase = .hidden }
}

/// 触发计时器编排的事件
enum AlertBannerTimerEvent {
    case show          // 展示（含再次展示）：无条件重置旧计时器，连续告警不泄漏 / 不双计时
    case hoverStarted  // 鼠标进入：暂停倒计时
    case hoverEnded    // 鼠标离开：恢复倒计时
    case dismissed     // 关闭（点击 / 淡出完成）
}

/// 对自动关闭计时器的编排指令（面板把它落到真实 NSTimer 上；自测直接断言指令序列，
/// 规避裸二进制进程构造真计时器不稳定的问题）
enum AlertBannerTimerDirective: Equatable {
    case none
    case invalidate                  // 仅取消现有计时器（悬停暂停 / 关闭清理）
    case restart(TimeInterval)       // 先取消再重新调度（show / 移出恢复）
}

// MARK: - 告警浮动横幅

/// 应用内告警浮动横幅：全屏 / 专注模式下系统通知被抑制时的应用内兜底（设计文档 2026-11-26 方案 B）。
/// - `.nonactivatingPanel`：弹出与点击都不夺当前应用（如全屏游戏）的焦点
/// - `.floating` + `.canJoinAllSpaces + .fullScreenAuxiliary`：横跨 Space，全屏应用所在空间也可见
/// - `hidesOnDeactivate = false`：本应用是 LSUIElement accessory，横幅绝不因失活隐藏
/// - 10 秒自动淡出；悬停暂停倒计时、移出恢复；点击回调 onClick 并淡出关闭
/// 自测约束：裸二进制进程不构造真 NSPanel / 真计时器——可测逻辑已抽为
/// `bannerFrame`（纯函数）、`displayDuration`（常量）、`AlertBannerVisibility` /
/// `timerDirective`（状态机与编排映射，本类真实使用）；面板真身由打包目检覆盖。
@MainActor
final class AlertBannerPanel: NSPanel {
    /// 横幅固定尺寸（AppIcon + 标题一行 + 正文两行内的深色卡片）
    static let bannerSize = NSSize(width: 360, height: 76)
    /// 自动淡出前的展示时长（nonisolated：bannerFrame / timerDirective 纯函数与自测可直接引用）
    nonisolated static let displayDuration: TimeInterval = 10
    /// 淡出动画时长
    static let fadeOutDuration: TimeInterval = 0.25
    /// 顶部留白：横幅顶边距屏幕顶边 30pt（避开菜单栏遮挡：.mainMenu 层级 24 高于 .floating，
    /// 桌面空间下横幅顶边距 < 24 会被菜单栏盖住；全屏空间菜单栏隐藏不受影响。bannerFrame 语义）
    nonisolated static let topGap: CGFloat = 30

    /// 顶部居中布局（纯函数，可测）：水平居中，y = screenFrame.maxY − 30 − height
    nonisolated static func bannerFrame(screenFrame: NSRect, bannerSize: NSSize) -> NSRect {
        NSRect(x: screenFrame.midX - bannerSize.width / 2,
               y: screenFrame.maxY - topGap - bannerSize.height,
               width: bannerSize.width,
               height: bannerSize.height)
    }

    /// 事件 → 计时器指令（纯映射，可测）。show 无条件 restart：
    /// 连续两次告警时旧计时器随新 show 一并作废，绝不出现双计时 / 泄漏。
    nonisolated static func timerDirective(for event: AlertBannerTimerEvent,
                                           hasLiveTimer: Bool) -> AlertBannerTimerDirective {
        switch event {
        case .show, .hoverEnded:
            return .restart(displayDuration)
        case .hoverStarted, .dismissed:
            return hasLiveTimer ? .invalidate : .none
        }
    }

    private var visibility = AlertBannerVisibility()
    private var autoDismissTimer: Timer?
    private var isHovering = false
    /// show 递增的代际号：淡出完成回调据此识别自己是否已被新 show 取代
    private var fadeGeneration = 0
    private var onClickHandler: (() -> Void)?
    private let bannerContentView: AlertBannerContentView
    private let titleLabel: NSTextField
    private let bodyLabel: NSTextField

    init() {
        bannerContentView = AlertBannerContentView(frame: NSRect(origin: .zero, size: Self.bannerSize))
        titleLabel = NSTextField(labelWithString: "")
        bodyLabel = NSTextField(labelWithString: "")
        super.init(contentRect: NSRect(origin: .zero, size: Self.bannerSize),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        level = .floating
        // canJoinAllSpaces：跟随当前 Space；fullScreenAuxiliary：全屏空间也允许显示
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false // NSPanel 默认 true——失活即隐藏会废掉全屏兜底
        isReleasedWhenClosed = false
        ignoresMouseEvents = false
        appearance = NSAppearance(named: .darkAqua)
        self.contentView = bannerContentView
        bannerContentView.onClick = { [weak self] in self?.handleTap() }
        bannerContentView.onHoverChange = { [weak self] entered in self?.handleHoverChanged(entered) }
        layoutContent(in: bannerContentView)
    }

    /// 展示横幅（含再次展示：更新文案、重置旧计时器、复位透明度后重新置顶）。
    /// 不激活应用（orderFrontRegardless）。
    func show(title: String, body: String, onClick: @escaping () -> Void) {
        onClickHandler = onClick
        titleLabel.stringValue = title
        bodyLabel.stringValue = body
        fadeGeneration += 1 // 在飞的淡出回调作废
        isHovering = false
        bannerContentView.clearHoverState()
        visibility.show()
        applyTimerDirective(.show) // show 前重置旧计时器（restart 语义）
        setFrame(Self.bannerFrame(screenFrame: NSScreen.main?.frame
                                            ?? NSRect(x: 0, y: 0, width: 1280, height: 800),
                                  bannerSize: Self.bannerSize),
                 display: false)
        // 零时长动画复位透明度，终结上一轮可能仍在飞的淡出
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            context.allowsImplicitAnimation = false
            self.animator().alphaValue = 1
        }
        orderFrontRegardless()
    }

    /// 关闭横幅（淡出后 orderOut）。幂等：未展示 / 已在淡出时不动相位，仅清计时器。
    func dismiss() {
        applyTimerDirective(.dismissed)
        guard visibility.phase == .shown else { return }
        beginFadeOut()
    }

    // MARK: - 内部驱动

    private func applyTimerDirective(_ event: AlertBannerTimerEvent) {
        let directive = Self.timerDirective(for: event, hasLiveTimer: autoDismissTimer != nil)
        switch directive {
        case .none:
            break
        case .invalidate:
            cancelAutoDismissTimer()
        case .restart(let interval):
            cancelAutoDismissTimer()
            autoDismissTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) {
                [weak self] _ in
                // scheduledTimer 挂在主 runloop，回调必在主线程；横跨隔离边界兜一层
                MainActor.assumeIsolated { self?.beginFadeOut() }
            }
        }
    }

    private func cancelAutoDismissTimer() {
        autoDismissTimer?.invalidate()
        autoDismissTimer = nil
    }

    private func handleTap() {
        onClickHandler?()
        dismiss()
    }

    private func handleHoverChanged(_ entered: Bool) {
        if entered {
            guard visibility.acceptsHoverPause, !isHovering else { return }
            isHovering = true
            applyTimerDirective(.hoverStarted)
        } else {
            guard isHovering else { return }
            isHovering = false
            guard visibility.acceptsHoverPause else { return } // 淡出中不复活倒计时
            applyTimerDirective(.hoverEnded)
        }
    }

    private func beginFadeOut() {
        guard visibility.phase == .shown else { return } // 防御：计时器迟到 / 重复触发
        visibility.beginFadeOut()
        let generation = fadeGeneration
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Self.fadeOutDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            context.allowsImplicitAnimation = true
            self.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            // NSAnimationContext 完成回调在主线程；代际不符 = 期间发生了新 show，不收起
            MainActor.assumeIsolated {
                guard let self, self.fadeGeneration == generation else { return }
                self.finishDismiss()
            }
        })
    }

    private func finishDismiss() {
        cancelAutoDismissTimer()
        visibility.finishDismiss()
        alphaValue = 1
        orderOut(nil)
    }

    // MARK: - 卡片视觉（与主页仪表盘同语言的深色圆角卡）

    private func layoutContent(in card: AlertBannerContentView) {
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor(calibratedWhite: 0.07, alpha: 0.96).cgColor
        card.layer?.cornerRadius = 16
        card.layer?.masksToBounds = true
        card.layer?.borderWidth = 1
        card.layer?.borderColor = NSColor.white.withAlphaComponent(0.10).cgColor

        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.setContentHuggingPriority(.required, for: .horizontal)
        card.addSubview(icon)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .boldSystemFont(ofSize: 13)
        titleLabel.textColor = .white
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        card.addSubview(titleLabel)

        bodyLabel.translatesAutoresizingMaskIntoConstraints = false
        bodyLabel.font = .systemFont(ofSize: 12)
        bodyLabel.textColor = NSColor.white.withAlphaComponent(0.78)
        bodyLabel.maximumNumberOfLines = 2
        bodyLabel.cell?.truncatesLastVisibleLine = true
        bodyLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        card.addSubview(bodyLabel)

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            icon.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 30),
            icon.heightAnchor.constraint(equalToConstant: 30),
            titleLabel.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 12),
            titleLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 13),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: card.trailingAnchor, constant: -16),
            bodyLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            bodyLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            bodyLabel.trailingAnchor.constraint(lessThanOrEqualTo: card.trailingAnchor, constant: -16),
            bodyLabel.bottomAnchor.constraint(lessThanOrEqualTo: card.bottomAnchor, constant: -13),
        ])
    }
}

/// 横幅交互视图：点击整卡回调（borderless + nonactivatingPanel 下点击直达视图、不激活应用），
/// 悬停经 NSTrackingArea 通知面板暂停 / 恢复倒计时。
private final class AlertBannerContentView: NSView {
    var onClick: (() -> Void)?
    var onHoverChange: ((Bool) -> Void)?
    private var isHovering = false

    override var acceptsFirstResponder: Bool { false }

    /// 应用未激活时首击也直达视图（横幅常驻于他应用前台时）
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        // activeAlways：本应用非激活（游戏在前台）时悬停同样生效
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) {
        guard !isHovering else { return }
        isHovering = true
        onHoverChange?(true)
    }

    override func mouseExited(with event: NSEvent) {
        guard isHovering else { return }
        isHovering = false
        onHoverChange?(false)
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    /// show 时复位悬停态：orderOut 期间 tracking 的 enter/exit 事件不可靠，
    /// 复位后若鼠标仍停留在横幅上，下一次移动会重新触发 mouseEntered
    func clearHoverState() {
        isHovering = false
    }
}
