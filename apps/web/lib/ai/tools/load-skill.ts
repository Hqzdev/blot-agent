import type { LoadedSkill, SkillSummary } from '@teya/contracts';
import { tool } from 'ai';
import { z } from 'zod';

import type { SkillGateway } from '@/lib/services/skill-gateway';

const MAX_SKILLS_PER_RESPONSE = 2;
const INSTRUCTION_BUDGET = 16_000;

export class SkillLoader {
  private readonly availableSkillIds: Set<string>;
  private readonly loadedSkills = new Map<string, LoadedSkill>();
  private usedCharacters = 0;

  constructor(
    skills: SkillSummary[],
    private readonly userId: string,
    private readonly gateway: SkillGateway,
  ) {
    this.availableSkillIds = new Set(skills.map((skill) => skill.id));
  }

  createTool() {
    return tool({
      description:
        'Load the full instructions for one installed skill when that skill is relevant to the current request. Use the exact skill id from the installed skills catalog.',
      parameters: z.object({
        skillId: z.string().uuid(),
      }),
      execute: ({ skillId }: { skillId: string }) => this.load(skillId),
    });
  }

  private async load(skillId: string): Promise<LoadedSkill> {
    const cached = this.loadedSkills.get(skillId);
    if (cached) {
      return cached;
    }
    if (!this.availableSkillIds.has(skillId)) {
      return this.unavailable(skillId, 'This skill is not installed.');
    }
    if (this.loadedSkills.size >= MAX_SKILLS_PER_RESPONSE) {
      return this.unavailable(
        skillId,
        'The per-response skill limit has been reached.',
      );
    }
    try {
      const skill = await this.gateway.loadInstalledSkill(this.userId, skillId);
      const remaining = INSTRUCTION_BUDGET - this.usedCharacters;
      if (remaining <= 0) {
        return this.unavailable(
          skillId,
          'The per-response skill context budget has been reached.',
        );
      }
      const loaded = {
        ...skill,
        instructions: skill.instructions.slice(0, remaining),
      };
      this.usedCharacters += loaded.instructions.length;
      this.loadedSkills.set(skillId, loaded);
      return loaded;
    } catch {
      return this.unavailable(
        skillId,
        'The skill is temporarily unavailable. Continue without it.',
      );
    }
  }

  private unavailable(id: string, instructions: string): LoadedSkill {
    return {
      id,
      instructions,
      name: 'Skill unavailable',
    };
  }
}
