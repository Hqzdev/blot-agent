import type { LoadedSkill, SkillInput, SkillSummary } from '@teya/contracts';
import {
  DatabaseConnectionProvider,
  type SkillRow,
  skills,
  userSkillInstallations,
} from '@teya/database';
import { and, asc, count, desc, eq, ilike, or } from 'drizzle-orm';

export interface SkillDetailRecord extends SkillSummary {
  instructions: string;
}

export interface SkillRepository {
  countCustomSkills(userId: string): Promise<number>;
  countInstalledSkills(userId: string): Promise<number>;
  createCustomSkill(
    userId: string,
    input: SkillInput,
  ): Promise<SkillDetailRecord>;
  deleteCustomSkill(id: string): Promise<void>;
  deleteUserData(userId: string): Promise<void>;
  findAccessibleSkill(
    userId: string,
    id: string,
  ): Promise<SkillDetailRecord | undefined>;
  findInstalledSkill(
    userId: string,
    id: string,
  ): Promise<LoadedSkill | undefined>;
  installSkill(userId: string, id: string): Promise<void>;
  listAccessibleSkills(userId: string, query?: string): Promise<SkillSummary[]>;
  listInstalledSkills(userId: string): Promise<SkillSummary[]>;
  uninstallSkill(userId: string, id: string): Promise<void>;
  updateCustomSkill(id: string, input: SkillInput): Promise<SkillDetailRecord>;
}

const summarySelection = {
  category: skills.category,
  createdAt: skills.createdAt,
  description: skills.description,
  icon: skills.icon,
  id: skills.id,
  name: skills.name,
  ownerId: skills.ownerId,
  sortOrder: skills.sortOrder,
  source: skills.source,
  updatedAt: skills.updatedAt,
  whenToUse: skills.whenToUse,
};

export class PostgresSkillRepository implements SkillRepository {
  private readonly db = new DatabaseConnectionProvider().get().db;

  async countCustomSkills(userId: string): Promise<number> {
    const [result] = await this.db
      .select({ value: count() })
      .from(skills)
      .where(and(eq(skills.source, 'custom'), eq(skills.ownerId, userId)));
    return result?.value ?? 0;
  }

  async countInstalledSkills(userId: string): Promise<number> {
    const [result] = await this.db
      .select({ value: count() })
      .from(userSkillInstallations)
      .where(eq(userSkillInstallations.userId, userId));
    return result?.value ?? 0;
  }

  async createCustomSkill(
    userId: string,
    input: SkillInput,
  ): Promise<SkillDetailRecord> {
    return this.db.transaction(async (transaction) => {
      const [created] = await transaction
        .insert(skills)
        .values({
          category: 'personal',
          description: input.description,
          icon: 'sparkles',
          instructions: input.instructions,
          name: input.name,
          ownerId: userId,
          sortOrder: 0,
          source: 'custom',
          whenToUse: input.whenToUse,
        })
        .returning();
      if (!created) {
        throw new Error('Skill creation returned no row');
      }
      await transaction.insert(userSkillInstallations).values({
        skillId: created.id,
        userId,
      });
      return this.toDetail(created, true);
    });
  }

  async deleteCustomSkill(id: string): Promise<void> {
    await this.db.delete(skills).where(eq(skills.id, id));
  }

  async deleteUserData(userId: string): Promise<void> {
    await this.db.transaction(async (transaction) => {
      await transaction
        .delete(userSkillInstallations)
        .where(eq(userSkillInstallations.userId, userId));
      await transaction.delete(skills).where(eq(skills.ownerId, userId));
    });
  }

  async findAccessibleSkill(
    userId: string,
    id: string,
  ): Promise<SkillDetailRecord | undefined> {
    const [row] = await this.db
      .select({
        ...summarySelection,
        installedUserId: userSkillInstallations.userId,
        instructions: skills.instructions,
      })
      .from(skills)
      .leftJoin(
        userSkillInstallations,
        and(
          eq(userSkillInstallations.skillId, skills.id),
          eq(userSkillInstallations.userId, userId),
        ),
      )
      .where(
        and(
          eq(skills.id, id),
          or(eq(skills.source, 'built_in'), eq(skills.ownerId, userId)),
        ),
      )
      .limit(1);
    return row
      ? {
          ...row,
          installed: row.installedUserId === userId,
        }
      : undefined;
  }

  async findInstalledSkill(
    userId: string,
    id: string,
  ): Promise<LoadedSkill | undefined> {
    const [row] = await this.db
      .select({
        id: skills.id,
        instructions: skills.instructions,
        name: skills.name,
      })
      .from(skills)
      .innerJoin(
        userSkillInstallations,
        and(
          eq(userSkillInstallations.skillId, skills.id),
          eq(userSkillInstallations.userId, userId),
        ),
      )
      .where(
        and(
          eq(skills.id, id),
          or(eq(skills.source, 'built_in'), eq(skills.ownerId, userId)),
        ),
      )
      .limit(1);
    return row;
  }

  async installSkill(userId: string, id: string): Promise<void> {
    await this.db
      .insert(userSkillInstallations)
      .values({ skillId: id, userId })
      .onConflictDoNothing();
  }

  async listAccessibleSkills(
    userId: string,
    query?: string,
  ): Promise<SkillSummary[]> {
    const accessible = or(
      eq(skills.source, 'built_in'),
      eq(skills.ownerId, userId),
    );
    const search = query
      ? or(
          ilike(skills.name, `%${query}%`),
          ilike(skills.description, `%${query}%`),
          ilike(skills.whenToUse, `%${query}%`),
        )
      : undefined;
    const rows = await this.db
      .select({
        ...summarySelection,
        installedUserId: userSkillInstallations.userId,
      })
      .from(skills)
      .leftJoin(
        userSkillInstallations,
        and(
          eq(userSkillInstallations.skillId, skills.id),
          eq(userSkillInstallations.userId, userId),
        ),
      )
      .where(search ? and(accessible, search) : accessible)
      .orderBy(asc(skills.category), asc(skills.sortOrder), asc(skills.name));
    return rows.map((row) => ({
      ...row,
      installed: row.installedUserId === userId,
    }));
  }

  async listInstalledSkills(userId: string): Promise<SkillSummary[]> {
    const rows = await this.db
      .select(summarySelection)
      .from(skills)
      .innerJoin(
        userSkillInstallations,
        eq(userSkillInstallations.skillId, skills.id),
      )
      .where(
        and(
          eq(userSkillInstallations.userId, userId),
          or(eq(skills.source, 'built_in'), eq(skills.ownerId, userId)),
        ),
      )
      .orderBy(desc(userSkillInstallations.createdAt), asc(skills.name));
    return rows.map((row) => ({ ...row, installed: true }));
  }

  async uninstallSkill(userId: string, id: string): Promise<void> {
    await this.db
      .delete(userSkillInstallations)
      .where(
        and(
          eq(userSkillInstallations.userId, userId),
          eq(userSkillInstallations.skillId, id),
        ),
      );
  }

  async updateCustomSkill(
    id: string,
    input: SkillInput,
  ): Promise<SkillDetailRecord> {
    const [updated] = await this.db
      .update(skills)
      .set({
        description: input.description,
        instructions: input.instructions,
        name: input.name,
        updatedAt: new Date(),
        whenToUse: input.whenToUse,
      })
      .where(eq(skills.id, id))
      .returning();
    if (!updated) {
      throw new Error('Skill update returned no row');
    }
    return this.toDetail(updated, true);
  }

  private toDetail(row: SkillRow, installed: boolean): SkillDetailRecord {
    return {
      category: row.category,
      createdAt: row.createdAt,
      description: row.description,
      icon: row.icon,
      id: row.id,
      installed,
      instructions: row.instructions,
      name: row.name,
      ownerId: row.ownerId,
      sortOrder: row.sortOrder,
      source: row.source,
      updatedAt: row.updatedAt,
      whenToUse: row.whenToUse,
    };
  }
}
