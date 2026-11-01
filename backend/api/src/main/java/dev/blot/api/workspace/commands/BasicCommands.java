package dev.blot.api.workspace.commands;

import dev.blot.application.ports.*;
import dev.blot.application.ports.JsonCodec;
import dev.blot.application.workspace.*;
import dev.blot.application.workspace.billing.BudgetService;
import dev.blot.application.workspace.commands.CommandDispatcher;
import dev.blot.application.workspace.conversation.ConversationService;
import dev.blot.application.workspace.conversation.MemoryService;
import dev.blot.application.workspace.identity.DeviceService;
import dev.blot.application.workspace.providers.ProviderSettingsService;
import dev.blot.core.workspace.*;
import dev.blot.core.workspace.conversation.MemoryData;
import dev.blot.core.workspace.provider.ProviderSettingsData;
import java.util.*;

public final class BasicCommands {
  record CreateConversation(String title) {}

  record SendMessage(UUID conversationId, String content) {}

  record Id(UUID id) {}

  record MemoryChange(UUID id, MemoryData data) {}

  record Increase(UUID id, long limit) {}

  public BasicCommands(
      CommandDispatcher d,
      JsonCodec json,
      ConversationService chat,
      MemoryService memory,
      ProviderSettingsService settings,
      DeviceService devices,
      BudgetService budgets) {
    d.register(
        "conversation.create",
        (tx, a, c) ->
            chat.create(
                tx, a, c.projectId(), json.convert(c.payload(), CreateConversation.class).title()));
    d.register(
        "conversation.send_message",
        (tx, a, c) -> {
          var v = json.convert(c.payload(), SendMessage.class);
          return chat.sendMessage(tx, a, v.conversationId(), v.content());
        });
    d.register(
        "generation.cancel",
        (tx, a, c) -> chat.cancel(tx, a, json.convert(c.payload(), Id.class).id()));
    d.register(
        "memory.save",
        (tx, a, c) -> {
          var v = json.convert(c.payload(), MemoryChange.class);
          return memory.save(tx, a, c.projectId(), v.id(), c.expectedVersion(), v.data());
        });
    d.register(
        "memory.delete",
        (tx, a, c) -> {
          memory.delete(tx, a, json.convert(c.payload(), Id.class).id(), c.expectedVersion());
          return Map.of("deleted", true);
        });
    d.register(
        "provider.settings",
        (tx, a, c) ->
            settings.save(
                tx, a, json.convert(c.payload(), ProviderSettingsData.class), c.expectedVersion()));
    d.register("device.pair", (tx, a, c) -> devices.create(tx, a));
    d.register(
        "device.approve",
        (tx, a, c) ->
            devices.approve(tx, a, json.convert(c.payload(), Id.class).id(), c.expectedVersion()));
    d.register(
        "device.revoke",
        (tx, a, c) -> {
          devices.revoke(tx, a, json.convert(c.payload(), Id.class).id());
          return Map.of("revoked", true);
        });
    d.register(
        "budget.increase",
        (tx, a, c) -> {
          var v = json.convert(c.payload(), Increase.class);
          return budgets.increase(tx, a, v.id(), c.expectedVersion(), v.limit());
        });
  }
}
