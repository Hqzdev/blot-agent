package dev.blot.core.workspace.agent;

import dev.blot.core.workspace.provider.ProviderSettingsData;
import java.util.*;

/** Неизменяемая конфигурация конкретной сессии; последующее редактирование профиля её не меняет. */
public record AgentConfigurationData(
    UUID profileId,
    long profileVersion,
    ProviderSettingsData settings,
    List<String> tools,
    int maxTurns) {
  public AgentConfigurationData {
    tools = tools == null ? null : java.util.List.copyOf(tools);
  }
}
