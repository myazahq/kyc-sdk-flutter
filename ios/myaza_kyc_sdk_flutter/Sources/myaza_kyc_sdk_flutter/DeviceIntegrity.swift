import Darwin
import Foundation
import MachO

/// Client-side jailbreak and hook heuristics for `fingerprint.integrity`
/// (kyc-core docs/DEVICE_INTEL_WIRE.md §2). Soft by design: the server reads a
/// positive as evidence and a negative as nothing. None prompts the user or
/// needs a permission, and none needs an Info.plist entry, which is why the
/// `cydia://` URL-scheme check (it needs LSApplicationQueriesSchemes) is not
/// here. Run off the main thread.
///
/// On the simulator the filesystem checks would read the Mac's own files
/// (/bin/bash exists there), so they are skipped and `rooted` is null.
enum DeviceIntegrity {
  private static let jailbreakPaths = [
    "/Applications/Cydia.app", "/Applications/Sileo.app", "/Applications/Zebra.app",
    "/Library/MobileSubstrate/MobileSubstrate.dylib", "/bin/bash", "/usr/sbin/sshd",
    "/usr/bin/ssh", "/etc/apt", "/private/var/lib/apt/", "/var/jb", "/var/binpack",
    "/usr/lib/libjailbreak.dylib",
  ]
  /// Image names that mean code was injected into this process.
  private static let injectedNames = [
    "mobilesubstrate", "substrateloader", "libsubstitute", "substitute-inserter",
    "tweakinject", "libhooker", "cephei", "sslkillswitch", "libellekit",
  ]
  /// Libraries Xcode injects into a debug run; not a hook.
  private static let xcodeInjected = ["/Developer/", "libMainThreadChecker", "libViewDebuggerSupport"]
  private static let rootTokens: Set<String> = ["jailbreak_paths", "cydia_scheme", "sandbox_escape"]
  private static let hookTokens: Set<String> = ["dyld_injection", "frida", "debugger"]

  static func check() -> [String: Any] {
    var signals: [String] = []
    #if !targetEnvironment(simulator)
      if jailbreakPaths.contains(where: { FileManager.default.fileExists(atPath: $0) }) {
        signals.append("jailbreak_paths")
      }
      if sandboxEscape() { signals.append("sandbox_escape") }
    #endif
    let images = loadedImages()
    if images.contains(where: { n in injectedNames.contains(where: { n.contains($0) }) })
      || insertedLibraries()
    {
      signals.append("dyld_injection")
    }
    if images.contains(where: { $0.contains("frida") }) || loopbackPortOpen(27042) {
      signals.append("frida")
    }
    if debuggerAttached() { signals.append("debugger") }
    #if targetEnvironment(simulator)
      let rooted: Any = NSNull()  // the filesystem checks did not run
    #else
      let rooted: Any = signals.contains(where: rootTokens.contains)
    #endif
    return [
      "rooted": rooted,
      "hooked": signals.contains(where: hookTokens.contains),
      "signals": signals,
    ]
  }

  /// A sandboxed app cannot write outside its container; a jailbroken one can.
  private static func sandboxEscape() -> Bool {
    let path = "/private/myaza_kyc_probe_\(UUID().uuidString)"
    do {
      try "x".write(toFile: path, atomically: false, encoding: .utf8)
      try? FileManager.default.removeItem(atPath: path)
      return true
    } catch {
      return false
    }
  }

  private static func loadedImages() -> [String] {
    (0..<_dyld_image_count()).compactMap { i in
      _dyld_get_image_name(i).map { String(cString: $0).lowercased() }
    }
  }

  /// DYLD_INSERT_LIBRARIES carrying anything Xcode itself did not put there.
  private static func insertedLibraries() -> Bool {
    guard let raw = getenv("DYLD_INSERT_LIBRARIES") else { return false }
    return String(cString: raw).split(separator: ":").contains { lib in
      !xcodeInjected.contains(where: { lib.contains($0) })
    }
  }

  /// frida-server's default port answering on loopback (exempt from the
  /// Local Network prompt).
  private static func loopbackPortOpen(_ port: UInt16) -> Bool {
    let fd = socket(AF_INET, SOCK_STREAM, 0)
    guard fd >= 0 else { return false }
    defer { close(fd) }
    var addr = sockaddr_in()
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_port = port.bigEndian
    addr.sin_addr.s_addr = inet_addr("127.0.0.1")
    let rc = withUnsafePointer(to: &addr) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
      }
    }
    return rc == 0
  }

  /// P_TRACED: a debugger (or ptrace-based tool) is attached.
  private static func debuggerAttached() -> Bool {
    var info = kinfo_proc()
    var size = MemoryLayout<kinfo_proc>.stride
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
    guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0 else { return false }
    return (info.kp_proc.p_flag & P_TRACED) != 0
  }
}
