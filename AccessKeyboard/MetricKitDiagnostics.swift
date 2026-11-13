import AccessKeyboardCore
import MetricKit
import os

/// Subscribes to MetricKit in the host app and writes a short summary to
/// `os.Logger`. Payloads are not sent to the Fix proxy or anywhere else.
///
/// The keyboard extension does not subscribe. MetricKit delivers reports to
/// the containing app, and a second subscriber inside the memory-limited
/// extension would only add weight. Extension jetsams are the `mem=` lines
/// from `KeyboardViewController` plus whatever MetricKit later reports here.
final class MetricKitDiagnostics: NSObject, MXMetricManagerSubscriber {
    static let shared = MetricKitDiagnostics()

    func start() {
        MXMetricManager.shared.add(self)
    }

    /// MetricKit calls these off the main actor. The app target isolates types
    /// to the main actor by default, so the callbacks are explicitly nonisolated
    /// and only touch the log.
    nonisolated func didReceive(_ payloads: [MXMetricPayload]) {
        let log = Logger(subsystem: DiagnosticsLog.subsystem, category: "metrickit")
        for payload in payloads {
            let peak = payload.memoryMetrics?.peakMemoryUsage
                .converted(to: .megabytes)
                .value
            let peakMB = peak.map { Int($0.rounded()) } ?? -1
            log.notice(
                "metric begin=\(payload.timeStampBegin.timeIntervalSince1970, privacy: .public) peakMB=\(peakMB, privacy: .public) version=\(payload.latestApplicationVersion, privacy: .public)"
            )
        }
    }

    nonisolated func didReceive(_ payloads: [MXDiagnosticPayload]) {
        let log = Logger(subsystem: DiagnosticsLog.subsystem, category: "metrickit")
        for payload in payloads {
            let crashes = payload.crashDiagnostics?.count ?? 0
            let hangs = payload.hangDiagnostics?.count ?? 0
            let cpu = payload.cpuExceptionDiagnostics?.count ?? 0
            let disk = payload.diskWriteExceptionDiagnostics?.count ?? 0
            log.error("diagnostics crashes=\(crashes, privacy: .public) hangs=\(hangs, privacy: .public) cpu=\(cpu, privacy: .public) disk=\(disk, privacy: .public)")
            for crash in payload.crashDiagnostics ?? [] {
                let reason = String((crash.terminationReason ?? "").prefix(120))
                let exception = crash.exceptionType?.intValue ?? -1
                let signal = crash.signal?.intValue ?? -1
                let build = crash.metaData.applicationBuildVersion
                log.error(
                    "crash build=\(build, privacy: .public) exception=\(exception, privacy: .public) signal=\(signal, privacy: .public) reason=\(reason, privacy: .public)"
                )
            }
        }
    }
}
