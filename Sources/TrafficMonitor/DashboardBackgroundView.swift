import AppKit

/// 主页固化背景：内置图片 aspect-fill 铺满（contentsGravity 自适应窗口高矮变化），
/// 其上叠黑色半透明遮罩保证白字可读。图片由 make-app.sh 强制打包进
/// Contents/Resources，缺失即视为打包损坏，fail-fast、无回退路径。
final class DashboardBackgroundView: NSView {
    /// 遮罩浓度：蓝青中亮背景图上的白字可读性（目检标定值；调整请改此常量。
    /// 2026-11-05 v0.9.1：0.5 → 0.3，用户反馈整体观感需更亮）
    static let scrimAlpha: CGFloat = 0.3

    /// 黑色遮罩层（最底层子视图，白字可读性前提）
    private let scrim = NSView()

    init(frame: NSRect, image: CGImage) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.contents = image
        layer?.contentsGravity = .resizeAspectFill
        layer?.masksToBounds = true
        // autoresizing 只按父视图「尺寸增量」调整子视图，不会撑起零尺寸视图，
        // 初始 frame 必须显式铺满（否则遮罩恒为 0×0，窗口变高后只留底部残条）
        scrim.frame = NSRect(origin: .zero, size: frame.size)
        scrim.wantsLayer = true
        scrim.layer?.backgroundColor = NSColor.black.withAlphaComponent(Self.scrimAlpha).cgColor
        scrim.autoresizingMask = [.width, .height]
        addSubview(scrim) // 最先加入：后续所有 UI 子视图都叠在遮罩之上
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        // 遮罩垫底是白字可读性前提；被插入到 0 号位即破坏，debug 断言兜底
        assert(subviews.first === scrim, "遮罩必须保持最底层子视图")
    }

    /// 加载打包内置背景图；缺失 = 打包不完整，直接崩溃
    /// （自测路径在 GUI 启动前 exit，不受影响；裸二进制 GUI 本就不可运行）
    static func loadBundledImage() -> CGImage {
        guard let url = Bundle.main.url(forResource: "default-background", withExtension: "png") else {
            fatalError("背景图资源缺失：打包不完整（应有 Contents/Resources/default-background.png）")
        }
        guard let image = NSImage(contentsOfFile: url.path)?
            .cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            fatalError("背景图存在但无法解码（文件损坏）")
        }
        return image
    }
}
