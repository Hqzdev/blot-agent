package dev.blot.application.workspace.library;

import dev.blot.application.ports.*;
import dev.blot.application.ports.WorkspaceStore;
import dev.blot.application.workspace.Records;
import dev.blot.application.workspace.WorkspaceFailure;
import dev.blot.application.workspace.agent.RoleCatalog;
import dev.blot.core.workspace.*;
import dev.blot.core.workspace.Entity;
import dev.blot.core.workspace.EntityKind;
import dev.blot.core.workspace.identity.Actor;
import dev.blot.core.workspace.projects.ProjectData;
import dev.blot.core.workspace.skills.SkillData;
import java.util.*;

public final class LibraryService {
  private final Records records;
  private final RoleCatalog roles;

  public LibraryService(Records records, RoleCatalog roles) {
    this.records = records;
    this.roles = roles;
  }

  public Entity<SkillData> saveSkill(
      WorkspaceStore.Transaction tx,
      Actor actor,
      UUID project,
      UUID id,
      Long version,
      SkillData data) {
    Records.text(data.name(), "name", 200);
    Records.text(data.instruction(), "instruction", 16000);
    if (data.roles() == null || data.roles().isEmpty() || !roles.roles().containsAll(data.roles()))
      throw WorkspaceFailure.invalid("Неверные роли навыка");
    if (project != null)
      Records.require(tx, EntityKind.PROJECT, actor.accountId(), project, ProjectData.class);
    if (id == null)
      return records.create(tx, EntityKind.SKILL, actor.accountId(), project, null, data);
    var old = Records.require(tx, EntityKind.SKILL, actor.accountId(), id, SkillData.class);
    Records.version(old, version);
    return records.change(tx, EntityKind.SKILL, old, data);
  }

  public void delete(
      WorkspaceStore.Transaction tx, Actor actor, EntityKind kind, UUID id, Long version) {
    if (!Set.of(EntityKind.SKILL, EntityKind.AUTOMATION).contains(kind))
      throw WorkspaceFailure.invalid("Неверный раздел");
    var e = Records.require(tx, kind, actor.accountId(), id, Object.class);
    Records.version(e, version);
    tx.delete(kind, actor.accountId(), id);
    tx.event(
        actor.accountId(), e.projectId(), kind.name().toLowerCase() + ".deleted", Map.of("id", id));
  }
}
