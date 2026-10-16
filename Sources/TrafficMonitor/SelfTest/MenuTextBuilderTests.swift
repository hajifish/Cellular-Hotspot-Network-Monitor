import AppKit

enum MenuTextBuilderTests {
    static func all() {
        interfaceRowContainsNameAndArrows()
        alertHeaderReflectsState()
        bellAttachmentHasGlyph()
    }

    static func bellAttachmentHasGlyph() {
        let bell = MenuTextBuilder.bellAttachment(fired: false)
        TestRun.expect(bell.string.contains("\u{FFFC}"), "bell is an attachment glyph")
        let fired = MenuTextBuilder.bellAttachment(fired: true)
        TestRun.expect(fired.string.contains("\u{FFFC}"), "fired bell is an attachment glyph")
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
        let fired = MenuTextBuilder.alertHeader(armed: true, fired: true)
        TestRun.expect(fired?.string.contains("●") == true, "fired has dot")
    }
}
