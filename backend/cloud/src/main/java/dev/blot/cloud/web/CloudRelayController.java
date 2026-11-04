package dev.blot.cloud.web;

import dev.blot.cloud.identity.CloudSessions;
import dev.blot.cloud.relay.*;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/v1/relay")
public final class CloudRelayController {
  public record Receipt(UUID changeID) {}

  public record Accepted(boolean accepted) {}

  public record Acknowledgement(long cursor) {}

  private final CloudSessions sessions;
  private final CloudRelay relay;
  private final CloudEncryptedBlobs blobs;

  public CloudRelayController(CloudSessions sessions, CloudRelay relay, CloudEncryptedBlobs blobs) {
    this.sessions = sessions;
    this.relay = relay;
    this.blobs = blobs;
  }

  @PostMapping("/changes")
  public Receipt upload(
      @RequestHeader(value = "Authorization", required = false) String auth,
      @RequestBody CloudPacket request) {
    return new Receipt(relay.upload(sessions.require(auth, true), request));
  }

  @GetMapping("/changes/{id}/receipt")
  public Accepted accepted(
      @RequestHeader(value = "Authorization", required = false) String auth,
      @PathVariable UUID id) {
    return new Accepted(relay.accepted(sessions.require(auth, true), id));
  }

  @GetMapping("/changes")
  public CloudRelay.Batch pull(
      @RequestHeader(value = "Authorization", required = false) String auth,
      @RequestParam(defaultValue = "0") long after,
      @RequestParam(defaultValue = "100") int limit) {
    return relay.pull(sessions.require(auth, true), after, limit);
  }

  @PostMapping("/ack")
  @ResponseStatus(HttpStatus.NO_CONTENT)
  public void acknowledge(
      @RequestHeader(value = "Authorization", required = false) String auth,
      @RequestBody Acknowledgement request) {
    relay.acknowledge(sessions.require(auth, true), request.cursor());
  }

  @PutMapping("/blobs")
  @ResponseStatus(HttpStatus.NO_CONTENT)
  public void putBlob(
      @RequestHeader(value = "Authorization", required = false) String auth,
      @RequestBody CloudEncryptedBlobs.Chunk request) {
    blobs.put(sessions.require(auth, true), request);
  }

  @GetMapping("/blobs/{id}/{index}")
  public CloudEncryptedBlobs.Chunk blob(
      @RequestHeader(value = "Authorization", required = false) String auth,
      @PathVariable UUID id,
      @PathVariable int index) {
    return blobs.get(sessions.require(auth, true), id, index);
  }
}
