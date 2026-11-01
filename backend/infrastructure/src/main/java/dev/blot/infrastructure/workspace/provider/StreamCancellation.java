package dev.blot.infrastructure.workspace.provider;

import java.io.*;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.function.BooleanSupplier;

/** Отмена должна разбудить readLine, даже когда провайдер перестал присылать фрагменты. */
final class StreamCancellation implements AutoCloseable {
  private final AtomicBoolean closed = new AtomicBoolean();
  private final Thread watcher;

  StreamCancellation(InputStream stream, BooleanSupplier cancelled) {
    watcher =
        Thread.startVirtualThread(
            () -> {
              try {
                long deadline =
                    System.nanoTime() + java.util.concurrent.TimeUnit.MINUTES.toNanos(3);
                while (!closed.get()) {
                  boolean stop;
                  try {
                    stop = cancelled.getAsBoolean() || System.nanoTime() >= deadline;
                  } catch (RuntimeException failure) {
                    stop = true;
                  }
                  if (stop) {
                    try {
                      stream.close();
                    } catch (IOException ignored) {
                    }
                    return;
                  }
                  Thread.sleep(200);
                }
              } catch (InterruptedException ignored) {
                Thread.currentThread().interrupt();
              }
            });
  }

  public void close() {
    closed.set(true);
    watcher.interrupt();
  }
}
