#if os(macOS)
import Darwin
import Foundation

/// Birth timestamps prevent a delayed stop from signaling a recycled PID.
struct NativeProcessIdentity: Sendable, Equatable {
    let pid: pid_t
    let seconds: UInt64
    let micros: UInt64
    static func read(_ pid: pid_t) -> NativeProcessIdentity? {
        var info = proc_bsdinfo()
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size)) == MemoryLayout<proc_bsdinfo>.size,
              info.pbi_uid == getuid() else { return nil }
        return .init(pid: pid, seconds: info.pbi_start_tvsec, micros: info.pbi_start_tvusec)
    }
    func signal(_ value: Int32) { if Self.read(pid) == self { kill(pid, value) } }
    static func descendants(of root: pid_t) -> [pid_t: NativeProcessIdentity] {
        var pending = [root], visited: Set<pid_t> = [], result: [pid_t: NativeProcessIdentity] = [:]
        while let parent = pending.popLast(), visited.count < 4096 {
            guard visited.insert(parent).inserted else { continue }
            let count = proc_listchildpids(parent, nil, 0)
            guard count > 0, count <= 64 * 1024 else { continue }
            var pids = [pid_t](repeating: 0, count: Int(count) + 32)
            let returned = pids.withUnsafeMutableBytes { buffer in proc_listchildpids(parent, buffer.baseAddress, Int32(buffer.count)) }
            guard returned > 0 else { continue }
            // Unlike proc_listpids, proc_listchildpids returns the number of PIDs when a buffer is supplied.
            for pid in pids.prefix(Int(returned)) where pid > 0 {
                if let identity = Self.read(pid) { result[pid] = identity; pending.append(pid) }
            }
        }
        return result
    }
}
#endif
