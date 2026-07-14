import Foundation
import Sentry

/// Thin wrapper over Sentry so the SDK stays behind one file and is a no-op when disabled
enum Monitoring {
    /// Starts Sentry when enabled and a DSN is set; call once, as early as possible
    static func start() {
        guard Config.sentryEnabled, let dsn = Config.sentryDSN else { return }

        SentrySDK.start { options in
            options.dsn = dsn
            options.environment = environment
            options.tracesSampleRate = 1.0
            #if DEBUG
            options.debug = true
            #endif
        }
    }

    /// Reports an unexpected error, tagged with the operation that produced it
    static func capture(_ error: Error, operation: String) {
        guard Config.sentryEnabled else { return }

        SentrySDK.capture(error: error) { scope in
            scope.setTag(value: operation, key: "operation")
        }
    }

    private static var environment: String {
        #if DEBUG
        "development"
        #else
        "production"
        #endif
    }
}
