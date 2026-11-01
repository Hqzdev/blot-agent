package dev.blot.core.workspace.skills;

public record SkillData(
    String name, String instruction, java.util.List<String> roles, boolean enabled) {
  public SkillData {
    roles = roles == null ? null : java.util.List.copyOf(roles);
  }
}
