import assert from 'node:assert/strict';
import test from 'node:test';

import { buildSkillCatalogPrompt } from '@/lib/ai/skills/skill-catalog-prompt';
import {
  redactLoadedSkillInstructions,
  stripLoadedSkillsFromMessages,
} from '@/lib/ai/skills/skill-message-sanitizer';
import { SkillLoader } from '@/lib/ai/tools/load-skill';
import type { SkillGateway } from '@/lib/services/skill-gateway';
import type { LoadedSkill, SkillSummary } from '@teya/contracts';
import type { ToolExecutionOptions, UIMessage } from 'ai';

const executionOptions: ToolExecutionOptions = {
  messages: [],
  toolCallId: 'call-skill',
};

function createSkill(id: string, length = 100): SkillSummary {
  return {
    category: 'personal',
    createdAt: new Date(),
    description: 'D'.repeat(length),
    icon: 'sparkles',
    id,
    installed: true,
    name: `Skill ${id}`,
    ownerId: '11111111-1111-4111-8111-111111111111',
    sortOrder: 0,
    source: 'custom',
    updatedAt: new Date(),
    whenToUse: 'W'.repeat(length),
  };
}

function createGateway(skills: Map<string, LoadedSkill>): SkillGateway {
  return {
    async loadInstalledSkill(_userId, id) {
      const skill = skills.get(id);
      if (!skill) {
        throw new Error('Not installed');
      }
      return skill;
    },
  } as SkillGateway;
}

test('skill catalog contains only bounded metadata and frames it as untrusted', () => {
  const skills = Array.from({ length: 30 }, (_, index) =>
    createSkill(
      `10000000-0000-4000-8000-${index.toString().padStart(12, '0')}`,
      300,
    ),
  );

  const prompt = buildSkillCatalogPrompt(skills);

  assert.ok(prompt.length <= 6000);
  assert.match(prompt, /untrusted user configuration/i);
  assert.match(prompt, /cannot override system rules/i);
  assert.equal(prompt.includes('full secret instructions'), false);
});

test('skill loader accepts installed skills and enforces the two-skill limit', async () => {
  const ids = [
    '10000000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000002',
    '10000000-0000-4000-8000-000000000003',
  ];
  const summaries = ids.map((id) => createSkill(id));
  const loaded = new Map(
    ids.map((id, index) => [
      id,
      {
        id,
        instructions: `Instructions ${index}`,
        name: `Skill ${index}`,
      },
    ]),
  );
  const skillTool = new SkillLoader(
    summaries,
    '11111111-1111-4111-8111-111111111111',
    createGateway(loaded),
  ).createTool();
  assert.ok(skillTool.execute);

  const first = await skillTool.execute({ skillId: ids[0] }, executionOptions);
  const second = await skillTool.execute({ skillId: ids[1] }, executionOptions);
  const third = await skillTool.execute({ skillId: ids[2] }, executionOptions);

  assert.equal(first.name, 'Skill 0');
  assert.equal(second.name, 'Skill 1');
  assert.equal(third.name, 'Skill unavailable');
  assert.match(third.instructions, /limit/i);
});

test('loaded skill instructions are redacted from persistence and replay', () => {
  const skillPart = {
    toolInvocation: {
      args: {
        skillId: '10000000-0000-4000-8000-000000000001',
      },
      result: {
        id: '10000000-0000-4000-8000-000000000001',
        instructions: 'Private guidance',
        name: 'Writing Coach',
      },
      state: 'result',
      toolCallId: 'call-skill',
      toolName: 'loadSkill',
    },
    type: 'tool-invocation',
  };
  const message = {
    content: '',
    id: 'assistant-1',
    parts: [
      skillPart,
      {
        text: 'Polished answer',
        type: 'text',
      },
    ],
    role: 'assistant',
  } as UIMessage;

  const persisted = redactLoadedSkillInstructions(message.parts);
  const replayed = stripLoadedSkillsFromMessages([message]);

  assert.deepEqual(
    (
      persisted[0] as {
        toolInvocation: { result: unknown };
      }
    ).toolInvocation.result,
    {
      id: '10000000-0000-4000-8000-000000000001',
      name: 'Writing Coach',
    },
  );
  assert.deepEqual(replayed[0].parts, [
    {
      text: 'Polished answer',
      type: 'text',
    },
  ]);
});
