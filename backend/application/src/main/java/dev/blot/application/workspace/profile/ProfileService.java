package dev.blot.application.workspace.profile;

import dev.blot.application.ports.*;
import dev.blot.application.ports.ProviderGateway;
import dev.blot.application.ports.WorkspaceStore;
import dev.blot.application.workspace.Records;
import dev.blot.application.workspace.WorkspaceFailure;
import dev.blot.application.workspace.agent.RoleCatalog;
import dev.blot.application.workspace.commands.ToolDefinitions;
import dev.blot.application.workspace.providers.ProviderSettingsService;
import dev.blot.core.workspace.*;
import dev.blot.core.workspace.Entity;
import dev.blot.core.workspace.EntityKind;
import dev.blot.core.workspace.agent.AgentConfigurationData;
import dev.blot.core.workspace.agent.AgentSessionData;
import dev.blot.core.workspace.identity.Actor;
import dev.blot.core.workspace.profile.ProfileData;
import dev.blot.core.workspace.projects.ProjectData;
import java.util.*;

public final class ProfileService {
  private final WorkspaceStore store;
  private final Records records;
  private final RoleCatalog roles;
  private final ToolDefinitions tools;
  private final ProviderSettingsService settings;

  public ProfileService(
      WorkspaceStore store, Records records, RoleCatalog roles, ToolDefinitions tools) {
    this(store, records, roles, tools, new ProviderSettingsService(store, records));
  }

  public ProfileService(
      WorkspaceStore store,
      Records records,
      RoleCatalog roles,
      ToolDefinitions tools,
      ProviderSettingsService settings) {
    this.store = store;
    this.records = records;
    this.roles = roles;
    this.tools = tools;
    this.settings = settings;
  }

  public Entity<ProfileData> save(
      WorkspaceStore.Transaction tx,
      Actor actor,
      UUID project,
      UUID id,
      Long version,
      ProfileData data) {
    roles.instruction(data.role());
    Records.text(data.instruction(), "instruction", 16000);
    if (project != null)
      Records.require(tx, EntityKind.PROJECT, actor.accountId(), project, ProjectData.class);
    ProviderSettingsService.validate(data.settings());
    if (settings.managed() && !settings.get(tx, actor.accountId()).equals(data.settings()))
      throw new WorkspaceFailure(
          403, "configuration_managed", "Модель и лимиты задаёт владелец установки через .env");
    var available =
        tools.functions(data.role()).stream().map(ProviderGateway.Function::name).toList();
    if (data.tools() == null
        || !available.containsAll(data.tools())
        || data.maxTurns() < 1
        || data.maxTurns() > 64)
      throw WorkspaceFailure.invalid("Профиль запрашивает недоступные инструменты или лимиты");
    var duplicates =
        tx
            .list(EntityKind.PROFILE, actor.accountId(), null, null, ProfileData.class, 10000)
            .stream()
            .filter(
                e ->
                    Objects.equals(project, e.projectId())
                        && e.data().role().equals(data.role())
                        && !e.id().equals(id))
            .toList();
    if (!duplicates.isEmpty())
      throw WorkspaceFailure.conflict("Профиль этой роли уже существует в области");
    if (id == null)
      return records.create(tx, EntityKind.PROFILE, actor.accountId(), project, null, data);
    var old = Records.require(tx, EntityKind.PROFILE, actor.accountId(), id, ProfileData.class);
    Records.version(old, version);
    if (!Objects.equals(project, old.projectId()) || !old.data().role().equals(data.role()))
      throw WorkspaceFailure.invalid("Нельзя изменить область профиля");
    return records.change(tx, EntityKind.PROFILE, old, data);
  }

  public Optional<Entity<ProfileData>> select(
      WorkspaceStore.Transaction tx, UUID owner, UUID project, String role) {
    return tx.list(EntityKind.PROFILE, owner, null, null, ProfileData.class, 10000).stream()
        .filter(
            e ->
                e.data().role().equals(role)
                    && (e.projectId() == null || e.projectId().equals(project)))
        .sorted(Comparator.comparing((Entity<ProfileData> e) -> e.projectId() == null))
        .findFirst();
  }

  public String instruction(WorkspaceStore.Transaction tx, UUID owner, UUID project, String role) {
    return roles.instruction(role)
        + select(tx, owner, project, role)
            .map(e -> "\nДополнительная инструкция профиля:\n" + e.data().instruction())
            .orElse("");
  }

  public AgentConfigurationData freeze(
      WorkspaceStore.Transaction tx, UUID owner, UUID project, String role, UUID parent) {
    var profile = select(tx, owner, project, role);
    var options =
        settings.managed()
            ? settings.get(tx, owner)
            : profile.map(e -> e.data().settings()).orElseGet(() -> settings.get(tx, owner));
    var allowed =
        profile
            .map(e -> e.data().tools())
            .orElseGet(
                () -> tools.functions(role).stream().map(ProviderGateway.Function::name).toList());
    if (parent != null) {
      var parentSession =
          Records.require(tx, EntityKind.AGENT_SESSION, owner, parent, AgentSessionData.class);
      // Reviewer — независимое назначение, Mote наследует потолок возможностей родителя.
      if (!role.equals("REVIEWER") && parentSession.data().depth() == 0) {
        var parentConfig = config(tx, owner, parent);
        allowed =
            allowed.stream()
                .filter(parentConfig.tools()::contains)
                .filter(n -> !n.startsWith("agent_"))
                .toList();
      }
    }
    return new AgentConfigurationData(
        profile.map(Entity::id).orElse(null),
        profile.map(Entity::version).orElse(0L),
        options,
        List.copyOf(allowed),
        profile.map(e -> e.data().maxTurns()).orElse(32));
  }

  public AgentConfigurationData config(WorkspaceStore.Transaction tx, UUID owner, UUID session) {
    return tx
        .list(EntityKind.AGENT_CONFIGURATION, owner, null, session, AgentConfigurationData.class, 1)
        .stream()
        .findFirst()
        .orElseThrow(
            () ->
                new WorkspaceFailure(
                    409,
                    "session_configuration_missing",
                    "Сессия создана до обновления; повторите задачу новым назначением"))
        .data();
  }

  public AgentConfigurationData config(UUID owner, UUID session) {
    return store.transact(tx -> config(tx, owner, session));
  }
}
