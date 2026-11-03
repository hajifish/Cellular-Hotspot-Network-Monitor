import Foundation
import Observation
import os

/// 单个类别的计量状态：累计收发 + 独立开始时间
struct CategoryUsage: Codable, Equatable {
    var rx: UInt64 = 0
    var tx: UInt64 = 0
    var startTime = Date()
}

@Observable
@MainActor
final class UsageStore {
    private static let persistenceKey = "usageStore.v1"

    private(set) var wifi: CategoryUsage
    private(set) var iphone: CategoryUsage
    private let defaults: UserDefaults
    private let logger = Logger(subsystem: "local.shin.TrafficMonitor", category: "usage-store")

    private struct PersistedUsage: Codable {
        var wifi: CategoryUsage
        var iphone: CategoryUsage
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.persistenceKey) {
            do {
                let state = try PropertyListDecoder().decode(PersistedUsage.self, from: data)
                wifi = state.wifi
                iphone = state.iphone
                return
            } catch {
                logger.error("Failed to restore usage totals: \(error.localizedDescription, privacy: .public)")
            }
        }
        wifi = CategoryUsage()
        iphone = CategoryUsage()
    }

    func record(_ deltas: [InterfaceCategory: CategoryDelta]) {
        var changed = false
        if let d = deltas[.wifi], d.rx > 0 || d.tx > 0 {
            wifi.rx += d.rx
            wifi.tx += d.tx
            changed = true
        }
        if let d = deltas[.iphone], d.rx > 0 || d.tx > 0 {
            iphone.rx += d.rx
            iphone.tx += d.tx
            changed = true
        }
        if changed {
            persist()
        }
    }

    /// 重置指定类别的累计并重新开始计时；nil = 全部
    func reset(_ category: InterfaceCategory? = nil) {
        if category == nil || category == .wifi { wifi = CategoryUsage() }
        if category == nil || category == .iphone { iphone = CategoryUsage() }
        persist()
    }

    func usage(for category: InterfaceCategory) -> CategoryUsage {
        category == .wifi ? wifi : iphone
    }

    /// 全部模块中最早的开始时间（会话起点）
    var sessionStart: Date {
        min(wifi.startTime, iphone.startTime)
    }

    private func persist() {
        do {
            let state = PersistedUsage(wifi: wifi, iphone: iphone)
            defaults.set(try PropertyListEncoder().encode(state), forKey: Self.persistenceKey)
        } catch {
            logger.error("Failed to save usage totals: \(error.localizedDescription, privacy: .public)")
        }
    }
}
