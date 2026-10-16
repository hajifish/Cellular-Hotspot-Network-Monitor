import Foundation

/// 状态栏显示偏好（两个独立开关；都关闭 = 只显示图标）
enum StatusBarPrefs {
    static let showRatesKey = "statusBarShowRates"
    static let showTotalsKey = "statusBarShowTotals"
    private static let legacyModeKey = "menuBarDisplayMode"

    static var showRates: Bool {
        get { UserDefaults.standard.object(forKey: showRatesKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: showRatesKey) }
    }

    static var showTotals: Bool {
        get { UserDefaults.standard.object(forKey: showTotalsKey) as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: showTotalsKey) }
    }

    /// 一次性迁移旧的单选模式（ratesOnly/totalsOnly/both/iconOnly）
    static func migrateLegacyMode() {
        guard UserDefaults.standard.object(forKey: showRatesKey) == nil,
              let legacy = UserDefaults.standard.string(forKey: legacyModeKey) else { return }
        switch legacy {
        case "ratesOnly": showRates = true; showTotals = false
        case "totalsOnly": showRates = false; showTotals = true
        case "both": showRates = true; showTotals = true
        default: showRates = false; showTotals = false // iconOnly
        }
        UserDefaults.standard.removeObject(forKey: legacyModeKey)
    }
}

enum StatusBarFormatter {
    /// 状态栏文字；两个开关都关时返回 nil（只显示图标）
    static func text(showRates: Bool, showTotals: Bool,
                     totalRate: CategoryDelta, totalRX: UInt64, totalTX: UInt64) -> String? {
        switch (showRates, showTotals) {
        case (true, false):
            return "↑\(ByteFormat.rate(totalRate.tx)) ↓\(ByteFormat.rate(totalRate.rx))"
        case (false, true):
            return "↑\(ByteFormat.string(totalTX)) ↓\(ByteFormat.string(totalRX))"
        case (true, true):
            return "↑\(ByteFormat.string(totalTX)) (\(ByteFormat.rate(totalRate.tx)))"
                + " ↓\(ByteFormat.string(totalRX)) (\(ByteFormat.rate(totalRate.rx)))"
        case (false, false):
            return nil
        }
    }
}
