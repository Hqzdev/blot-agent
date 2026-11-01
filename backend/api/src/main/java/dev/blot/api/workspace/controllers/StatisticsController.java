package dev.blot.api.workspace.controllers;

import dev.blot.api.workspace.transport.RequestActor;
import dev.blot.application.workspace.statistics.StatisticsService;
import jakarta.servlet.http.HttpServletRequest;
import java.util.UUID;
import org.springframework.web.bind.annotation.*;

@RestController
public final class StatisticsController {
  private final StatisticsService statistics;
  private final RequestActor actors;

  public StatisticsController(StatisticsService statistics, RequestActor actors) {
    this.statistics = statistics;
    this.actors = actors;
  }

  @GetMapping("/v2/statistics")
  public StatisticsService.Statistics read(
      @RequestParam(required = false) UUID projectId, HttpServletRequest request) {
    return statistics.read(actors.require(request), projectId);
  }
}
