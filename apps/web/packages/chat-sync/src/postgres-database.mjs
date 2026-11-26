export class PostgresBridgeDatabase {
  constructor(client) {
    this.client = client;
  }
  async query(sql, values = []) {
    return { rows: await this.client.unsafe(sql, values) };
  }
  async transaction(operation) {
    const connection = await this.client.reserve();
    try {
      await connection.unsafe('BEGIN');
      const result = await operation({
        async query(sql, values = []) {
          return { rows: await connection.unsafe(sql, values) };
        },
      });
      await connection.unsafe('COMMIT');
      return result;
    } catch (error) {
      await connection.unsafe('ROLLBACK');
      throw error;
    } finally {
      connection.release();
    }
  }
}
