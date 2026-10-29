import AppKit

enum MenuTextBuilderTests {
    static func all() {
        interfaceRowContainsNameAndArrows()
        alertHeaderReflectsState()
    }

    static func interfaceRowContainsNameAndArrows() {
        let row = MenuTextBuilder.interfaceRow(name: "iPhone",
                                               rx: 4_500_000_000, tx: 80_000_000,
                                               rate: CategoryDelta(rx: 1_200, tx: 300))
        let plain = row.string
        TestRun.expect(plain.contains("iPhone"), "row has name")
        TestRun.expect(plain.contains("↓"), "row has download arrow")
        TestRun.expect(plain.contains("↑"), "row has upload arrow")
        TestRun.expect(plain.contains("4.5 GB"), "row has rx total")
        TestRun.expect(plain.contains("1.5 KB/s"), "row has combined rate")
    }

    static func alertHeaderReflectsState() {
        TestRun.expect(MenuTextBuilder.alertHeader(armed: false, fired: false) == nil, "off has no marker")
        let armed = MenuTextBuilder.alertHeader(armed: true, fired: false)
        TestRun.expect(armed?.string.contains("流量告警") == true, "armed has label")
        TestRun.expect(armed?.string.contains("●") == true, "armed has dot")
        let armedWithDetail = MenuTextBuilder.alertHeader(armed: true, fired: false, detail: "剩 2.0GB")
        TestRun.expect(armedWithDetail?.string.contains("剩 2.0GB") == true, "armed shows detail")
        let fired = MenuTextBuilder.alertHeader(armed: true, fired: true, detail: "已触发")
        TestRun.expect(fired?.string.contains("已触发") == true, "fired shows detail")
        TestRun.expect(fired?.string.contains("●") == true, "fired has dot")
    }
}
