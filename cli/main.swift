import Foundation

func fail(_ msg: String) -> Never { FileHandle.standardError.write(Data((msg + "\n").utf8)); exit(1) }

switch CommandLine.arguments.dropFirst().first ?? "on" {
case "list": for d in devices() where d.outputs { print("\(d.bluetooth ? "[BT]" : "    ") \(d.name)") }
case "on":
    do { print("Playing on: " + (try enableDual())) } catch let e as DualError { fail(e.message) }
case "off": disableDual(); print("Back to normal output.")
default: fail("Usage: twinpods on | off | list")
}
