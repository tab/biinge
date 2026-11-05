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
            // Jellyfin stream URLs carry the access token in their query, and the contract keeps the URLs out too
            options.beforeBreadcrumb = { breadcrumb in
                breadcrumb.data = breadcrumb.data?.mapValues { value -> Any in
                    guard let text = value as? String else { return value }
                    return redacted(text)
                }
                return breadcrumb
            }
            options.beforeSend = { event in
                redactRequest(of: event)
            }
            options.beforeSendSpan = { span in
                span.spanDescription = span.spanDescription.map(redacted)
                for (key, value) in span.data {
                    if let text = value as? String { span.setData(value: redacted(text), key: key) }
                }
                return span
            }
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

    /// Replaces text that holds a Jellyfin API key or a Jellyfin stream path (`/videos/`) with "[redacted]"
    static func redacted(_ text: String) -> String {
        let jellyfin = "api_?key=|/videos/"
        return text.range(of: jellyfin, options: [.regularExpression, .caseInsensitive]) == nil ? text : "[redacted]"
    }

    /// Redacts the URL and query of an error event's request (failed HTTP requests copy both into the event)
    static func redactRequest(of event: Event) -> Event {
        event.request?.url = event.request?.url.map(redacted)
        event.request?.queryString = event.request?.queryString.map(redacted)
        return event
    }

    private static var environment: String {
        #if DEBUG
        "development"
        #else
        "production"
        #endif
    }
}
