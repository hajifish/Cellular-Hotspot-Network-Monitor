import Foundation

@MainActor
enum UsageStoreTests {
    static func all() {
        initialValuesAreZero()
        recordAccumulatesPerCategory()
        resetZeroesAndRestartsClock()
    }

    static func initialValuesAreZero() {
        let store = UsageStore()
        TestRun.expect(store.wifiRX == 0 && store.wifiTX == 0, "wifi zero")
        TestRun.expect(store.iphoneRX == 0 && store.iphoneTX == 0, "iphone zero")
    }

    static func recordAccumulatesPerCategory() {
        let store = UsageStore()
        store.record([.wifi: CategoryDelta(rx: 100, tx: 50)])
        store.record([.wifi: CategoryDelta(rx: 10, tx: 5), .iphone: CategoryDelta(rx: 7000, tx: 300)])
        TestRun.expectEqual(store.wifiRX, UInt64(110), "wifi rx")
        TestRun.expectEqual(store.wifiTX, UInt64(55), "wifi tx")
        TestRun.expectEqual(store.iphoneRX, UInt64(7000), "iphone rx")
        TestRun.expectEqual(store.iphoneTX, UInt64(300), "iphone tx")
    }

    static func resetZeroesAndRestartsClock() {
        let store = UsageStore()
        store.record([.wifi: CategoryDelta(rx: 100, tx: 100)])
        let before = store.startTime
        Thread.sleep(forTimeInterval: 0.02)
        store.reset()
        TestRun.expectEqual(store.wifiRX, UInt64(0), "reset zeroes wifi")
        TestRun.expectEqual(store.iphoneTX, UInt64(0), "reset zeroes iphone")
        TestRun.expect(store.startTime.timeIntervalSince(before) >= 0, "clock restarts")
    }
}
