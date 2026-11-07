import Sentry
import Testing
@testable import Biinge

struct MonitoringTests {
    @Test(arguments: [
        "https://media.example.com/videos/1/main.m3u8?ApiKey=secret&Static=true",
        "GET https://media.example.com/Videos/1/stream",
        "https://media.example.com/videos/1/hls1/main/0.mp4",
        "GET https://media.example.com/stream?api_key=secret",
        "DeviceId=x&api_key=secret",
    ])
    func redactedReplacesStreamURLsAndAPIKeys(text: String) {
        #expect(Monitoring.redacted(text) == "[redacted]")
    }

    @Test func failedRequestEventsLoseTheirAPIKey() {
        let event = Event()
        let request = SentryRequest()
        request.url = "https://media.example.com/videos/1/stream"
        request.queryString = "api_key=secret&static=true"
        event.request = request

        let redacted = Monitoring.redactRequest(of: event)

        #expect(redacted.request?.url == "[redacted]")
        #expect(redacted.request?.queryString == "[redacted]")
    }

    @Test func redactedLeavesOtherTextAlone() {
        let url = "https://api.example.com/movies?page=2"

        #expect(Monitoring.redacted(url) == url)
    }
}
