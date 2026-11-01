package dev.blot.infrastructure.workspace.git;

import dev.blot.application.workspace.WorkspaceFailure;
import java.nio.charset.StandardCharsets;
import java.nio.file.Path;
import java.util.*;
import java.util.concurrent.*;

final class GitCommandRunner {
  String run(Path root, String input, String... arguments) {
    var prefix =
        new ArrayList<String>(
            List.of(
                "/usr/bin/git",
                "--no-pager",
                "-c",
                "core.hooksPath=/dev/null",
                "-c",
                "core.fsmonitor=false",
                "-c",
                "submodule.recurse=false",
                "-c",
                "protocol.ext.allow=never",
                "-c",
                "protocol.allow=never",
                "-c",
                "protocol.https.allow=always",
                "-c",
                "protocol.ssh.allow=always",
                "-c",
                "protocol.file.allow=always",
                "-c",
                "credential.helper=",
                "-c",
                "core.sshCommand=/usr/bin/ssh",
                "-c",
                "diff.external=",
                "-c",
                "core.pager=cat",
                "-c",
                "commit.gpgsign=false"));
    var query = new ArrayList<>(prefix);
    query.addAll(
        List.of(
            "-C",
            root.toString(),
            "config",
            "--null",
            "--name-only",
            "--get-regexp",
            "^filter\\..*\\.(clean|smudge|process|required)$"));
    String keys = execute(query, null, true);
    for (String key : keys.split("\u0000"))
      if (!key.isBlank()) {
        prefix.add("-c");
        prefix.add(key + "=" + (key.endsWith(".required") ? "false" : ""));
      }
    prefix.addAll(
        List.of("-C", root.toString(), "--work-tree=" + root.toAbsolutePath().normalize()));
    prefix.addAll(List.of(arguments));
    return execute(prefix, input, false);
  }

  private void stop(Process process) {
    process.toHandle().descendants().forEach(child -> child.destroyForcibly());
    process.destroyForcibly();
  }

  private String execute(List<String> command, String input, boolean absentAllowed) {
    try {
      var builder = new ProcessBuilder(command).redirectErrorStream(true);
      builder.environment().keySet().removeIf(k -> k.startsWith("GIT_"));
      builder.environment().put("GIT_CONFIG_NOSYSTEM", "1");
      builder.environment().put("GIT_CONFIG_GLOBAL", "/dev/null");
      builder.environment().put("GIT_TERMINAL_PROMPT", "0");
      var process = builder.start();
      try (var reader = Executors.newVirtualThreadPerTaskExecutor()) {
        var output =
            reader.submit(
                () -> {
                  byte[] bytes = process.getInputStream().readNBytes(16_777_217);
                  if (bytes.length > 16_777_216) {
                    stop(process);
                    throw new java.io.IOException("Output limit");
                  }
                  return new String(bytes, StandardCharsets.UTF_8);
                });
        try (var stdin = process.getOutputStream()) {
          if (input != null) stdin.write(input.getBytes(StandardCharsets.UTF_8));
        }
        if (!process.waitFor(120, TimeUnit.SECONDS)) {
          stop(process);
          throw new WorkspaceFailure(503, "git_timeout", "Git превысил время ожидания");
        }
        String value = output.get(5, TimeUnit.SECONDS);
        if (process.exitValue() != 0) {
          if (absentAllowed && process.exitValue() == 1) return "";
          throw new WorkspaceFailure(
              409, "git_failed", "Операция Git отклонена; проверьте состояние репозитория");
        }
        return value;
      } finally {
        stop(process);
      }
    } catch (WorkspaceFailure e) {
      throw e;
    } catch (Exception e) {
      if (e instanceof InterruptedException) Thread.currentThread().interrupt();
      throw new WorkspaceFailure(503, "git_unavailable", "Git недоступен");
    }
  }
}
