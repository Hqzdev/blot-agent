import {
  DatabaseConnectionProvider,
  type UserRow,
  users,
} from '@teya/database';
import { eq, sql } from 'drizzle-orm';

export interface CreateIdentityUser {
  email: string;
  nickname: string;
  password: string | null;
}

export interface IdentityUserRepository {
  create(input: CreateIdentityUser): Promise<UserRow>;
  delete(userId: string): Promise<void>;
  findByEmail(email: string): Promise<UserRow | undefined>;
  findById(userId: string): Promise<UserRow | undefined>;
  findByNickname(nickname: string): Promise<UserRow | undefined>;
  updateCustomization(userId: string, customization: unknown): Promise<UserRow>;
  updateNickname(userId: string, nickname: string): Promise<UserRow>;
  updatePassword(userId: string, password: string): Promise<UserRow>;
}

export class PostgresIdentityUserRepository implements IdentityUserRepository {
  private readonly db = new DatabaseConnectionProvider().get().db;

  async create(input: CreateIdentityUser): Promise<UserRow> {
    const [created] = await this.db
      .insert(users)
      .values({
        email: input.email.trim().toLowerCase(),
        nickname: input.nickname.trim().toLowerCase(),
        password: input.password,
      })
      .returning();

    if (!created) {
      throw new Error('User creation returned no row');
    }

    return created;
  }

  async delete(userId: string): Promise<void> {
    await this.db.delete(users).where(eq(users.id, userId));
  }

  async findByEmail(email: string): Promise<UserRow | undefined> {
    const [found] = await this.db
      .select()
      .from(users)
      .where(sql`lower(${users.email}) = ${email.trim().toLowerCase()}`)
      .limit(1);
    return found;
  }

  async findById(userId: string): Promise<UserRow | undefined> {
    const [found] = await this.db
      .select()
      .from(users)
      .where(eq(users.id, userId))
      .limit(1);
    return found;
  }

  async findByNickname(nickname: string): Promise<UserRow | undefined> {
    const [found] = await this.db
      .select()
      .from(users)
      .where(sql`lower(${users.nickname}) = ${nickname.trim().toLowerCase()}`)
      .limit(1);
    return found;
  }

  async updateCustomization(
    userId: string,
    customization: unknown,
  ): Promise<UserRow> {
    return this.update(userId, { customization });
  }

  async updateNickname(userId: string, nickname: string): Promise<UserRow> {
    return this.update(userId, { nickname: nickname.trim().toLowerCase() });
  }

  async updatePassword(userId: string, password: string): Promise<UserRow> {
    return this.update(userId, { password });
  }

  private async update(
    userId: string,
    values: Partial<Pick<UserRow, 'customization' | 'nickname' | 'password'>>,
  ): Promise<UserRow> {
    const [updated] = await this.db
      .update(users)
      .set({
        ...values,
        updatedAt: new Date(),
      })
      .where(eq(users.id, userId))
      .returning();

    if (!updated) {
      throw new Error('User update returned no row');
    }

    return updated;
  }
}
