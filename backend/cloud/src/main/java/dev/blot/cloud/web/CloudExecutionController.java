package dev.blot.cloud.web;

import dev.blot.cloud.execution.CloudLeases;
import dev.blot.cloud.identity.CloudSessions;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/v1/execution")
public final class CloudExecutionController {
  public record Task(UUID taskID) {}

  public record Acquire(UUID taskID, UUID holderID) {}

  public record Authority(UUID taskID, UUID holderID, long generation) {}

  public record Action(UUID taskID, UUID holderID, long generation, UUID actionID, String digest) {}

  public record ActionResult(UUID taskID, UUID actionID, String digest, String state) {}

  private final CloudSessions sessions;
  private final CloudLeases leases;

  public CloudExecutionController(CloudSessions sessions, CloudLeases leases) {
    this.sessions = sessions;
    this.leases = leases;
  }

  @PostMapping("/tasks")
  @ResponseStatus(HttpStatus.NO_CONTENT)
  public void register(
      @RequestHeader(value = "Authorization", required = false) String auth,
      @RequestBody CloudLeases.Registration request) {
    leases.register(sessions.require(auth, true), request);
  }

  @PostMapping("/acquire")
  public CloudLeases.Lease acquire(
      @RequestHeader(value = "Authorization", required = false) String auth,
      @RequestBody Acquire request) {
    return leases.acquire(sessions.require(auth, true), request.taskID(), request.holderID());
  }

  @PostMapping("/renew")
  public CloudLeases.Lease renew(
      @RequestHeader(value = "Authorization", required = false) String auth,
      @RequestBody Authority request) {
    return leases.renew(
        sessions.require(auth, true), request.taskID(), request.holderID(), request.generation());
  }

  @PostMapping("/check")
  @ResponseStatus(HttpStatus.NO_CONTENT)
  public void check(
      @RequestHeader(value = "Authorization", required = false) String auth,
      @RequestBody Authority request) {
    leases.check(
        sessions.require(auth, true), request.taskID(), request.holderID(), request.generation());
  }

  @PostMapping("/release")
  @ResponseStatus(HttpStatus.NO_CONTENT)
  public void release(
      @RequestHeader(value = "Authorization", required = false) String auth,
      @RequestBody Authority request) {
    leases.release(
        sessions.require(auth, true), request.taskID(), request.holderID(), request.generation());
  }

  @PostMapping("/cancel")
  @ResponseStatus(HttpStatus.NO_CONTENT)
  public void cancel(
      @RequestHeader(value = "Authorization", required = false) String auth,
      @RequestBody Task request) {
    leases.cancel(sessions.require(auth, true), request.taskID());
  }

  @PostMapping("/actions/begin")
  @ResponseStatus(HttpStatus.NO_CONTENT)
  public void begin(
      @RequestHeader(value = "Authorization", required = false) String auth,
      @RequestBody Action request) {
    leases.beginAction(
        sessions.require(auth, true),
        request.taskID(),
        request.holderID(),
        request.generation(),
        request.actionID(),
        request.digest());
  }

  @PostMapping("/actions/finish")
  @ResponseStatus(HttpStatus.NO_CONTENT)
  public void finish(
      @RequestHeader(value = "Authorization", required = false) String auth,
      @RequestBody ActionResult request) {
    leases.finishAction(
        sessions.require(auth, true),
        request.taskID(),
        request.actionID(),
        request.digest(),
        request.state());
  }
}
