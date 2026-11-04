package dev.blot.cloud.web;

import dev.blot.cloud.relay.*;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

@Component
public final class CloudMaintenance {
  private final CloudRelay relay;
  private final CloudEncryptedBlobs blobs;
  private final CloudSnapshots snapshots;

  public CloudMaintenance(CloudRelay relay, CloudEncryptedBlobs blobs, CloudSnapshots snapshots) {
    this.relay = relay;
    this.blobs = blobs;
    this.snapshots = snapshots;
  }

  @Scheduled(fixedDelay = 3_600_000, initialDelay = 0)
  public void expireCiphertext() {
    relay.purgeExpired();
    blobs.purgeExpired();
    snapshots.purgeExpired();
  }
}
