package dev.blot.cloud.web;

import dev.blot.cloud.identity.*;
import java.util.*;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/v1/devices")
public final class CloudDevicesController {
  public record Claim(UUID pairingID, String secret, CloudDevices.Registration device) {}

  private final CloudSessions sessions;
  private final CloudDevices devices;
  private final CloudPairings pairings;
  private final CloudDeviceRevocations revocations;

  public CloudDevicesController(
      CloudSessions sessions,
      CloudDevices devices,
      CloudPairings pairings,
      CloudDeviceRevocations revocations) {
    this.sessions = sessions;
    this.devices = devices;
    this.pairings = pairings;
    this.revocations = revocations;
  }

  @PostMapping("/bootstrap")
  public CloudDevices.Device bootstrap(
      @RequestHeader(value = "Authorization", required = false) String auth,
      @RequestBody CloudDevices.Registration request) {
    return devices.bootstrap(sessions.require(auth, false), request);
  }

  @GetMapping
  public List<CloudDevices.Device> list(
      @RequestHeader(value = "Authorization", required = false) String auth) {
    return devices.list(sessions.require(auth, true));
  }

  @PostMapping("/pairings")
  public CloudPairings.Invite start(
      @RequestHeader(value = "Authorization", required = false) String auth) {
    return pairings.start(sessions.require(auth, true));
  }

  @PostMapping("/pairings/claim")
  public CloudPairings.Status claim(
      @RequestHeader(value = "Authorization", required = false) String auth,
      @RequestBody Claim request) {
    return pairings.claim(
        sessions.require(auth, false), request.pairingID(), request.secret(), request.device());
  }

  @GetMapping("/pairings/{id}")
  public CloudPairings.Status inspect(
      @RequestHeader(value = "Authorization", required = false) String auth,
      @PathVariable UUID id) {
    return pairings.inspect(sessions.require(auth, true), id);
  }

  @PostMapping("/pairings/approve")
  public CloudPairings.Approved approve(
      @RequestHeader(value = "Authorization", required = false) String auth,
      @RequestBody CloudPairings.Approval request) {
    return pairings.approve(sessions.require(auth, true), request);
  }

  @GetMapping("/pairings/{id}/result")
  public CloudPairings.Approved result(
      @RequestHeader(value = "Authorization", required = false) String auth,
      @PathVariable UUID id) {
    return pairings.result(sessions.require(auth, false), id);
  }

  @PostMapping("/revoke")
  public CloudDeviceRevocations.Result revoke(
      @RequestHeader(value = "Authorization", required = false) String auth,
      @RequestBody CloudDeviceRevocations.Request request) {
    return revocations.revoke(sessions.require(auth, true), request);
  }

  @GetMapping("/keys")
  public List<CloudDeviceRevocations.KeyGrant> keys(
      @RequestHeader(value = "Authorization", required = false) String auth,
      @RequestParam(defaultValue = "0") long afterEpoch) {
    return revocations.keys(sessions.require(auth, true), afterEpoch);
  }
}
