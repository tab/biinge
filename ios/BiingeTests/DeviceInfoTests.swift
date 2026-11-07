import Testing
@testable import Biinge

struct DeviceInfoTests {
    @Test func theUserAgentNamesThePlatformTheTestsRunOn() {
        #if os(macOS)
        let expected = "macOS"
        #elseif os(tvOS)
        let expected = "tvOS"
        #else
        let expected = "iOS"
        #endif
        #expect(APIClient.userAgent.contains("; \(expected) "))
    }

    @Test func theDeviceNameIsThePlatformTheTestsRunOn() {
        #if os(macOS)
        let expected = "Mac"
        #elseif os(tvOS)
        let expected = "Apple TV"
        #else
        let expected = "iPhone"
        #endif
        #expect(DeviceInfo.deviceName == expected)
    }
}
