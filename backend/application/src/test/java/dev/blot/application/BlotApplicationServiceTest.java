package dev.blot.application;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertInstanceOf;
import static org.junit.jupiter.api.Assertions.assertThrows;

import dev.blot.core.Project;
import dev.blot.core.Run;
import dev.blot.core.RunStatus;
import dev.blot.core.SpecificationRevision;
import dev.blot.core.Task;
import java.nio.file.Path;
import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicLong;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

class BlotApplicationServiceTest {
  private final InMemoryUnitOfWork unitOfWork = new InMemoryUnitOfWork();
  private final AtomicLong ids = new AtomicLong(1);
  private final BlotApplicationService service =
      new BlotApplicationService(
          unitOfWork,
          Clock.fixed(Instant.parse("2026-01-01T00:00:00Z"), ZoneOffset.UTC),
          () -> new UUID(0, ids.getAndIncrement()));

  private Project project;
  private Run run;

  @BeforeEach
  void setUp() {
    project =
        value(
            service.createProject(
                new BlotApplicationService.CreateProject("Blot", Path.of("/repo"))));
    run =
        value(
            service.createRun(
                new BlotApplicationService.CreateRun(project.id(), "Build the backend")));
  }

  @Test
  void createsAndReadsProjectAndRecordsEventWithTheStateChange() {
    Project created =
        value(
            service.createProject(
                new BlotApplicationService.CreateProject(
                    "  Another project  ", Path.of("/tmp/../repo"))));

    assertEquals("Another project", created.name());
    assertEquals(Path.of("/repo"), created.repositoryPath());
    assertEquals(created, value(service.getProject(created.id())));
    assertEquals("project.created", unitOfWork.events.get(2).type());
    assertEquals(created.id(), unitOfWork.events.get(2).projectId());
    assertEquals(3, unitOfWork.events.size());
  }

  @Test
  void returnsTypedNotFoundWithoutWritingStateOrEvents() {
    int eventCount = unitOfWork.events.size();
    UUID missingId = new UUID(0, 999);

    ApplicationError.NotFound missing =
        assertInstanceOf(ApplicationError.NotFound.class, failure(service.getProject(missingId)));
    ApplicationError.NotFound missingRun =
        assertInstanceOf(
            ApplicationError.NotFound.class,
            failure(service.createRun(new BlotApplicationService.CreateRun(missingId, "goal"))));

    assertEquals("project", missing.resource());
    assertEquals("project", missingRun.resource());
    assertEquals(eventCount, unitOfWork.events.size());
  }

  @Test
  void changesRunStatusWithOptimisticVersionAndRejectsIllegalTransitions() {
    Run planning =
        value(
            service.changeRunStatus(
                new BlotApplicationService.ChangeRunStatus(run.id(), 0, RunStatus.PLANNING)));
    assertEquals(1, planning.version());

    ApplicationError.VersionConflict conflict =
        assertInstanceOf(
            ApplicationError.VersionConflict.class,
            failure(
                service.changeRunStatus(
                    new BlotApplicationService.ChangeRunStatus(run.id(), 0, RunStatus.RUNNING))));
    assertEquals(0, conflict.expected());
    assertEquals(1, conflict.actual());

    ApplicationError.InvalidTransition invalid =
        assertInstanceOf(
            ApplicationError.InvalidTransition.class,
            failure(
                service.changeRunStatus(
                    new BlotApplicationService.ChangeRunStatus(run.id(), 1, RunStatus.COMPLETED))));
    assertEquals(RunStatus.PLANNING, invalid.from());
    assertEquals(RunStatus.COMPLETED, invalid.to());
    assertEquals(planning, value(service.getRun(run.id())));
  }

  @Test
  void appendsImmutableSpecificationHistoryInRevisionOrder() {
    SpecificationRevision first =
        value(
            service.addSpecificationRevision(
                new BlotApplicationService.AddSpecificationRevision(
                    run.id(), "First requirements")));
    SpecificationRevision second =
        value(
            service.addSpecificationRevision(
                new BlotApplicationService.AddSpecificationRevision(
                    run.id(), "Updated requirements")));

    assertEquals(1, first.revision());
    assertEquals(2, second.revision());
    assertEquals(List.of(first, second), value(service.getSpecificationHistory(run.id())));
    assertEquals("specification.revision_created", unitOfWork.events.get(2).type());
    assertEquals("specification.revision_created", unitOfWork.events.get(3).type());
  }

  @Test
  void createsTasksOnlyWithDependenciesFromTheSameRun() {
    Task prerequisite =
        value(
            service.createTask(
                new BlotApplicationService.CreateTask(
                    project.id(), run.id(), "Build domain", List.of("Model exists"), Set.of())));
    Task dependent =
        value(
            service.createTask(
                new BlotApplicationService.CreateTask(
                    project.id(),
                    run.id(),
                    "Build application",
                    List.of("Use case exists"),
                    Set.of(prerequisite.id()))));
    Run otherRun =
        value(service.createRun(new BlotApplicationService.CreateRun(project.id(), "Other work")));

    ApplicationError.Conflict crossRunDependency =
        assertInstanceOf(
            ApplicationError.Conflict.class,
            failure(
                service.createTask(
                    new BlotApplicationService.CreateTask(
                        project.id(),
                        otherRun.id(),
                        "Invalid dependency",
                        List.of("Never created"),
                        Set.of(prerequisite.id())))));

    assertEquals("task dependency", crossRunDependency.resource());
    assertEquals(List.of(prerequisite, dependent), value(service.getTasks(run.id())));
  }

  @Test
  void returnsValidationErrorsForInvalidBoundaryInput() {
    ApplicationError.Validation invalidProject =
        assertInstanceOf(
            ApplicationError.Validation.class,
            failure(
                service.createProject(
                    new BlotApplicationService.CreateProject(" ", Path.of("relative")))));
    ApplicationError.Validation invalidRevision =
        assertInstanceOf(
            ApplicationError.Validation.class,
            failure(
                service.addSpecificationRevision(
                    new BlotApplicationService.AddSpecificationRevision(run.id(), "  "))));

    assertEquals("name", invalidProject.field());
    assertEquals("content", invalidRevision.field());
    assertEquals(2, unitOfWork.events.size());
  }

  @Test
  void rollsBackStateAndEventsWhenTheUnitOfWorkOperationThrows() {
    int eventCount = unitOfWork.events.size();

    assertThrows(
        IllegalStateException.class,
        () ->
            unitOfWork.transact(
                transaction -> {
                  transaction
                      .runs()
                      .save(
                          new Run(
                              run.id(),
                              run.projectId(),
                              run.goal(),
                              run.createdAt(),
                              RunStatus.RUNNING,
                              run.version() + 1));
                  transaction.appendEvent(
                      new ApplicationEvent(
                          new UUID(0, 1000),
                          run.projectId(),
                          run.id(),
                          run.id(),
                          1,
                          run.version() + 1,
                          run.createdAt(),
                          "run.status_changed",
                          Map.of("from", "DRAFT", "to", "RUNNING")));
                  throw new IllegalStateException("simulated storage failure");
                }));

    assertEquals(run, value(service.getRun(run.id())));
    assertEquals(eventCount, unitOfWork.events.size());
  }

  private static <T> T value(ApplicationResult<T> result) {
    ApplicationResult.Success<?> success =
        assertInstanceOf(ApplicationResult.Success.class, result);
    @SuppressWarnings("unchecked")
    T value = (T) success.value();
    return value;
  }

  private static ApplicationError failure(ApplicationResult<?> result) {
    return assertInstanceOf(ApplicationResult.Failure.class, result).error();
  }

  private static final class InMemoryUnitOfWork implements BlotUnitOfWork {
    private Map<UUID, Project> projects = new HashMap<>();
    private Map<UUID, Run> runs = new HashMap<>();
    private Map<UUID, SpecificationRevision> specifications = new HashMap<>();
    private Map<UUID, Task> tasks = new HashMap<>();
    private List<ApplicationEvent> events = new ArrayList<>();

    @Override
    public synchronized <T> T transact(java.util.function.Function<Transaction, T> operation) {
      Map<UUID, Project> nextProjects = new HashMap<>(projects);
      Map<UUID, Run> nextRuns = new HashMap<>(runs);
      Map<UUID, SpecificationRevision> nextSpecifications = new HashMap<>(specifications);
      Map<UUID, Task> nextTasks = new HashMap<>(tasks);
      List<ApplicationEvent> nextEvents = new ArrayList<>(events);
      Transaction transaction =
          new Transaction() {
            @Override
            public ProjectRepository projects() {
              return repository(nextProjects);
            }

            @Override
            public RunRepository runs() {
              return new RunRepository() {
                @Override
                public Optional<Run> findById(UUID runId) {
                  return Optional.ofNullable(nextRuns.get(runId));
                }

                @Override
                public void save(Run run) {
                  nextRuns.put(run.id(), run);
                }
              };
            }

            @Override
            public SpecificationRevisionRepository specifications() {
              return new SpecificationRevisionRepository() {
                @Override
                public List<SpecificationRevision> findByRunId(UUID runId) {
                  return nextSpecifications.values().stream()
                      .filter(revision -> revision.runId().equals(runId))
                      .toList();
                }

                @Override
                public void save(SpecificationRevision revision) {
                  nextSpecifications.put(revision.id(), revision);
                }
              };
            }

            @Override
            public TaskRepository tasks() {
              return new TaskRepository() {
                @Override
                public Optional<Task> findById(UUID taskId) {
                  return Optional.ofNullable(nextTasks.get(taskId));
                }

                @Override
                public List<Task> findByRunId(UUID runId) {
                  return nextTasks.values().stream()
                      .filter(task -> task.runId().equals(runId))
                      .toList();
                }

                @Override
                public void save(Task task) {
                  nextTasks.put(task.id(), task);
                }
              };
            }

            @Override
            public void appendEvent(ApplicationEvent event) {
              nextEvents.add(event);
            }
          };

      T result = operation.apply(transaction);
      projects = nextProjects;
      runs = nextRuns;
      specifications = nextSpecifications;
      tasks = nextTasks;
      events = nextEvents;
      return result;
    }

    private static ProjectRepository repository(Map<UUID, Project> values) {
      return new ProjectRepository() {
        @Override
        public Optional<Project> findById(UUID projectId) {
          return Optional.ofNullable(values.get(projectId));
        }

        @Override
        public void save(Project project) {
          values.put(project.id(), project);
        }
      };
    }
  }
}
