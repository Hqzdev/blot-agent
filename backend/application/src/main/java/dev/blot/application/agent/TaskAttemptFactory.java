package dev.blot.application.agent;

import dev.blot.core.Task;
import dev.blot.core.agent.AgentAssignment;
import dev.blot.core.agent.AgentSession;
import dev.blot.core.agent.AssignmentStatus;
import dev.blot.core.agent.TaskAttempt;
import dev.blot.core.agent.TaskAttemptStatus;
import java.time.Clock;
import java.time.Instant;
import java.util.Objects;
import java.util.Optional;
import java.util.UUID;
import java.util.function.Supplier;

/** Starts an execution attempt only for a matching active assignment and running session. */
public final class TaskAttemptFactory {
  private final Clock clock;
  private final Supplier<UUID> idGenerator;

  public TaskAttemptFactory(Clock clock, Supplier<UUID> idGenerator) {
    this.clock = Objects.requireNonNull(clock, "clock");
    this.idGenerator = Objects.requireNonNull(idGenerator, "idGenerator");
  }

  public TaskAttempt start(
      Task task, AgentAssignment assignment, AgentSession session, int attemptNumber) {
    Objects.requireNonNull(task, "task");
    Objects.requireNonNull(assignment, "assignment");
    Objects.requireNonNull(session, "session");
    if (attemptNumber < 1) {
      throw new IllegalArgumentException("attemptNumber must be at least 1");
    }
    if (assignment.status() != AssignmentStatus.ACTIVE
        || assignment.sessionId().filter(session.id()::equals).isEmpty()) {
      throw new IllegalArgumentException("Attempt requires the session active on its assignment");
    }
    if (!task.id().equals(assignment.taskId())
        || !task.projectId().equals(assignment.projectId())
        || !task.runId().equals(assignment.runId())
        || !task.projectId().equals(session.projectId())
        || !task.runId().equals(session.runId())) {
      throw new IllegalArgumentException("Task, assignment, and session do not match");
    }
    if (session.status() != dev.blot.core.agent.AgentSessionStatus.RUNNING) {
      throw new IllegalArgumentException("Attempt requires a running agent session");
    }

    Instant now = clock.instant();
    return new TaskAttempt(
        Objects.requireNonNull(idGenerator.get(), "generated attempt id"),
        task.projectId(),
        task.runId(),
        task.id(),
        assignment.id(),
        session.id(),
        attemptNumber,
        TaskAttemptStatus.RUNNING,
        Optional.empty(),
        Optional.empty(),
        now,
        now,
        0);
  }
}
