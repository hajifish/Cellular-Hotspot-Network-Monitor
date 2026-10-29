import Foundation

/// 菜单栏与主页卡片的展示映射（纯函数，可测）；着色等 AppKit 细节在 UI 层完成
enum UpdatePresentation {
    struct MenuContent: Equatable {
        let info: String
        let infoBold: Bool
        let primary: String?   // nil = 隐藏
        let primaryEnabled: Bool
        let secondary: String? // nil = 隐藏
    }

    static func menuContent(for state: UpdateState, currentVersion: String) -> MenuContent {
        switch state {
        case .idle:
            return MenuContent(info: "版本 \(currentVersion)", infoBold: false,
                               primary: "检查更新…", primaryEnabled: true, secondary: nil)
        case .checking:
            return MenuContent(info: "正在检查更新…", infoBold: false,
                               primary: nil, primaryEnabled: false, secondary: nil)
        case .upToDate:
            return MenuContent(info: "版本 \(currentVersion) ✓", infoBold: false,
                               primary: "检查更新…", primaryEnabled: true, secondary: nil)
        case .available(let release):
            return MenuContent(info: "⬆️ 新版本 \(release.tagName) 可用", infoBold: true,
                               primary: "下载并更新", primaryEnabled: true, secondary: "查看更新内容")
        case .failed:
            return MenuContent(info: "检查更新失败", infoBold: false,
                               primary: "重试检查", primaryEnabled: true, secondary: nil)
        case .downloading(let progress):
            return MenuContent(info: "下载更新中… \(Int(progress * 100))%", infoBold: false,
                               primary: nil, primaryEnabled: false, secondary: "取消下载")
        case .downloaded(let release):
            return MenuContent(info: "已下载 \(release.tagName)，待重启", infoBold: false,
                               primary: "重启以完成更新", primaryEnabled: true, secondary: "取消更新")
        case .installing:
            return MenuContent(info: "正在重启更新…", infoBold: false,
                               primary: nil, primaryEnabled: false, secondary: nil)
        }
    }

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
        let checkedAt = lastCheck.map { "上次检查 \($0.formatted(date: .omitted, time: .shortened))" } ?? ""
        switch state {
        case .idle:
            return CardContent(status: "当前版本 \(currentVersion)", kind: .neutral,
                               notes: "尚未检查过更新", primary: "检查更新", secondary: nil)
        case .checking:
            return CardContent(status: "当前版本 \(currentVersion)", kind: .neutral,
                               notes: "正在检查更新…", primary: nil, secondary: nil)
        case .upToDate:
            return CardContent(status: "当前版本 \(currentVersion) · 已是最新", kind: .ok,
                               notes: checkedAt, primary: "检查更新", secondary: nil)
        case .available(let release):
            let excerpt = AppVersion.notesExcerpt(release.body)
            return CardContent(status: "发现新版本 \(release.tagName)", kind: .attention,
                               notes: excerpt.isEmpty ? checkedAt : excerpt,
                               primary: "下载并更新", secondary: "打开发布页")
        case .failed:
            return CardContent(status: "检查更新失败", kind: .error,
                               notes: errorText ?? "", primary: "重试检查", secondary: nil)
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
