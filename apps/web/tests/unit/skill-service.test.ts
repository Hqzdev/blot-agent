import assert from 'node:assert/strict';
import test from 'node:test';

import type { LoadedSkill, SkillInput, SkillSummary } from '@teya/contracts';
import {
  type SkillDetailRecord,
  SkillForbiddenError,
  SkillNotFoundError,
  type SkillRepository,
  SkillService,
  SkillValidationError,
} from '@teya/service-ai-gateway';

const ownerId = '11111111-1111-4111-8111-111111111111';
const otherUserId = '22222222-2222-4222-8222-222222222222';
const builtInId = '33333333-3333-4333-8333-333333333333';
const ownerSkillId = '44444444-4444-4444-8444-444444444444';
const otherSkillId = '55555555-5555-4555-8555-555555555555';

const skillInput: SkillInput = {
  description: 'Improves focused writing',
  instructions: 'Preserve meaning and improve clarity.',
  name: 'Writing Helper',
  whenToUse: 'Use when the user asks to revise text.',
};

class SkillRepositoryFake implements SkillRepository {
  readonly skills = new Map<string, SkillDetailRecord>([
    [builtInId, this.createSkill(builtInId, null, 'built_in', false)],
    [ownerSkillId, this.createSkill(ownerSkillId, ownerId, 'custom', true)],
    [otherSkillId, this.createSkill(otherSkillId, otherUserId, 'custom', true)],
  ]);
  readonly installations = new Map<string, Set<string>>([
    [ownerId, new Set([ownerSkillId])],
    [otherUserId, new Set([otherSkillId])],
  ]);
  private createdSkillIndex = 0;

  async countCustomSkills(userId: string): Promise<number> {
    return [...this.skills.values()].filter(
      (skill) => skill.source === 'custom' && skill.ownerId === userId,
    ).length;
  }

  async countInstalledSkills(userId: string): Promise<number> {
    return this.installations.get(userId)?.size ?? 0;
  }

  async createCustomSkill(
    userId: string,
    input: SkillInput,
  ): Promise<SkillDetailRecord> {
    this.createdSkillIndex += 1;
    const id = `90000000-0000-4000-8000-${this.createdSkillIndex
      .toString()
      .padStart(12, '0')}`;
    const skill: SkillDetailRecord = {
      category: 'personal',
      createdAt: new Date(),
      description: input.description,
      icon: 'sparkles',
      id,
      installed: true,
      instructions: input.instructions,
      name: input.name,
      ownerId: userId,
      sortOrder: 0,
      source: 'custom',
      updatedAt: new Date(),
      whenToUse: input.whenToUse,
    };
    this.skills.set(id, skill);
    this.installations.set(
      userId,
      new Set([...(this.installations.get(userId) ?? []), id]),
    );
    return skill;
  }

  async deleteCustomSkill(id: string): Promise<void> {
    this.skills.delete(id);
    for (const installation of this.installations.values()) {
      installation.delete(id);
    }
  }

  async deleteUserData(userId: string): Promise<void> {
    this.installations.delete(userId);
    for (const skill of this.skills.values()) {
      if (skill.ownerId === userId) {
        this.skills.delete(skill.id);
      }
    }
  }

  async findAccessibleSkill(
    userId: string,
    id: string,
  ): Promise<SkillDetailRecord | undefined> {
    const skill = this.skills.get(id);
    if (!skill || (skill.source === 'custom' && skill.ownerId !== userId)) {
      return undefined;
    }
    return {
      ...skill,
      installed: this.installations.get(userId)?.has(id) ?? false,
    };
  }

  async findInstalledSkill(
    userId: string,
    id: string,
  ): Promise<LoadedSkill | undefined> {
    const skill = await this.findAccessibleSkill(userId, id);
    return skill?.installed
      ? {
          id: skill.id,
          instructions: skill.instructions,
          name: skill.name,
        }
      : undefined;
  }

  async installSkill(userId: string, id: string): Promise<void> {
    const installations = this.installations.get(userId) ?? new Set<string>();
    installations.add(id);
    this.installations.set(userId, installations);
  }

  async listAccessibleSkills(
    userId: string,
    query?: string,
  ): Promise<SkillSummary[]> {
    const normalizedQuery = query?.toLowerCase();
    return [...this.skills.values()]
      .filter(
        (skill) => skill.source === 'built_in' || skill.ownerId === userId,
      )
      .filter(
        (skill) =>
          !normalizedQuery ||
          `${skill.name} ${skill.description} ${skill.whenToUse}`
            .toLowerCase()
            .includes(normalizedQuery),
      )
      .map((skill) => ({
        ...skill,
        installed: this.installations.get(userId)?.has(skill.id) ?? false,
      }));
  }

  async listInstalledSkills(userId: string): Promise<SkillSummary[]> {
    const ids = this.installations.get(userId) ?? new Set<string>();
    return [...ids].flatMap((id) => {
      const skill = this.skills.get(id);
      return skill ? [{ ...skill, installed: true }] : [];
    });
  }

  async uninstallSkill(userId: string, id: string): Promise<void> {
    this.installations.get(userId)?.delete(id);
  }

  async updateCustomSkill(
    id: string,
    input: SkillInput,
  ): Promise<SkillDetailRecord> {
    const skill = this.skills.get(id);
    assert.ok(skill);
    const updated = {
      ...skill,
      ...input,
      updatedAt: new Date(),
    };
    this.skills.set(id, updated);
    return updated;
  }

  addCustomSkills(userId: string, count: number) {
    for (let index = 0; index < count; index += 1) {
      const id = `80000000-0000-4000-8000-${index
        .toString()
        .padStart(12, '0')}`;
      this.skills.set(id, this.createSkill(id, userId, 'custom', false));
    }
  }

  addInstallations(userId: string, count: number) {
    const installations = this.installations.get(userId) ?? new Set<string>();
    for (let index = 0; index < count; index += 1) {
      installations.add(
        `70000000-0000-4000-8000-${index.toString().padStart(12, '0')}`,
      );
    }
    this.installations.set(userId, installations);
  }

  private createSkill(
    id: string,
    owner: string | null,
    source: 'built_in' | 'custom',
    installed: boolean,
  ): SkillDetailRecord {
    return {
      category: source === 'custom' ? 'personal' : 'featured',
      createdAt: new Date(),
      description: `${source} description`,
      icon: source === 'custom' ? 'sparkles' : 'writing',
      id,
      installed,
      instructions: `${source} instructions`,
      name: `${source} skill`,
      ownerId: owner,
      sortOrder: 0,
      source,
      updatedAt: new Date(),
      whenToUse: `${source} trigger`,
    };
  }
}

test('skill catalog exposes built-ins and only the actor custom skills', async () => {
  const service = new SkillService(new SkillRepositoryFake());

  const skills = await service.listSkills(ownerId);

  assert.deepEqual(
    skills.map((skill) => skill.id).sort(),
    [builtInId, ownerSkillId].sort(),
  );
});

test('custom skill access is owner-only and built-ins are immutable', async () => {
  const service = new SkillService(new SkillRepositoryFake());

  await assert.rejects(
    () => service.updateSkill(ownerId, otherSkillId, skillInput),
    SkillNotFoundError,
  );
  await assert.rejects(
    () => service.updateSkill(ownerId, builtInId, skillInput),
    SkillForbiddenError,
  );
});

test('custom skills are installed on creation and cascade on deletion', async () => {
  const repository = new SkillRepositoryFake();
  const service = new SkillService(repository);

  const created = await service.createSkill(ownerId, skillInput);

  assert.equal(created.installed, true);
  assert.equal(
    (await service.loadInstalledSkill(ownerId, created.id)).instructions,
    skillInput.instructions,
  );

  await service.deleteSkill(ownerId, created.id);

  assert.equal(repository.skills.has(created.id), false);
  assert.equal(repository.installations.get(ownerId)?.has(created.id), false);
});

test('skill installation is idempotent and respects limits', async () => {
  const repository = new SkillRepositoryFake();
  const service = new SkillService(repository);

  await service.installSkill(ownerId, builtInId);
  await service.installSkill(ownerId, builtInId);

  assert.equal(repository.installations.get(ownerId)?.has(builtInId), true);

  repository.addInstallations(ownerId, 24);
  await assert.rejects(
    () => service.createSkill(ownerId, skillInput),
    SkillValidationError,
  );

  const customLimitRepository = new SkillRepositoryFake();
  customLimitRepository.addCustomSkills(ownerId, 20);
  await assert.rejects(
    () =>
      new SkillService(customLimitRepository).createSkill(ownerId, skillInput),
    SkillValidationError,
  );
});
