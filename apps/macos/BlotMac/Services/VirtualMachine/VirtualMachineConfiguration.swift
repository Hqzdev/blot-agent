import BlotDesign
import Foundation
import Virtualization

/// У образа, задания и рабочих файлов разные каталоги. Гость видит только явно переданные shares.
@MainActor
enum VirtualMachineConfiguration {
    static var root: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Blot/local/vm", isDirectory: true)
    }
    static var base: URL { root.appendingPathComponent("base", isDirectory: true) }
    static func make(directory: URL, shares: [String: VZSharedDirectory], network: Bool = false) throws -> VZVirtualMachineConfiguration {
        guard VZVirtualMachine.isSupported,
              let hardware = VZMacHardwareModel(dataRepresentation: try Data(contentsOf: directory.appendingPathComponent("HardwareModel.bin"))), hardware.isSupported,
              let identifier = VZMacMachineIdentifier(dataRepresentation: try Data(contentsOf: directory.appendingPathComponent("MachineIdentifier.bin"))) else {
            throw error("Образ VM несовместим с этим Mac")
        }
        let platform = VZMacPlatformConfiguration()
        platform.hardwareModel = hardware
        platform.machineIdentifier = identifier
        platform.auxiliaryStorage = VZMacAuxiliaryStorage(contentsOf: directory.appendingPathComponent("AuxiliaryStorage.bin"))
        let configuration = VZVirtualMachineConfiguration()
        configuration.platform = platform
        configuration.bootLoader = VZMacOSBootLoader()
        configuration.cpuCount = min(4, VZVirtualMachineConfiguration.maximumAllowedCPUCount)
        configuration.memorySize = 8 * 1024 * 1024 * 1024
        let disk = try VZDiskImageStorageDeviceAttachment(url: directory.appendingPathComponent("Disk.img"), readOnly: false)
        configuration.storageDevices = [VZVirtioBlockDeviceConfiguration(attachment: disk)]
        let graphics = VZMacGraphicsDeviceConfiguration()
        graphics.displays = [VZMacGraphicsDisplayConfiguration(widthInPixels: 1440, heightInPixels: 900, pixelsPerInch: 80)]
        configuration.graphicsDevices = [graphics]
        configuration.keyboards = [VZUSBKeyboardConfiguration()]
        configuration.pointingDevices = [VZUSBScreenCoordinatePointingDeviceConfiguration()]
        if !shares.isEmpty {
            let sharing = VZVirtioFileSystemDeviceConfiguration(tag: VZVirtioFileSystemDeviceConfiguration.macOSGuestAutomountTag)
            sharing.share = VZMultipleDirectoryShare(directories: shares)
            configuration.directorySharingDevices = [sharing]
        }
        // NAT разрешён только при ручной подготовке образа. Задания запускаются без сетевого устройства.
        if network {
            let adapter = VZVirtioNetworkDeviceConfiguration()
            adapter.attachment = VZNATNetworkDeviceAttachment()
            configuration.networkDevices = [adapter]
        }
        try configuration.validate()
        return configuration
    }
    static func error(_ message: String) -> NSError {
        NSError(domain: "BlotVM", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
