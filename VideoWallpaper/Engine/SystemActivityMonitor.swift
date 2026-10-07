import AppKit
import IOKit.ps

/// Tracks system conditions that should pause playback: lock screen, screen saver, sleep,
/// fast user switching, battery power and Low Power Mode.
@MainActor
final class SystemActivityMonitor {
    private(set) var isScreenLocked = false
    private(set) var isScreenSaverRunning = false
    private(set) var areScreensAsleep = false
    private(set) var isSystemAsleep = false
    private(set) var isSessionInactive = false
    private(set) var isOnBattery = false
    private(set) var isLowPowerMode = false

    var onChange: (() -> Void)?
    var onWake: (() -> Void)?

    private var tokens: [(NotificationCenter, NSObjectProtocol)] = []
    private var powerSource: CFRunLoopSource?

    func start() {
        guard tokens.isEmpty else { return }
        isOnBattery = PowerSource.isOnBattery
        isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled

        let distributed = DistributedNotificationCenter.default()
        observe(distributed, Notification.Name("com.apple.screenIsLocked")) { $0.isScreenLocked = true }
        observe(distributed, Notification.Name("com.apple.screenIsUnlocked")) { $0.isScreenLocked = false }
        observe(distributed, Notification.Name("com.apple.screensaver.didstart")) { $0.isScreenSaverRunning = true }
        observe(distributed, Notification.Name("com.apple.screensaver.didstop")) { $0.isScreenSaverRunning = false }

        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.screensDidSleepNotification) { $0.areScreensAsleep = true }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { monitor in
            monitor.areScreensAsleep = false
            monitor.onWake?()
        }
        observe(workspace, NSWorkspace.willSleepNotification) { $0.isSystemAsleep = true }
        observe(workspace, NSWorkspace.didWakeNotification) { monitor in
            monitor.isSystemAsleep = false
            monitor.onWake?()
        }
        observe(workspace, NSWorkspace.sessionDidResignActiveNotification) { $0.isSessionInactive = true }
        observe(workspace, NSWorkspace.sessionDidBecomeActiveNotification) { $0.isSessionInactive = false }

        observe(NotificationCenter.default, Notification.Name.NSProcessInfoPowerStateDidChange) { monitor in
            monitor.isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
        observe(NotificationCenter.default, PowerSource.didChangeNotification) { monitor in
            monitor.isOnBattery = PowerSource.isOnBattery
        }
        powerSource = PowerSource.startMonitoring()
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, _ update: @escaping @MainActor (SystemActivityMonitor) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                update(self)
                self.onChange?()
            }
        }
        tokens.append((center, token))
    }
}

enum PowerSource {
    static let didChangeNotification = Notification.Name("VideoWallpaperPowerSourceDidChange")

    static var isOnBattery: Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(snapshot)?.takeUnretainedValue() else {
            return false
        }
        return (type as String) == "Battery Power"
    }

    static func startMonitoring() -> CFRunLoopSource? {
        guard let source = IOPSNotificationCreateRunLoopSource({ _ in
            NotificationCenter.default.post(name: PowerSource.didChangeNotification, object: nil)
        }, nil)?.takeRetainedValue() else {
            return nil
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        return source
    }
}
