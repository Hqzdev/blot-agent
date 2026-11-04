package dev.blot.cloud.web;

import dev.blot.application.ports.JsonCodec;
import dev.blot.cloud.identity.*;
import dev.blot.cloud.model.*;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.concurrent.atomic.AtomicBoolean;
import org.springframework.http.*;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.servlet.mvc.method.annotation.StreamingResponseBody;

@RestController
@RequestMapping("/v1/model")
public final class CloudModelController {
  private final CloudSessions sessions;
  private final CloudModelGateway model;
  private final CloudModelQuota quota;
  private final JsonCodec json;

  public CloudModelController(
      CloudSessions sessions, CloudModelGateway model, CloudModelQuota quota, JsonCodec json) {
    this.sessions = sessions;
    this.model = model;
    this.quota = quota;
    this.json = json;
  }

  @GetMapping("/usage")
  public CloudModelQuota.Usage usage(
      @RequestHeader(value = "Authorization", required = false) String auth) {
    return quota.usage(sessions.require(auth, true));
  }

  @PostMapping(value = "/chat/completions", produces = MediaType.TEXT_EVENT_STREAM_VALUE)
  public ResponseEntity<StreamingResponseBody> completion(
      @RequestHeader(value = "Authorization", required = false) String auth,
      @RequestBody CloudModelGateway.Completion request) {
    var prepared = model.prepare(sessions.require(auth, true), request);
    StreamingResponseBody stream =
        output -> {
          var disconnected = new AtomicBoolean();
          try {
            var reply =
                model.generate(
                    prepared,
                    text -> {
                      try {
                        write(
                            output,
                            Map.of("choices", List.of(Map.of("delta", Map.of("content", text)))));
                      } catch (IOException failure) {
                        disconnected.set(true);
                        throw new UncheckedIOException(failure);
                      }
                    },
                    () -> disconnected.get() || Thread.currentThread().isInterrupted());
            var result = new LinkedHashMap<String, Object>();
            result.put("choices", List.of(Map.of("delta", Map.of(), "finish_reason", "stop")));
            if (reply.inputTokens() != null && reply.outputTokens() != null)
              result.put(
                  "usage",
                  Map.of(
                      "prompt_tokens",
                      reply.inputTokens(),
                      "completion_tokens",
                      reply.outputTokens()));
            write(output, result);
            output.write("data: [DONE]\n\n".getBytes(StandardCharsets.UTF_8));
            output.flush();
          } catch (RuntimeException failure) {
            // A failed stream has no finish marker. Clients persist the partial response as
            // interrupted.
            if (!disconnected.get())
              write(output, Map.of("error", Map.of("code", "generation_interrupted")));
          }
        };
    return ResponseEntity.ok().header("X-Accel-Buffering", "no").body(stream);
  }

  private void write(OutputStream output, Object value) throws IOException {
    output.write(("data: " + json.write(value) + "\n\n").getBytes(StandardCharsets.UTF_8));
    output.flush();
  }
}
