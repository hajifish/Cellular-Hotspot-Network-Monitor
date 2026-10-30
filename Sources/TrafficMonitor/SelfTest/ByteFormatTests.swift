enum ByteFormatTests {
    static func all() {
        bytes()
        kilobytes()
        megabytesAndGigabytes()
        rateAppendsPerSecond()
        stringPartsSplit()
    }

    static func bytes() {
        TestRun.expectEqual(ByteFormat.string(0), "0 B", "zero bytes")
        TestRun.expectEqual(ByteFormat.string(999), "999 B", "sub-KB")
    }

    static func kilobytes() {
        TestRun.expectEqual(ByteFormat.string(1_000), "1.0 KB", "1 KB")
        TestRun.expectEqual(ByteFormat.string(1_500), "1.5 KB", "1.5 KB")
    }

    static func megabytesAndGigabytes() {
        TestRun.expectEqual(ByteFormat.string(1_000_000), "1.0 MB", "1 MB")
        TestRun.expectEqual(ByteFormat.string(2_500_000_000), "2.5 GB", "2.5 GB")
        TestRun.expectEqual(ByteFormat.string(1_234_567_890_123), "1.2 TB", "1.2 TB")
    }

    static func rateAppendsPerSecond() {
        TestRun.expectEqual(ByteFormat.rate(0), "0 B/s", "zero rate")
        TestRun.expectEqual(ByteFormat.rate(1_200_000), "1.2 MB/s", "MB rate")
    }

    static func stringPartsSplit() {
        let parts = ByteFormat.stringParts(10_400_000_000)
        TestRun.expectEqual(parts.value, "10.4", "total value part")
        TestRun.expectEqual(parts.unit, "GB", "total unit part")
        let zero = ByteFormat.stringParts(0)
        TestRun.expectEqual(zero.value, "0", "zero value part")
        TestRun.expectEqual(zero.unit, "B", "zero unit part")
    }
}
