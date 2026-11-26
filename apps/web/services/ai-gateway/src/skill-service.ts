import type {
  LoadedSkill,
  SkillDetail,
  SkillInput,
  SkillSummary,
} from '@teya/contracts';

import {
  SkillForbiddenError,
  SkillNotFoundError,
  SkillValidationError,
} from './skill-errors';
import type { SkillDetailRecord, SkillRepository } from './skill-repository';

const MAX_CUSTOM_SKILLS = 20;
const MAX_INSTALLED_SKILLS = 24;

export class SkillService {
  constructor(private readonly repository: SkillRepository) {}

  listSkills(userId: string, query?: string): Promise<SkillSummary[]> {
    return this.repository.listAccessibleSkills(
      userId,
      query?.trim() || undefined,
    );
  }

  async getSkill(userId: string, id: string): Promise<SkillDetail> {
    const skill = await this.requireAccessibleSkill(userId, id);
    return {
      ...skill,
      instructions: skill.source === 'custom' ? skill.instructions : null,
    };
  }

  async createSkill(userId: string, input: SkillInput): Promise<SkillDetail> {
    const [customCount, installedCount] = await Promise.all([
      this.repository.countCustomSkills(userId),
      this.repository.countInstalledSkills(userId),
    ]);
    if (customCount >= MAX_CUSTOM_SKILLS) {
      throw new SkillValidationError(
        `You can create up to ${MAX_CUSTOM_SKILLS} custom skills`,
      );
    }
    if (installedCount >= MAX_INSTALLED_SKILLS) {
      throw new SkillValidationError(
        `You can install up to ${MAX_INSTALLED_SKILLS} skills`,
      );
    }
    return this.repository.createCustomSkill(userId, this.normalize(input));
  }

  async updateSkill(
    userId: string,
    id: string,
    input: SkillInput,
  ): Promise<SkillDetail> {
    const skill = await this.requireCustomSkill(userId, id);
    return this.repository.updateCustomSkill(skill.id, this.normalize(input));
  }

  async deleteSkill(userId: string, id: string): Promise<void> {
    const skill = await this.requireCustomSkill(userId, id);
    await this.repository.deleteCustomSkill(skill.id);
  }

  async installSkill(userId: string, id: string): Promise<SkillSummary> {
    const skill = await this.requireAccessibleSkill(userId, id);
    if (skill.installed) {
      return skill;
    }
    if (
      (await this.repository.countInstalledSkills(userId)) >=
      MAX_INSTALLED_SKILLS
    ) {
      throw new SkillValidationError(
        `You can install up to ${MAX_INSTALLED_SKILLS} skills`,
      );
    }
    await this.repository.installSkill(userId, id);
    return { ...skill, installed: true };
  }

  async uninstallSkill(userId: string, id: string): Promise<SkillSummary> {
    const skill = await this.requireAccessibleSkill(userId, id);
    await this.repository.uninstallSkill(userId, id);
    return { ...skill, installed: false };
  }

  getInstalledSkillSummaries(userId: string): Promise<SkillSummary[]> {
    return this.repository.listInstalledSkills(userId);
  }

  async loadInstalledSkill(userId: string, id: string): Promise<LoadedSkill> {
    const skill = await this.repository.findInstalledSkill(userId, id);
    if (!skill) {
      throw new SkillNotFoundError('Installed skill not found');
    }
    return skill;
  }

  deleteUserData(userId: string): Promise<void> {
    return this.repository.deleteUserData(userId);
  }

  private async requireAccessibleSkill(
    userId: string,
    id: string,
  ): Promise<SkillDetailRecord> {
    const skill = await this.repository.findAccessibleSkill(userId, id);
    if (!skill) {
      throw new SkillNotFoundError('Skill not found');
    }
    return skill;
  }

  private async requireCustomSkill(
    userId: string,
    id: string,
  ): Promise<SkillDetailRecord> {
    const skill = await this.requireAccessibleSkill(userId, id);
    if (skill.source !== 'custom' || skill.ownerId !== userId) {
      throw new SkillForbiddenError('Built-in skills cannot be changed');
    }
    return skill;
  }

  private normalize(input: SkillInput): SkillInput {
    return {
      description: input.description.trim(),
      instructions: input.instructions.trim(),
      name: input.name.trim(),
      whenToUse: input.whenToUse.trim(),
    };
  }
}
