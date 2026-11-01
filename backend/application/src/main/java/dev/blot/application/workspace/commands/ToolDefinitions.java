package dev.blot.application.workspace.commands;

import dev.blot.application.ports.*;
import dev.blot.application.ports.ProviderGateway;
import dev.blot.core.workspace.*;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.atomic.*;

/** Описания доступных модели инструментов; системных действий здесь нет. */
public final class ToolDefinitions {
  public List<ProviderGateway.Function> functions(String role) {
    var result = new ArrayList<ProviderGateway.Function>();
    result.add(
        function(
            "project_read_file",
            "Прочитать UTF-8 файл в назначенной области",
            Map.of("path", string()),
            List.of("path")));
    result.add(
        function(
            "project_search",
            "Найти буквальный текст в файлах назначенной области",
            Map.of("query", string()),
            List.of("query")));
    result.add(
        function(
            "artifact_read",
            "Прочитать фрагмент результата",
            Map.of("artifactId", string(), "offset", Map.of("type", "integer")),
            List.of("artifactId")));
    result.add(
        function(
            "task_message",
            "Отправить сообщение другой сессии без изменения её прав",
            Map.of("recipientSessionId", string(), "content", string()),
            List.of("recipientSessionId", "content")));
    result.add(
        function(
            "user_ask",
            "Остановиться и спросить пользователя; ровно три варианта",
            Map.of(
                "question",
                string(),
                "options",
                Map.of("type", "array", "items", string(), "minItems", 3, "maxItems", 3)),
            List.of("question", "options")));
    if (Set.of("BACKEND", "FRONTEND", "BUILDER", "INTEGRATOR").contains(role)) {
      result.add(
          function(
              "patch_prepare",
              "Подготовить замену одного файла; возвращает preparedActionId",
              Map.of("path", string(), "content", string()),
              List.of("path", "content")));
      result.add(
          function(
              "patch_apply",
              "Применить подготовленное изменение после разрешения",
              Map.of("preparedActionId", string()),
              List.of("preparedActionId")));
    }
    if (Set.of(
            "BACKEND", "FRONTEND", "BUILDER", "REVIEWER", "CHECKER", "QA", "SECURITY", "INTEGRATOR")
        .contains(role))
      result.add(
          function(
              "process_run",
              "Запустить проверку через ограниченный runner после разрешения",
              Map.of(
                  "program",
                  Map.of("type", "string", "enum", List.of("gradle", "swift", "xcodebuild")),
                  "arguments",
                  Map.of("type", "array", "items", string()),
                  "timeoutSeconds",
                  Map.of("type", "integer")),
              List.of("program", "arguments")));
    if (Set.of("BACKEND", "FRONTEND", "INTEGRATOR", "RESEARCHER", "TECH_LEAD").contains(role)) {
      result.add(
          function(
              "agent_spawn",
              "Создать одну независимую подзадачу Mote; глубина ограничена сервером",
              Map.of(
                  "title",
                  string(),
                  "criteria",
                  Map.of("type", "array", "items", string()),
                  "role",
                  Map.of("type", "string", "enum", List.of("SCOUT", "BUILDER", "CHECKER")),
                  "paths",
                  Map.of("type", "array", "items", string())),
              List.of("title", "criteria", "role", "paths")));
      result.add(
          function(
              "agent_wait",
              "Получить результаты Motes; ожидание освобождает очередь модели",
              Map.of(),
              List.of()));
    }
    return List.copyOf(result);
  }

  private static Map<String, Object> string() {
    return Map.of("type", "string");
  }

  private static ProviderGateway.Function function(
      String name, String description, Map<String, Object> properties, List<String> required) {
    return new ProviderGateway.Function(
        name,
        description,
        Map.of(
            "type",
            "object",
            "properties",
            properties,
            "required",
            required,
            "additionalProperties",
            false));
  }
}
