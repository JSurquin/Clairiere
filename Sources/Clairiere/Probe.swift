import Darwin
import Foundation

enum Probe {
    private static let browserIDs: Set<String> = [
        "com.apple.safari",
        "com.google.chrome",
        "com.google.chrome.canary",
        "org.mozilla.firefox",
        "org.mozilla.nightly",
        "company.thebrowser.browser",
        "company.thebrowser.dia",
        "com.microsoft.edgemac",
        "com.brave.browser",
        "com.operasoftware.opera",
        "com.kagi.kagimacos",
        "com.vivaldi.vivaldi",
        "com.sigmaos.sigmaos",
        "com.arc.browser"
    ]

    static let shellIDs: Set<String> = [
        "com.apple.finder",
        "com.apple.dock",
        "com.apple.systemuiserver",
        "com.apple.controlcenter",
        "com.apple.notificationcenterui",
        "com.apple.windowmanager",
        "com.apple.spotlight",
        "com.apple.loginwindow",
        "com.apple.dock.extra"
    ]

    private static let protectedNames: Set<String> = [
        "kernel_task", "launchd", "WindowServer", "loginwindow", "sysmond", "logd",
        "notifyd", "distnoted", "cfprefsd", "trustd", "securityd", "amfid", "syspolicyd",
        "coreservicesd", "opendirectoryd", "UserEventAgent", "runningboardd", "powerd",
        "watchdogd", "configd", "mds", "mds_stores", "fseventsd", "coreaudiod",
        "bluetoothd", "airportd", "cloudd", "tccd", "containermanagerd", "deleted",
        "sandboxd", "secinitd", "kernelmanagerd", "logind", "endpointsecurityd",
        "runningboardd", "symptomsd", "rapportd", "sharingd", "timed", "watchdogd"
    ]

    static func capture(previous: [Int32: TickMark]) -> Capture {
        let now = Date()
        let system = readSystem(now: now)
        let (processes, ticks) = readProcesses(previous: previous, now: now)
        return Capture(system: system, processes: processes, ticks: ticks)
    }

    static func isBrowser(bundleID: String?, name: String) -> Bool {
        if let bundleID, browserIDs.contains(bundleID.lowercased()) { return true }
        let folded = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let names = ["safari", "chrome", "firefox", "arc", "edge", "brave", "opera", "orion", "vivaldi", "dia"]
        return names.contains { folded == $0 || folded.hasPrefix($0 + " ") }
    }

    static func isShell(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return shellIDs.contains(bundleID.lowercased())
    }

    static func role(name: String, command: String, isMain: Bool) -> PartRole {
        let folded = (name + " " + command).lowercased()
        if folded.contains("kernel_task") { return .kernel }
        if folded.contains("renderer") || folded.contains("web content") || folded.contains("webcontent") {
            return .pages
        }
        if folded.contains("gpu") { return .graphics }
        if folded.contains("plugin") || folded.contains("plug-in") { return .plugin }
        if isMain { return .interface }
        if folded.contains("helper") || folded.contains("utility") { return .helper }
        return .service
    }

    static func canSignal(process: RawProcess, selfPID: Int32) -> Bool {
        if process.pid <= 1 || process.pid == selfPID { return false }
        if protectedNames.contains(process.name) || protectedNames.contains(process.command) { return false }
        if process.uid == 0 || process.uid != getuid() { return false }
        let path = process.path
        if path.hasPrefix("/usr/libexec/") || path.hasPrefix("/usr/sbin/") || path.hasPrefix("/sbin/") {
            return false
        }
        if path.hasPrefix("/System/Library/") && !path.contains(".app/") { return false }
        return true
    }

    private static func readSystem(now: Date) -> SystemSnapshot {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        var page: vm_size_t = 0
        host_page_size(mach_host_self(), &page)
        let pageSize = UInt64(page)
        guard result == KERN_SUCCESS, pageSize > 0 else { return .empty }

        func pages(_ count: UInt64) -> UInt64 { count * pageSize }

        var swap = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.stride
        let swapResult = sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0)

        var level: Int32 = 0
        var levelSize = MemoryLayout<Int32>.stride
        sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &levelSize, nil, 0)

        let internalPages = UInt64(stats.internal_page_count)
        let purgeable = UInt64(stats.purgeable_count)
        let appPages = internalPages > purgeable ? internalPages - purgeable : 0

        return SystemSnapshot(
            physical: ProcessInfo.processInfo.physicalMemory,
            app: pages(appPages),
            wired: pages(UInt64(stats.wire_count)),
            compressed: pages(UInt64(stats.compressor_page_count)),
            cached: pages(UInt64(stats.external_page_count)),
            free: pages(UInt64(stats.free_count)),
            purgeable: pages(purgeable),
            swapUsed: swapResult == 0 ? swap.xsu_used : 0,
            swapTotal: swapResult == 0 ? swap.xsu_total : 0,
            uncompressedInCompressor: stats.total_uncompressed_pages_in_compressor * pageSize,
            swapEncrypted: swapResult == 0 && swap.xsu_encrypted != 0,
            pressureLevel: level,
            capturedAt: now
        )
    }

    private static func readProcesses(previous: [Int32: TickMark], now: Date) -> ([RawProcess], [Int32: TickMark]) {
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)

        let capacity = max(proc_listallpids(nil, 0), 1)
        var pids = [pid_t](repeating: 0, count: Int(capacity) + 32)
        let written = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.stride))
        let upper = min(Int(written), pids.count)

        var processes: [RawProcess] = []
        var ticks: [Int32: TickMark] = [:]
        processes.reserveCapacity(upper)
        var seen = Set<Int32>()

        for pid in pids.prefix(upper) where pid > 0 && seen.insert(pid).inserted {
            guard let process = readProcess(pid: pid, previous: previous, now: now, timebase: timebase) else { continue }
            if process.footprint < 1_500_000 && process.resident < 8_000_000 { continue }
            processes.append(process)
            ticks[pid] = TickMark(ticks: process.cpuTicks, time: now)
        }
        return (processes, ticks)
    }

    private static func readProcess(
        pid: pid_t,
        previous: [Int32: TickMark],
        now: Date,
        timebase: mach_timebase_info_data_t
    ) -> RawProcess? {
        var task = proc_taskinfo()
        let taskSize = Int32(MemoryLayout<proc_taskinfo>.stride)
        guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &task, taskSize) == taskSize else { return nil }

        var bsd = proc_bsdinfo()
        let bsdSize = Int32(MemoryLayout<proc_bsdinfo>.stride)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsd, bsdSize) == bsdSize else { return nil }

        var usage = rusage_info_v4()
        let usageResult: Int32 = withUnsafeMutablePointer(to: &usage) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
            }
        }

        let pathCapacity = 4096
        var pathBuffer = [CChar](repeating: 0, count: pathCapacity)
        let pathLength = proc_pidpath(pid, &pathBuffer, UInt32(pathCapacity))
        let path: String
        if pathLength > 0 {
            let bytes = pathBuffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
            path = String(decoding: bytes, as: UTF8.self)
        } else {
            path = ""
        }
        let command = decode(bsd.pbi_comm)
        var name = decode(bsd.pbi_name)
        if name.isEmpty { name = command }
        if name.isEmpty { name = URL(fileURLWithPath: path).lastPathComponent }
        if name.isEmpty { name = "Processus \(pid)" }

        let footprint = usageResult == 0 && usage.ri_phys_footprint > 0 ? usage.ri_phys_footprint : task.pti_resident_size
        var cwd = ""
        var detail = ""
        if footprint > 40_000_000 && !path.contains(".app/") {
            var vnode = proc_vnodepathinfo()
            let vnodeSize = Int32(MemoryLayout<proc_vnodepathinfo>.stride)
            if proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &vnode, vnodeSize) == vnodeSize {
                cwd = decode(vnode.pvi_cdir.vip_path)
            }
            if isRuntime(command.isEmpty ? name : command) {
                detail = scriptArgument(pid: pid) ?? ""
            }
        }
        let cpuTicks = task.pti_total_user &+ task.pti_total_system
        let cpu = cpuPercent(ticks: cpuTicks, previous: previous[pid], now: now, timebase: timebase)
        let start = bsd.pbi_start_tvsec > 0 ? Date(timeIntervalSince1970: TimeInterval(bsd.pbi_start_tvsec)) : now

        return RawProcess(
            pid: pid,
            ppid: Int32(bsd.pbi_ppid),
            uid: bsd.pbi_uid,
            name: name,
            command: command.isEmpty ? name : command,
            path: path,
            footprint: footprint,
            resident: usageResult == 0 ? usage.ri_resident_size : task.pti_resident_size,
            virtualSize: task.pti_virtual_size,
            wired: usageResult == 0 ? usage.ri_wired_size : 0,
            peak: usageResult == 0 ? usage.ri_lifetime_max_phys_footprint : footprint,
            threads: Int(task.pti_threadnum),
            cpuTicks: cpuTicks,
            cpuPercent: cpu,
            start: start,
            cwd: cwd,
            detail: detail
        )
    }

    private static func cpuPercent(
        ticks: UInt64,
        previous: TickMark?,
        now: Date,
        timebase: mach_timebase_info_data_t
    ) -> Double {
        guard let previous else { return 0 }
        let elapsed = now.timeIntervalSince(previous.time)
        guard elapsed > 0.4 else { return 0 }
        let delta = ticks &- previous.ticks
        let nanos = Double(delta) * Double(timebase.numer) / Double(timebase.denom)
        return min(999, (nanos / 1_000_000_000) / elapsed * 100)
    }

    private static let runtimes: Set<String> = ["node", "python", "python3", "ruby", "java", "bun", "deno", "perl"]

    private static func isRuntime(_ name: String) -> Bool {
        runtimes.contains(name.lowercased())
    }

    private static func scriptArgument(pid: pid_t) -> String? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 8, size < 256_000 else { return nil }
        var data = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &data, &size, nil, 0) == 0, size > 8 else { return nil }
        let argc = Int(data.withUnsafeBytes { $0.load(as: Int32.self) })
        guard argc > 1 else { return nil }
        var index = MemoryLayout<Int32>.size
        func next() -> String? {
            guard index < size else { return nil }
            guard let end = data[index..<size].firstIndex(of: 0) else { return nil }
            let slice = data[index..<end]
            index = end + 1
            return String(decoding: slice, as: UTF8.self)
        }
        _ = next()
        while index < size, data[index] == 0 { index += 1 }
        var arguments: [String] = []
        for _ in 0..<argc {
            guard let value = next() else { break }
            if !value.isEmpty { arguments.append(value) }
        }
        return arguments.dropFirst().first { argument in
            !argument.hasPrefix("-") && (argument.contains("/") || argument.contains("."))
        }
    }

    private static func decode<T>(_ value: T) -> String {
        withUnsafeBytes(of: value) { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            let end = bytes.firstIndex(of: 0) ?? bytes.count
            return String(decoding: bytes.prefix(end), as: UTF8.self)
        }
    }
}

enum MemoryNudge {
    static func push(maxBytes: Int) {
        let chunk = 64 * 1024 * 1024
        guard maxBytes >= chunk else { return }
        var blocks: [UnsafeMutableRawPointer] = []
        var taken = 0
        while taken + chunk <= maxBytes {
            guard let raw = malloc(chunk) else { break }
            memset(raw, 0xA5, chunk)
            blocks.append(raw)
            taken += chunk
        }
        for block in blocks {
            free(block)
        }
    }
}
