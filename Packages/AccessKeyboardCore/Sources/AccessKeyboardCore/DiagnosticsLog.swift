import Foundation
import os

/// On-device diagnostics. Nothing here is uploaded.
///
/// Unified logging stays on the device (Console, a sysdiagnose, or Xcode).
/// MetricKit payloads are delivered to the host app and logged the same way.
/// That needs no extra App Store privacy category: the app does not collect
/// diagnostics off the device.
public enum DiagnosticsLog {
    public static let subsystem = "app.access.keyboard"

    public static func memory(_ context: String, category: String) {
        let mb = ResidentMemory.megabytes
        let log = Logger(subsystem: subsystem, category: category)
        if mb >= ResidentMemory.keyboardWarningMegabytes {
            log.error("\(context, privacy: .public) mem=\(mb, privacy: .public)MB")
        } else {
            log.notice("\(context, privacy: .public) mem=\(mb, privacy: .public)MB")
        }
    }
}

public enum ResidentMemory {
    /// Keyboard extensions are jetsam-killed somewhere around 40–60 MB.
    /// Crossing the low end is logged so a long session is visible before the kill.
    public static let keyboardWarningMegabytes = 40

    /// Resident footprint in megabytes, or -1 if the kernel will not say.
    public static var megabytes: Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return -1 }
        return Int(info.phys_footprint) / (1024 * 1024)
    }
}
