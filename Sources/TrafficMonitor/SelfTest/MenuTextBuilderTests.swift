import AppKit

enum MenuTextBuilderTests {
    static func all() {
        interfaceRowContainsNameAndArrows()
        totalRowSumsModulesAndStaysSingleLine()
        stopsKeepColumnsApartAtScale()
        alertHeaderReflectsState()
    }

    static func interfaceRowContainsNameAndArrows() {
        let spec = MenuTextBuilder.InterfaceRowSpec(name: "iPhone",
                                                    rx: 4_500_000_000, tx: 80_000_000)
        let stops = MenuTextBuilder.columnStops(forRows: [spec])
        let row = MenuTextBuilder.interfaceRow(name: spec.name, rx: spec.rx, tx: spec.tx, stops: stops)
        let plain = row.string
        TestRun.expect(plain.contains("iPhone"), "row has name")
        TestRun.expect(plain.contains("↓"), "row has download arrow")
        TestRun.expect(plain.contains("↑"), "row has upload arrow")
        TestRun.expect(plain.contains("4.5 GB"), "row has rx total")
        TestRun.expect(plain.contains("4.6 GB"), "row has merged total")
        TestRun.expect(!plain.contains("/s"), "row has no real-time rate")
    }

    static func totalRowSumsModulesAndStaysSingleLine() {
        let wifi = MenuTextBuilder.InterfaceRowSpec(name: "Wi-Fi", rx: 3_900_000, tx: 1_200_000)
        let iphone = MenuTextBuilder.InterfaceRowSpec(name: "iPhone", rx: 5_200_000, tx: 28_600_000)
        let total = MenuTextBuilder.InterfaceRowSpec(name: "合计",
                                                     rx: wifi.rx + iphone.rx, tx: wifi.tx + iphone.tx)
        let stops = MenuTextBuilder.columnStops(forRows: [wifi, iphone, total])
        let row = MenuTextBuilder.interfaceRow(name: total.name, rx: total.rx, tx: total.tx,
                                               stops: stops, emphasized: true)
        TestRun.expect(row.string.contains("合计"), "total row labeled 合计")
        TestRun.expect(row.string.contains("38.9 MB"), "total row shows merged sum")
        TestRun.expect(!row.string.contains("\n"), "total row stays on one line")
    }

    static func stopsKeepColumnsApartAtScale() {
        // 999.9 GB 级大数：tab 位仍须把三列隔开，行不折
        let rows = [
            MenuTextBuilder.InterfaceRowSpec(name: "iPhone", rx: 999_900_000_000, tx: 888_800_000_000),
            MenuTextBuilder.InterfaceRowSpec(name: "Wi-Fi", rx: 777_700_000_000, tx: 666_600_000_000),
            MenuTextBuilder.InterfaceRowSpec(name: "合计", rx: 1_777_600_000_000, tx: 1_555_400_000_000),
        ]
        let stops = MenuTextBuilder.columnStops(forRows: rows)
        TestRun.expect(stops.first < stops.total, "stops ordered")
        for row in rows {
            let nameWidth = MenuTextBuilder.measuredNameWidth(row.name)
            let midWidth = MenuTextBuilder.measuredMidWidth(tx: ByteFormat.string(row.tx),
                                                            rx: ByteFormat.string(row.rx))
            TestRun.expect(RowLayout.leadingIndent + nameWidth < stops.first,
                           "\(row.name) name fits before first stop")
            TestRun.expect(stops.first + midWidth < stops.total,
                           "\(row.name) values fit before total stop")
        }
        let row = MenuTextBuilder.interfaceRow(name: rows[2].name, rx: rows[2].rx, tx: rows[2].tx,
                                               stops: stops)
        TestRun.expect(!row.string.contains("\n"), "large values stay single line")
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
