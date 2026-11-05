import AppKit

/// 主页固化背景：内置图片铺满窗口（contentsGravity 自适应窗口高矮变化）。
/// 图片由 make-app.sh 强制打包进 Contents/Resources，缺失即视为打包损坏，
/// fail-fast、无回退路径。
///
/// 明暗观感已固化在图内：与参考项目（LLM-Token-Usage-Monitor-Desktop）的内置
/// 背景同源，其默认渲染即原图直铺、无遮罩（2026-11-05 用户要求明暗一致，
/// 此前的黑色遮罩已移除）。白字可读性由图内自带的深色材质观感保证。
final class DashboardBackgroundView: NSView {
    init(frame: NSRect, image: CGImage) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.contents = image
        layer?.contentsGravity = .resizeAspectFill
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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
