package dev.blot.application.ports;

import java.util.*;
import java.util.function.Function;

/** Separate v3 history: no implicit conversion or deletion of v2 data. */
public interface V3Store {
  Set<UUID> owners();

  <T> T transact(UUID owner, Function<Transaction, T> operation);

  record Receipt(int schemaVersion, UUID commandId, UUID operationId, String state) {}

  record Accepted(String digest, Receipt receipt) {}

  record Record(String kind, UUID id, long version, Map<String, Object> value, boolean deleted) {}

  record Event(
      int schemaVersion,
      UUID eventId,
      long sequence,
      String kind,
      UUID recordId,
      long recordVersion,
      boolean deleted) {}

  record Page(long sequence, List<Record> records, String nextCursor) {}

  interface Transaction {
    Optional<Accepted> receipt(UUID commandId);

    void accept(UUID commandId, String digest, Receipt receipt);

    Optional<Record> find(String kind, UUID id);

    List<Record> records(String kind);

    void put(Record record);

    long sequence();

    Page snapshot(String cursor, int limit);

    List<Event> events(long after, int limit);
  }
}
