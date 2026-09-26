enum ByteFormatTests {
    static func all() {
        bytes()
        kilobytes()
        megabytesAndGigabytes()
        rateAppendsPerSecond()
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
}
