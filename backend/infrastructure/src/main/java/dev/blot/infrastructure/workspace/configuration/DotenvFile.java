package dev.blot.infrastructure.workspace.configuration;

import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;

/** Читает значения как данные: shell-команды и подстановки никогда не выполняются. */
public final class DotenvFile {
  public Map<String, Object> read(Path path) {
    try {
      if (!Files.isRegularFile(path) || Files.size(path) > 262144)
        throw new IllegalArgumentException("Нужен обычный .env размером до 256 KiB");
      return parse(Files.readString(path, StandardCharsets.UTF_8));
    } catch (IOException failure) {
      throw new IllegalArgumentException("Не удалось прочитать .env; проверьте путь и права");
    }
  }

  /** Первая строка приватного канала содержит только bootstrap; далее канал обслуживает broker. */
  public Map<String, Object> readEncoded(InputStream input) {
    try {
      var line = new ByteArrayOutputStream();
      int next;
      while ((next = input.read()) != '\n') {
        if (next < 0 || line.size() >= 349528)
          throw new IllegalArgumentException("Не удалось получить .env от приложения Mac");
        line.write(next);
      }
      byte[] data = Base64.getDecoder().decode(line.toByteArray());
      if (data.length > 262144) throw new IllegalArgumentException("Размер .env превышает 256 KiB");
      return parse(new String(data, StandardCharsets.UTF_8));
    } catch (IOException failure) {
      throw new IllegalArgumentException("Закрытый канал настроек Mac недоступен");
    }
  }

  private Map<String, Object> parse(String text) {
    var values = new LinkedHashMap<String, Object>();
    var lines = text.lines().toList();
    for (int index = 0; index < lines.size(); index++) {
      String line = lines.get(index).strip();
      if (index == 0 && line.startsWith("\uFEFF")) line = line.substring(1).strip();
      if (line.isEmpty() || line.startsWith("#")) continue;
      if (line.startsWith("export ")) line = line.substring(7).strip();
      int separator = line.indexOf('=');
      if (separator < 1) throw invalid(index);
      String key = line.substring(0, separator).strip();
      if (!key.matches("[A-Z][A-Z0-9_]*") || values.containsKey(key)) throw invalid(index);
      String value = line.substring(separator + 1).strip();
      if (value.startsWith("\"") || value.startsWith("'")) {
        char quote = value.charAt(0);
        if (value.length() < 2 || value.charAt(value.length() - 1) != quote) throw invalid(index);
        value = value.substring(1, value.length() - 1);
      }
      // Spring интерпретирует ${...}; в секретах такой синтаксис отклоняем явно.
      if (value.contains("${") || value.indexOf('\0') >= 0) throw invalid(index);
      values.put(key, value);
    }
    return Map.copyOf(values);
  }

  private IllegalArgumentException invalid(int index) {
    // Значение строки не попадает в диагностику, поскольку может содержать пароль.
    return new IllegalArgumentException("Некорректная строка .env: " + (index + 1));
  }
}
