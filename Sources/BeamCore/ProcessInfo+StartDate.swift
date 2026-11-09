import Foundation

extension ProcessInfo {
    /// When the kernel started process `pid`, nil when there is no such
    /// process. Unlike a clock read in `main`, it counts the time spent
    /// loading and linking the program before `main` runs.
    public static func startDate(of pid: pid_t) -> Date? {
        var name = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        // A pid with no process succeeds with nothing written.
        guard sysctl(&name, UInt32(name.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let start = info.kp_proc.p_un.__p_starttime
        return Date(timeIntervalSince1970: TimeInterval(start.tv_sec) + TimeInterval(start.tv_usec) / 1_000_000)
    }
}
