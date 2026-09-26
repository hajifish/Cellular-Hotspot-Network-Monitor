import Foundation
import Observation

@Observable
@MainActor
final class UsageStore {
    private(set) var startTime = Date()
    private(set) var wifiRX: UInt64 = 0
    private(set) var wifiTX: UInt64 = 0
    private(set) var iphoneRX: UInt64 = 0
    private(set) var iphoneTX: UInt64 = 0

    func record(_ deltas: [InterfaceCategory: CategoryDelta]) {
        if let d = deltas[.wifi] {
            wifiRX += d.rx
            wifiTX += d.tx
        }
        if let d = deltas[.iphone] {
            iphoneRX += d.rx
            iphoneTX += d.tx
        }
    }

    /// 清零累计并重新开始计时
    func reset() {
        startTime = Date()
        wifiRX = 0
        wifiTX = 0
        iphoneRX = 0
        iphoneTX = 0
    }
}
