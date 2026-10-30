import Foundation

/// 主页「软件更新」卡片的展示映射（纯函数，可测）；着色等 AppKit 细节在 UI 层完成。
/// 菜单栏不展示任何更新内容——主页卡片是唯一更新入口（用户决策 2026-10-30）。
enum UpdatePresentation {
    /// 卡片内容颜色语义（着色在 HomePageController 做）
    enum CardKind: Equatable {
        case neutral, ok, attention, error
    }

    struct CardContent: Equatable {
        let status: String
        let kind: CardKind
        let notes: String
        let primary: String?
        let secondary: String?
    }

    static func cardContent(for state: UpdateState, currentVersion: String,
                            lastCheck: Date?, errorText: String?) -> CardContent {
        switch state {
        case .idle, .upToDate:
            // 无新版本：只展示当前版本号
            return CardContent(status: "当前版本 \(currentVersion)", kind: .neutral,
                               notes: "", primary: nil, secondary: nil)
        case .checking:
            return CardContent(status: "当前版本 \(currentVersion)", kind: .neutral,
                               notes: "正在检查更新…", primary: nil, secondary: nil)
        case .available(let release):
            let excerpt = AppVersion.notesExcerpt(release.body)
            let checkedAt = lastCheck.map { "上次检查 \($0.formatted(date: .omitted, time: .shortened))" } ?? ""
            return CardContent(status: "发现新版本 \(release.tagName)", kind: .attention,
                               notes: excerpt.isEmpty ? checkedAt : excerpt,
                               primary: "下载并更新", secondary: "打开发布页")
        case .failed:
            return CardContent(status: "当前版本 \(currentVersion)", kind: .error,
                               notes: errorText ?? "", primary: nil, secondary: nil)
        case .downloading(let progress):
            return CardContent(status: "正在下载更新 \(Int(progress * 100))%", kind: .attention,
                               notes: "", primary: nil, secondary: "取消下载")
        case .downloaded(let release):
            return CardContent(status: "\(release.tagName) 已就绪，重启后生效", kind: .attention,
                               notes: "安装包已校验并暂存，重启应用即完成更新",
                               primary: "重启以完成更新", secondary: "取消更新")
        case .installing:
            return CardContent(status: "正在重启完成更新…", kind: .attention,
                               notes: "", primary: nil, secondary: nil)
        }
    }
}
