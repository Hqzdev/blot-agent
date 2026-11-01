import BlotDesign
import Foundation
import Virtualization

/// Один запуск — одна копия диска. Состояние гостя не переносится в следующую команду.
@MainActor
final class VirtualMachineExecution {
    static let shared = VirtualMachineExecution()
    private var id: String?
    private var job: URL?
    private var machine: VZVirtualMachine?
    private var task: _Concurrency.Task<Void, Never>?
    private var state: [String: Any] = [:]
    var isBusy: Bool { id != nil }

    func start(_ arguments: [String: Any]) throws -> [String: Any] {
        guard id == nil, !VirtualMachinePreparation.shared.isBusy else { throw VirtualMachineConfiguration.error("VM уже используется") }
        guard let id = arguments["id"] as? String, UUID(uuidString: id) != nil,
              let path = arguments["jobDirectory"] as? String,
              let timeout = arguments["timeoutSeconds"] as? Int, (1...1800).contains(timeout) else {
            throw VirtualMachineConfiguration.error("Неверные параметры VM")
        }
        let expected = VirtualMachineConfiguration.root.appendingPathComponent("jobs/" + id).standardizedFileURL
        let job = URL(fileURLWithPath: path).resolvingSymlinksInPath()
        guard expected.path == job.path else { throw VirtualMachineConfiguration.error("Неверный каталог VM") }
        guard FileManager.default.fileExists(atPath: VirtualMachineConfiguration.base.appendingPathComponent("Ready.json").path) else {
            throw VirtualMachineConfiguration.error("Сначала подготовьте macOS в настройках среды выполнения")
        }
        self.id = id; self.job = job; state = ["status": "RUNNING"]
        task = _Concurrency.Task { await execute(job: job, id: id, timeout: timeout) }
        return state
    }

    func status(_ requested: String) throws -> [String: Any] {
        guard requested == id else { throw VirtualMachineConfiguration.error("Задание VM не найдено") }
        return state
    }

    func release(_ requested: String) async throws {
        guard requested == id else { throw VirtualMachineConfiguration.error("Задание VM не найдено") }
        task?.cancel()
        await task?.value
        // При неудавшейся остановке сохраняем машину и каталог; новый запуск запрещён.
        try await stop()
        if let job { try FileManager.default.removeItem(at: job) }
        id = nil; job = nil; task = nil; state = [:]
    }

    func shutdown() async { if let id { try? await release(id) } }

    private func execute(job: URL, id: String, timeout: Int) async {
        do {
            let disk = job.appendingPathComponent("machine", isDirectory: true)
            try FileManager.default.createDirectory(at: disk, withIntermediateDirectories: true)
            for name in ["Disk.img", "AuxiliaryStorage.bin", "HardwareModel.bin", "MachineIdentifier.bin"] {
                // APFS создаёт независимую копию с copy-on-write; базовый образ не монтируется гостем.
                try FileManager.default.copyItem(at: VirtualMachineConfiguration.base.appendingPathComponent(name), to: disk.appendingPathComponent(name))
            }
            let exchange = job.appendingPathComponent("exchange")
            try FileManager.default.createDirectory(at: exchange, withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: job.appendingPathComponent("workspace"), to: exchange.appendingPathComponent("workspace"))
            try FileManager.default.copyItem(at: job.appendingPathComponent("request.json"), to: exchange.appendingPathComponent("request.json"))
            let vm = VZVirtualMachine(configuration: try VirtualMachineConfiguration.make(directory: disk,
                shares: ["job": VZSharedDirectory(url: exchange, readOnly: false)]))
            machine = vm
            try await vm.start()
            let deadline = Date().addingTimeInterval(TimeInterval(timeout + 90))
            let result = exchange.appendingPathComponent("result.json")
            while !FileManager.default.fileExists(atPath: result.path) {
                try _Concurrency.Task.checkCancellation()
                guard Date() < deadline, vm.state == .running else { throw VirtualMachineConfiguration.error("Гостевая macOS не ответила вовремя") }
                try await _Concurrency.Task.sleep(for: .milliseconds(250))
            }
            // Результат и файлы читаются только после остановки всех процессов гостя.
            try await stop()
            let values = try result.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true, (values.fileSize ?? Int.max) <= 1_048_576,
                  let reply = try JSONSerialization.jsonObject(with: Data(contentsOf: result)) as? [String: Any],
                  reply["id"] as? String == id,
                  let code = reply["exitCode"] as? Int, (-255...255).contains(code),
                  let output = reply["output"] as? String, output.utf8.count <= 524_288,
                  let truncated = reply["truncated"] as? Bool else {
                throw VirtualMachineConfiguration.error("Некорректный результат гостевой системы")
            }
            try FileManager.default.moveItem(at: exchange.appendingPathComponent("workspace"), to: job.appendingPathComponent("workspace"))
            state = ["status": "FINISHED", "result": ["exitCode": code, "output": output, "truncated": truncated]]
        } catch {
            do { try await stop() } catch { state = ["status": "FAILED", "error": "Не удалось остановить VM"]; return }
            state = ["status": "FAILED", "error": error.localizedDescription]
        }
    }

    private func stop() async throws {
        guard let machine else { return }
        if machine.canStop { try await machine.stop() }
        guard machine.state == .stopped || machine.state == .error else { throw VirtualMachineConfiguration.error("VM ещё работает") }
        self.machine = nil
    }
}
