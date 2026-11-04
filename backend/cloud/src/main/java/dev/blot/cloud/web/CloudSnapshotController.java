package dev.blot.cloud.web;

import dev.blot.cloud.identity.CloudSessions;
import dev.blot.cloud.relay.CloudSnapshots;
import java.util.*;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/v1/relay/snapshots")
public final class CloudSnapshotController {
  public record Input(UUID requestID, long minimumCursor) {}

  private final CloudSessions sessions;
  private final CloudSnapshots snapshots;

  public CloudSnapshotController(CloudSessions sessions, CloudSnapshots snapshots) {
    this.sessions = sessions;
    this.snapshots = snapshots;
  }

  @PostMapping
  public CloudSnapshots.Status request(
      @RequestHeader(value = "Authorization", required = false) String auth,
      @RequestBody Input input) {
    return snapshots.request(
        sessions.require(auth, true), input.requestID(), input.minimumCursor());
  }

  @GetMapping
  public List<CloudSnapshots.Request> pending(
      @RequestHeader(value = "Authorization", required = false) String auth) {
    return snapshots.pending(sessions.require(auth, true));
  }

  @GetMapping("/{id}")
  public CloudSnapshots.Status status(
      @RequestHeader(value = "Authorization", required = false) String auth,
      @PathVariable UUID id) {
    return snapshots.status(sessions.require(auth, true), id);
  }

  @PostMapping("/offers")
  @ResponseStatus(HttpStatus.NO_CONTENT)
  public void publish(
      @RequestHeader(value = "Authorization", required = false) String auth,
      @RequestBody CloudSnapshots.Offer offer) {
    snapshots.publish(sessions.require(auth, true), offer);
  }
}
