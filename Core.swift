// dual-audio: play Mac audio through all connected Bluetooth outputs at once.
// Usage: dual-audio on | off | list
import CoreAudio
import Foundation

let multiUID = "dev.audifonos.multi-output"
let prevFile = NSHomeDirectory() + "/.dual-audio-prev"

struct Device { let id: AudioObjectID; let uid: String; let name: String; let bluetooth: Bool; let outputs: Bool }

func addr(_ s: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: s, mScope: scope, mElement: kAudioObjectPropertyElementMain)
}

func string(_ id: AudioObjectID, _ sel: AudioObjectPropertySelector) -> String {
    var a = addr(sel); var ref: Unmanaged<CFString>?; var size = UInt32(MemoryLayout<CFString?>.size)
    guard AudioObjectGetPropertyData(id, &a, 0, nil, &size, &ref) == noErr, let r = ref else { return "" }
    return r.takeRetainedValue() as String
}

func hasOutput(_ id: AudioObjectID) -> Bool {
    var a = addr(kAudioDevicePropertyStreamConfiguration, kAudioObjectPropertyScopeOutput); var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(id, &a, 0, nil, &size) == noErr, size > 0 else { return false }
    let buf = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: 16); defer { buf.deallocate() }
    guard AudioObjectGetPropertyData(id, &a, 0, nil, &size, buf) == noErr else { return false }
    let list = UnsafeMutableAudioBufferListPointer(buf.assumingMemoryBound(to: AudioBufferList.self))
    return list.contains { $0.mNumberChannels > 0 }
}

func devices() -> [Device] {
    var a = addr(kAudioHardwarePropertyDevices); var size: UInt32 = 0
    AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size)
    var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
    AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &ids)
    return ids.map { id in
        var t = addr(kAudioDevicePropertyTransportType); var transport: UInt32 = 0; var s = UInt32(4)
        AudioObjectGetPropertyData(id, &t, 0, nil, &s, &transport)
        let bt = transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE
        return Device(id: id, uid: string(id, kAudioDevicePropertyDeviceUID), name: string(id, kAudioObjectPropertyName), bluetooth: bt, outputs: hasOutput(id))
    }
}

func defaultOutputUID() -> String {
    var a = addr(kAudioHardwarePropertyDefaultOutputDevice); var id = AudioObjectID(0); var s = UInt32(4)
    AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &s, &id)
    return string(id, kAudioDevicePropertyDeviceUID)
}

func setDefaultOutput(_ id: AudioObjectID) {
    var a = addr(kAudioHardwarePropertyDefaultOutputDevice); var dev = id
    AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, UInt32(MemoryLayout<AudioObjectID>.size), &dev)
}

func destroyExisting() {
    if let old = devices().first(where: { $0.uid == multiUID }) { AudioHardwareDestroyAggregateDevice(old.id) }
}


struct DualError: Error { let message: String }

func isActive() -> Bool { devices().contains { $0.uid == multiUID } }

func btOutputs() -> [Device] { devices().filter { $0.bluetooth && $0.outputs } }

/// UIDs of the headphones currently inside the combined device.
var activeMembers: Set<String> = []

@discardableResult
func enableDual() throws -> String {
    let bt = btOutputs()
    guard bt.count >= 2 else { throw DualError(message: "Need 2+ connected Bluetooth outputs, found \(bt.count)") }
    let current = defaultOutputUID()
    if current != multiUID { try? current.write(toFile: prevFile, atomically: true, encoding: .utf8) }
    destroyExisting()
    let subs: [[String: Any]] = bt.enumerated().map { i, d in
        [kAudioSubDeviceUIDKey: d.uid, kAudioSubDeviceDriftCompensationKey: i == 0 ? 0 : 1]
    }
    let desc: [String: Any] = [
        kAudioAggregateDeviceNameKey: "TwinPods",
        kAudioAggregateDeviceUIDKey: multiUID,
        kAudioAggregateDeviceIsStackedKey: 1,
        kAudioAggregateDeviceMainSubDeviceKey: bt[0].uid,
        kAudioAggregateDeviceSubDeviceListKey: subs,
    ]
    var newID = AudioObjectID(0)
    let st = AudioHardwareCreateAggregateDevice(desc as CFDictionary, &newID)
    guard st == noErr else { throw DualError(message: "Could not create device (OSStatus \(st))") }
    usleep(500_000)
    setDefaultOutput(newID)
    activeMembers = Set(bt.map(\.uid))
    return bt.map(\.name).joined(separator: " + ")
}

func disableDual() {
    activeMembers = []
    destroyExisting()
    if let uid = try? String(contentsOfFile: prevFile, encoding: .utf8),
       let prev = devices().first(where: { $0.uid == uid && $0.outputs }) { setDefaultOutput(prev.id) }
}
