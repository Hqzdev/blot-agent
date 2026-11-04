package dev.blot.cloud.identity;

import dev.blot.cloud.CloudFailure;
import java.io.*;
import java.math.BigInteger;
import java.nio.charset.StandardCharsets;
import java.security.*;
import java.security.spec.*;
import java.util.*;

public final class CloudDeviceProof {
  private CloudDeviceProof() {}

  public static PublicKey key(byte[] raw) {
    if (raw == null || raw.length != 65 || raw[0] != 4)
      throw new CloudFailure(400, "invalid_public_key");
    try {
      var parameters = AlgorithmParameters.getInstance("EC");
      parameters.init(new ECGenParameterSpec("secp256r1"));
      var curve = parameters.getParameterSpec(ECParameterSpec.class);
      BigInteger x = new BigInteger(1, Arrays.copyOfRange(raw, 1, 33)),
          y = new BigInteger(1, Arrays.copyOfRange(raw, 33, 65));
      BigInteger p = ((ECFieldFp) curve.getCurve().getField()).getP();
      if (x.compareTo(p) >= 0
          || y.compareTo(p) >= 0
          || !y.multiply(y)
              .mod(p)
              .equals(
                  x.multiply(x)
                      .multiply(x)
                      .add(curve.getCurve().getA().multiply(x))
                      .add(curve.getCurve().getB())
                      .mod(p))) throw new CloudFailure(400, "invalid_public_key");
      return KeyFactory.getInstance("EC")
          .generatePublic(new ECPublicKeySpec(new ECPoint(x, y), curve));
    } catch (GeneralSecurityException failure) {
      throw new CloudFailure(400, "invalid_public_key");
    }
  }

  public static void verify(byte[] publicKey, byte[] message, byte[] signature) {
    if (signature == null || signature.length > 144)
      throw new CloudFailure(403, "device_proof_invalid");
    try {
      var verifier = Signature.getInstance("SHA256withECDSA");
      verifier.initVerify(key(publicKey));
      verifier.update(message);
      if (!verifier.verify(signature)) throw new CloudFailure(403, "device_proof_invalid");
    } catch (GeneralSecurityException failure) {
      throw new CloudFailure(403, "device_proof_invalid");
    }
  }

  public static byte[] message(String domain, List<UUID> ids, List<byte[]> values) {
    try {
      var buffer = new ByteArrayOutputStream();
      var output = new DataOutputStream(buffer);
      output.write(domain.getBytes(StandardCharsets.US_ASCII));
      output.writeByte(0);
      for (UUID id : ids) {
        output.writeLong(id.getMostSignificantBits());
        output.writeLong(id.getLeastSignificantBits());
      }
      for (byte[] value : values) {
        output.writeInt(value.length);
        output.write(value);
      }
      return buffer.toByteArray();
    } catch (IOException impossible) {
      throw new IllegalStateException(impossible);
    }
  }
}
