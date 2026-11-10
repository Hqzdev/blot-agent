package dev.blot.client;

import com.fasterxml.jackson.databind.*;
import com.fasterxml.jackson.datatype.jsr310.JavaTimeModule;
import java.io.IOException;

/** Shared wire codec; the only model sources remain contracts/v3/model.json and its generator. */
public final class WorkspaceJson {
  private final ObjectMapper mapper =
      new ObjectMapper()
          .registerModule(new JavaTimeModule())
          .disable(SerializationFeature.WRITE_DATES_AS_TIMESTAMPS)
          .disable(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES);

  public <T> T decode(String json, Class<T> type) throws IOException {
    return mapper.readValue(json, type);
  }

  public String encode(Object value) throws IOException {
    return mapper.writeValueAsString(value);
  }

  public JsonNode tree(String json) throws IOException {
    return mapper.readTree(json);
  }

  public <T> T convert(JsonNode value, Class<T> type) throws IOException {
    return mapper.treeToValue(value, type);
  }
}
