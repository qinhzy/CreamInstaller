import Foundation

public enum QEMUCommandBuilder {
    public static func arguments(
        machine: VirtualMachine,
        layout: VMStorageLayout,
        installation: QEMUInstallation
    ) -> [String] {
        let diskPath = escapedOptionValue(layout.diskURL(for: machine.id).path)
        let variablesPath = escapedOptionValue(layout.efiVariablesURL(for: machine.id).path)
        let firmwarePath = escapedOptionValue(installation.firmwareURL.path)
        let serialSuffix = machine.id.uuidString
            .replacingOccurrences(of: "-", with: "")
            .prefix(12)
        let serial = "WINLIFT-" + String(serialSuffix)

        var result = [
            // 显式使用 guest= 键：裸值中的 '=' 会被 QEMU 当作未知子选项键。
            "-name", "guest=" + escapedOptionValue(machine.name),
            "-machine", "virt,highmem=on,gic-version=3",
            "-accel", "hvf",
            "-cpu", "host",
            "-smp", String(machine.cpuCount),
            "-m", "\(machine.memorySizeGiB)G",
            "-nodefaults",
            "-drive", "if=pflash,format=raw,unit=0,readonly=on,file=\(firmwarePath)",
            "-drive", "if=pflash,format=raw,unit=1,file=\(variablesPath)",
            "-drive", "if=none,id=systemdisk,format=raw,cache=writeback,file=\(diskPath)",
            "-device", "nvme,drive=systemdisk,serial=\(serial),bootindex=1",
            "-device", "nec-usb-xhci,id=usb-bus",
            "-device", "usb-kbd,bus=usb-bus.0",
            "-device", "usb-tablet,bus=usb-bus.0",
            "-device", "ramfb"
        ]

        if machine.attachInstaller, let isoPath = machine.installerISOPath {
            let escapedISOPath = escapedOptionValue(isoPath)
            result += [
                "-drive", "if=none,id=installer,format=raw,media=cdrom,readonly=on,file=\(escapedISOPath)",
                "-device", "usb-storage,drive=installer,removable=true,bootindex=0,bus=usb-bus.0"
            ]
        }

        result += [
            "-netdev", "user,id=net0",
            "-device", "usb-net,netdev=net0,bus=usb-bus.0",
            "-audiodev", "coreaudio,id=audio0",
            "-device", "usb-audio,audiodev=audio0,bus=usb-bus.0",
            "-rtc", "base=localtime",
            "-uuid", machine.id.uuidString,
            "-pidfile", layout.runtimePIDURL(for: machine.id).path,
            "-boot", "menu=on",
            "-display", "cocoa,show-cursor=on",
            "-vga", "none",
            "-serial", "none",
            "-monitor", "none",
            "-qmp", "stdio"
        ]

        return result
    }

    /// QEMU uses commas to separate sub-options. A literal comma inside a path
    /// is represented by two commas.
    public static func escapedOptionValue(_ value: String) -> String {
        value.replacingOccurrences(of: ",", with: ",,")
    }
}
