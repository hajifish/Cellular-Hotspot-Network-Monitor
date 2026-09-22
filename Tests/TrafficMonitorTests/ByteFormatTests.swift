import Testing
@testable import TrafficMonitor

struct ByteFormatTests {
    @Test func bytes() {
        #expect(ByteFormat.string(0) == "0 B")
        #expect(ByteFormat.string(999) == "999 B")
    }

    @Test func kilobytes() {
        #expect(ByteFormat.string(1_000) == "1.0 KB")
        #expect(ByteFormat.string(1_500) == "1.5 KB")
    }

    @Test func megabytesAndGigabytes() {
        #expect(ByteFormat.string(1_000_000) == "1.0 MB")
        #expect(ByteFormat.string(2_500_000_000) == "2.5 GB")
        #expect(ByteFormat.string(1_234_567_890_123) == "1.2 TB")
    }

    @Test func rateAppendsPerSecond() {
        #expect(ByteFormat.rate(0) == "0 B/s")
        #expect(ByteFormat.rate(1_200_000) == "1.2 MB/s")
    }
}
