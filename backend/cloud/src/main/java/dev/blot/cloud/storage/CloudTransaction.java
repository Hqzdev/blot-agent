package dev.blot.cloud.storage;

import java.sql.*;
import java.util.*;

public final class CloudTransaction {
  @FunctionalInterface
  public interface Row<T> {
    T read(ResultSet result) throws SQLException;
  }

  private final Connection connection;

  CloudTransaction(Connection connection) {
    this.connection = connection;
  }

  public int execute(String sql, Object... values) {
    try (var statement = connection.prepareStatement(sql)) {
      bind(statement, values);
      return statement.executeUpdate();
    } catch (SQLException failure) {
      throw CloudDatabase.failure(failure);
    }
  }

  public <T> List<T> query(String sql, Row<T> row, Object... values) {
    try (var statement = connection.prepareStatement(sql)) {
      bind(statement, values);
      try (var result = statement.executeQuery()) {
        var rows = new ArrayList<T>();
        while (result.next()) rows.add(row.read(result));
        return List.copyOf(rows);
      }
    } catch (SQLException failure) {
      throw CloudDatabase.failure(failure);
    }
  }

  public <T> Optional<T> one(String sql, Row<T> row, Object... values) {
    return query(sql, row, values).stream().findFirst();
  }

  private void bind(PreparedStatement statement, Object[] values) throws SQLException {
    for (int i = 0; i < values.length; i++) {
      Object value = values[i];
      if (value instanceof UUID) value = value.toString();
      if (value instanceof java.time.Instant instant) value = instant.toEpochMilli();
      statement.setObject(i + 1, value);
    }
  }
}
