package dev.blot.cloud.web;

import dev.blot.cloud.collaboration.*;
import dev.blot.cloud.identity.*;
import java.util.*;
import org.springframework.http.*;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/v1/collaboration")
public final class CloudCollaborationController {
  public record TeamInput(String name) {}

  public record InviteInput(String email, String role) {}

  public record AcceptInput(String token) {}

  public record BotInput(int version, CloudTeams.BotConfiguration configuration) {}

  public record PublishInput(String kind, String title, String payload, int days) {}

  private final CloudSessions sessions;
  private final CloudTeams teams;
  private final CloudPublishedContent content;
  private final CloudPublicationRenderer renderer;

  public CloudCollaborationController(
      CloudSessions sessions,
      CloudTeams teams,
      CloudPublishedContent content,
      dev.blot.application.ports.JsonCodec json) {
    this.sessions = sessions;
    this.teams = teams;
    this.content = content;
    this.renderer = new CloudPublicationRenderer(json);
  }

  @GetMapping("/teams")
  public List<CloudTeams.Team> teams(
      @RequestHeader(value = "Authorization", required = false) String auth) {
    return teams.list(sessions.require(auth, false));
  }

  @PostMapping("/teams")
  public CloudTeams.Team create(
      @RequestHeader(value = "Authorization", required = false) String auth,
      @RequestBody TeamInput input) {
    return teams.create(sessions.require(auth, false), input.name);
  }

  @GetMapping("/teams/{team}/members")
  public List<CloudTeams.Member> members(
      @RequestHeader(value = "Authorization", required = false) String auth,
      @PathVariable UUID team) {
    return teams.members(sessions.require(auth, false), team);
  }

  @PostMapping("/teams/{team}/invites")
  public CloudTeams.Invite invite(
      @RequestHeader(value = "Authorization", required = false) String auth,
      @PathVariable UUID team,
      @RequestBody InviteInput input) {
    return teams.invite(sessions.require(auth, false), team, input.email, input.role);
  }

  @PostMapping("/invites/accept")
  @ResponseStatus(HttpStatus.NO_CONTENT)
  public void accept(
      @RequestHeader(value = "Authorization", required = false) String auth,
      @RequestBody AcceptInput input) {
    teams.accept(sessions.require(auth, false), input.token);
  }

  @DeleteMapping("/teams/{team}/members/{account}")
  @ResponseStatus(HttpStatus.NO_CONTENT)
  public void removeMember(
      @RequestHeader(value = "Authorization", required = false) String auth,
      @PathVariable UUID team,
      @PathVariable UUID account) {
    teams.removeMember(sessions.require(auth, false), team, account);
  }

  @GetMapping("/teams/{team}/bots")
  public List<CloudTeams.Bot> bots(
      @RequestHeader(value = "Authorization", required = false) String auth,
      @PathVariable UUID team) {
    return teams.bots(sessions.require(auth, false), team);
  }

  @PutMapping("/teams/{team}/bots/{id}")
  public CloudTeams.Bot saveBot(
      @RequestHeader(value = "Authorization", required = false) String auth,
      @PathVariable UUID team,
      @PathVariable UUID id,
      @RequestBody BotInput input) {
    return teams.saveBot(
        sessions.require(auth, true), team, id, input.version, input.configuration);
  }

  @DeleteMapping("/teams/{team}/bots/{id}")
  @ResponseStatus(HttpStatus.NO_CONTENT)
  public void deleteBot(
      @RequestHeader(value = "Authorization", required = false) String auth,
      @PathVariable UUID team,
      @PathVariable UUID id,
      @RequestParam int version) {
    teams.deleteBot(sessions.require(auth, false), team, id, version);
  }

  @PostMapping("/publications")
  public CloudPublishedContent.Link publish(
      @RequestHeader(value = "Authorization", required = false) String auth,
      @RequestBody PublishInput input) {
    return content.publish(
        sessions.require(auth, false), input.kind, input.title, input.payload, input.days);
  }

  @GetMapping("/publications")
  public List<CloudPublishedContent.Summary> publications(
      @RequestHeader(value = "Authorization", required = false) String auth) {
    return content.list(sessions.require(auth, false));
  }

  @DeleteMapping("/publications/{id}")
  @ResponseStatus(HttpStatus.NO_CONTENT)
  public void revoke(
      @RequestHeader(value = "Authorization", required = false) String auth,
      @PathVariable UUID id) {
    content.revoke(sessions.require(auth, false), id);
  }

  @GetMapping("/public/{token}")
  public ResponseEntity<CloudPublishedContent.Publication> read(@PathVariable String token) {
    return ResponseEntity.ok()
        .header("Cache-Control", "no-store")
        .header("Referrer-Policy", "no-referrer")
        .header("X-Content-Type-Options", "nosniff")
        .body(content.read(token));
  }

  @GetMapping(value = "/share/{token}", produces = MediaType.TEXT_HTML_VALUE)
  public ResponseEntity<String> share(@PathVariable String token) {
    return ResponseEntity.ok()
        .header("Cache-Control", "no-store")
        .header("Referrer-Policy", "no-referrer")
        .header(
            "Content-Security-Policy",
            "default-src 'none'; style-src 'unsafe-inline'; frame-ancestors 'none'; base-uri 'none'")
        .header("X-Content-Type-Options", "nosniff")
        .body(renderer.render(content.read(token)));
  }
}
