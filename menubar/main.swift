import AppKit
import CoreAudio

final class Delegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let toggle = NSMenuItem(title: "", action: #selector(flip), keyEquivalent: "t")
    let status = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    let list = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    var note: String?            // one-shot message (e.g. "Headphone disconnected")
    var pending: DispatchWorkItem?

    func applicationDidFinishLaunching(_ n: Notification) {
        toggle.target = self
        let menu = NSMenu(); menu.delegate = self
        [status, list, .separator(), toggle].forEach(menu.addItem)
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        listen()
        reconcile()
    }

    // React to devices connecting / disconnecting.
    func listen() {
        var a = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &a, .main) { [weak self] _, _ in
            self?.debounce()
        }
    }

    func debounce() {   // the system fires several notifications per change
        pending?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.reconcile() }
        pending = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: w)
    }

    /// Make the active device match reality. Idempotent, so our own changes don't loop.
    func reconcile() {
        let bt = btOutputs()
        let now = Set(bt.map(\.uid))
        if isActive() && now != activeMembers {
            if now.count >= 2 {
                if (try? enableDual()) != nil { note = "Updated: \(bt.map(\.name).joined(separator: " + "))" }
            } else {
                disableDual()
                note = "Stopped: only \(now.count) Bluetooth headphone\(now.count == 1 ? "" : "s") connected"
            }
        }
        refresh()
    }

    func refresh() {
        let bt = btOutputs()
        let on = isActive()
        item.button?.image = NSImage(systemSymbolName: on ? "headphones.circle.fill" : "headphones", accessibilityDescription: "TwinPods")
        list.title = bt.isEmpty ? "No Bluetooth headphones connected" : "Connected: " + bt.map(\.name).joined(separator: ", ")
        if let n = note { status.title = n }
        else if on { status.title = "Active: both headphones" }
        else if bt.count < 2 { status.title = "Connect \(2 - bt.count) more to use" }
        else { status.title = "Ready" }
        toggle.title = on ? "Turn off" : "Play on both headphones"
        toggle.isEnabled = on || bt.count >= 2
    }

    func menuWillOpen(_ menu: NSMenu) { reconcile() }   // always fresh when opened
    func menuDidClose(_ menu: NSMenu) { note = nil }

    @objc func flip() {
        note = nil
        if isActive() { disableDual() }
        else { do { _ = try enableDual() } catch let e as DualError { note = e.message } catch {} }
        refresh()
    }
}

let app = NSApplication.shared
let delegate = Delegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
