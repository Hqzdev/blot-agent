import type { Customization } from '@teya/contracts';
import { DatabaseConnectionProvider, blotProfiles } from '@teya/database';
import { eq } from 'drizzle-orm';

export class BlotProfileRepository {
  private get db() {
    return new DatabaseConnectionProvider().get().db;
  }

  async get(ownerID: string) {
    const [profile] = await this.db
      .select()
      .from(blotProfiles)
      .where(eq(blotProfiles.ownerId, ownerID))
      .limit(1);
    return profile;
  }

  async save(
    ownerID: string,
    patch: { nickname?: string; customization?: Customization },
  ) {
    await this.db
      .insert(blotProfiles)
      .values({ ownerId: ownerID, ...patch })
      .onConflictDoUpdate({
        target: blotProfiles.ownerId,
        set: { ...patch, updatedAt: new Date() },
      });
  }
}
