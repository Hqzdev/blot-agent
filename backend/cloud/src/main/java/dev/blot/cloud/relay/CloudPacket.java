package dev.blot.cloud.relay;

import dev.blot.cloud.CloudFailure;
import dev.blot.cloud.identity.CloudDeviceProof;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.util.UUID;

public record CloudPacket(
    String kind,
    UUID workspaceID,
    UUID originDeviceID,
    UUID changeID,
    long sequence,
    long keyEpoch,
    byte[] ciphertext,
    byte[] signature) {
  public CloudPacket {
    ciphertext = ciphertext == null ? null : ciphertext.clone();
    signature = signature == null ? null : signature.clone();
  }

  @Override
  public byte[] ciphertext() {
    return ciphertext == null ? null : ciphertext.clone();
  }

  @Override
  public byte[] signature() {
    return signature == null ? null : signature.clone();
  }

  public void verify(byte[] publicKey) {
    if (!"change".equals(kind)
        || workspaceID == null
        || originDeviceID == null
        || changeID == null
        || sequence <= 0
        || keyEpoch <= 0
        || ciphertext == null
        || ciphertext.length < 28
        || ciphertext.length > 524_316) throw new CloudFailure(400, "invalid_packet");
    try {
      var buffer = new ByteArrayOutputStream();
      var output = new DataOutputStream(buffer);
      output.write("BLOT-APPLE-SYNC-1".getBytes(StandardCharsets.US_ASCII));
      output.writeByte(1);
      for (UUID id : new UUID[] {workspaceID, originDeviceID, changeID}) {
        output.writeLong(id.getMostSignificantBits());
        output.writeLong(id.getLeastSignificantBits());
      }
      output.writeLong(sequence);
      output.writeLong(keyEpoch);
      output.write(ciphertext);
      CloudDeviceProof.verify(publicKey, buffer.toByteArray(), signature);
    } catch (IOException impossible) {
      throw new IllegalStateException(impossible);
    }
  }
}
