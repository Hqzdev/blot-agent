package dev.blot.infrastructure.workspace.execution;

import dev.blot.application.ports.*;
import dev.blot.application.ports.JsonCodec;
import dev.blot.application.ports.ProcessGateway;
import dev.blot.application.workspace.WorkspaceFailure;
import java.nio.file.*;
import java.util.*;
import java.util.function.BooleanSupplier;

/** Системные программы запускает гостевая macOS, а не Java на Mac пользователя. */
public final class VirtualMachineProcessGateway implements ProcessGateway {
  private final Path jobs;
  private final java.util.concurrent.Semaphore queue = new java.util.concurrent.Semaphore(1, true);
  private final MacPlatformBridge platform;
  private final JsonCodec json;

  public VirtualMachineProcessGateway(Path jobs, MacPlatformBridge platform, JsonCodec json) {
    this.jobs = jobs.toAbsolutePath().normalize();
    this.platform = platform;
    this.json = json;
  }

  public Result run(
      Path workspace,
      List<String> scopes,
      String program,
      List<String> arguments,
      int timeout,
      BooleanSupplier cancelled) {
    if (!Set.of("gradle", "swift", "xcodebuild").contains(program)
        || timeout < 1
        || timeout > 1800
        || arguments.size() > 100
        || arguments.stream().anyMatch(a -> a.length() > 8192 || a.indexOf(0) >= 0))
      throw WorkspaceFailure.invalid("Неверный профиль процесса");
    String id = UUID.randomUUID().toString();
    Path job = jobs.resolve(id);
    boolean started = false;
    boolean acquired = false;
    try {
      while (!(acquired = queue.tryAcquire(200, java.util.concurrent.TimeUnit.MILLISECONDS)))
        if (cancelled.getAsBoolean())
          throw new WorkspaceFailure(409, "process_interrupted", "Ожидание VM отменено");
      if (cancelled.getAsBoolean())
        throw new WorkspaceFailure(409, "process_interrupted", "Ожидание VM отменено");
      Files.createDirectories(job);
      var transfer = new VmWorkspaceTransfer(workspace, job.resolve("workspace"), scopes);
      Files.writeString(
          job.resolve("request.json"),
          json.write(
              Map.of(
                  "id",
                  id,
                  "program",
                  program,
                  "arguments",
                  arguments,
                  "timeoutSeconds",
                  timeout)));
      platform.request(
          "vm.start", Map.of("id", id, "jobDirectory", job.toString(), "timeoutSeconds", timeout));
      started = true;
      long deadline =
          System.nanoTime() + java.util.concurrent.TimeUnit.SECONDS.toNanos(timeout + 120L);
      while (true) {
        if (cancelled.getAsBoolean()
            || Thread.currentThread().isInterrupted()
            || System.nanoTime() >= deadline)
          throw new WorkspaceFailure(409, "process_interrupted", "Выполнение в VM остановлено");
        Object value = platform.request("vm.status", Map.of("id", id));
        if (!(value instanceof Map<?, ?> state))
          throw new IllegalStateException("Invalid VM response");
        if ("FAILED".equals(state.get("status")))
          throw new WorkspaceFailure(
              503, "vm_failed", "VM не выполнила команду: " + state.get("error"));
        if ("FINISHED".equals(state.get("status"))) {
          // Mac возвращает FINISHED только после полной остановки гостевой системы.
          Result result = json.convert(state.get("result"), Result.class);
          transfer.importChanges();
          return result;
        }
        Thread.sleep(250);
      }
    } catch (WorkspaceFailure e) {
      throw e;
    } catch (Exception e) {
      if (e instanceof InterruptedException) Thread.currentThread().interrupt();
      throw new WorkspaceFailure(
          503, "vm_unavailable", "Виртуальная машина недоступна; проверьте её настройку на Mac");
    } finally {
      if (started) {
        try {
          platform.request("vm.release", Map.of("id", id));
        } catch (WorkspaceFailure ignored) {
          /* Каталог остаётся для диагностики, если Mac отключился. */
        }
      }
      if (!started && Files.exists(job)) {
        try (var files = Files.walk(job)) {
          for (Path path : files.sorted(Comparator.reverseOrder()).toList())
            Files.deleteIfExists(path);
        } catch (java.io.IOException ignored) {
          /* Невыполненное задание можно удалить при обслуживании. */
        }
      }
      if (acquired) queue.release();
    }
  }
}
