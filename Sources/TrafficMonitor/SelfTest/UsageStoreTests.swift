import Foundation

@MainActor
enum UsageStoreTests {
    static func all() {
        initialValuesAreZero()
        recordAccumulatesPerCategory()
        resetCategoryOnlyAffectsThatCategory()
        resetAllClearsEverything()
        resetRestartsCategoryClock()
    }

    static func initialValuesAreZero() {
        let store = UsageStore()
        TestRun.expect(store.wifi.rx == 0 && store.wifi.tx == 0, "wifi zero")
        TestRun.expect(store.iphone.rx == 0 && store.iphone.tx == 0, "iphone zero")
    }

    static func recordAccumulatesPerCategory() {
        let store = UsageStore()
        store.record([.wifi: CategoryDelta(rx: 100, tx: 50)])
        store.record([.wifi: CategoryDelta(rx: 10, tx: 5), .iphone: CategoryDelta(rx: 7000, tx: 300)])
        TestRun.expectEqual(store.wifi.rx, UInt64(110), "wifi rx")
        TestRun.expectEqual(store.wifi.tx, UInt64(55), "wifi tx")
        TestRun.expectEqual(store.iphone.rx, UInt64(7000), "iphone rx")
        TestRun.expectEqual(store.iphone.tx, UInt64(300), "iphone tx")
    }

    static func resetCategoryOnlyAffectsThatCategory() {
        let store = UsageStore()
        store.record([.wifi: CategoryDelta(rx: 100, tx: 100), .iphone: CategoryDelta(rx: 7000, tx: 300)])
        store.reset(.wifi)
        TestRun.expectEqual(store.wifi.rx, UInt64(0), "wifi reset")
        TestRun.expectEqual(store.iphone.rx, UInt64(7000), "iphone untouched")
        TestRun.expectEqual(store.iphone.tx, UInt64(300), "iphone tx untouched")
    }

    static func resetAllClearsEverything() {
        let store = UsageStore()
        store.record([.wifi: CategoryDelta(rx: 100, tx: 100), .iphone: CategoryDelta(rx: 1, tx: 2)])
        store.reset(nil)
        TestRun.expect(store.wifi.rx == 0 && store.wifi.tx == 0, "all reset wifi")
        TestRun.expect(store.iphone.rx == 0 && store.iphone.tx == 0, "all reset iphone")
    }

    static func resetRestartsCategoryClock() {
        let store = UsageStore()
        let before = store.wifi.startTime
        let iphoneBefore = store.iphone.startTime
        Thread.sleep(forTimeInterval: 0.02)
        store.reset(.wifi)
        TestRun.expect(store.wifi.startTime.timeIntervalSince(before) >= 0.015,
                       "wifi clock restarts")
        TestRun.expect(store.iphone.startTime == iphoneBefore, "iphone clock untouched")
    }
}
