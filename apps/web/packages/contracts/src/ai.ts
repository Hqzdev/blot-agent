import { z } from 'zod';

export const skillSourceSchema = z.enum(['built_in', 'custom']);
export const skillCategorySchema = z.enum([
  'featured',
  'productivity',
  'creativity',
  'developer_tools',
  'personal',
]);

export const skillInputSchema = z
  .object({
    description: z.string().trim().min(1).max(240),
    instructions: z.string().trim().min(1).max(8000),
    name: z.string().trim().min(1).max(80),
    whenToUse: z.string().trim().min(1).max(500),
  })
  .strict();

export const skillSummarySchema = z.object({
  category: skillCategorySchema,
  createdAt: z.coerce.date(),
  description: z.string(),
  icon: z.string(),
  id: z.string().uuid(),
  installed: z.boolean(),
  name: z.string(),
  ownerId: z.string().uuid().nullable(),
  sortOrder: z.number().int(),
  source: skillSourceSchema,
  updatedAt: z.coerce.date(),
  whenToUse: z.string(),
});

export const skillDetailSchema = skillSummarySchema.extend({
  instructions: z.string().nullable(),
});

export const loadedSkillSchema = z.object({
  id: z.string().uuid(),
  instructions: z.string(),
  name: z.string(),
});

export const skillOperationSchema = z.discriminatedUnion('operation', [
  z.object({
    operation: z.literal('listSkills'),
    payload: z.object({
      query: z.string().trim().max(80).optional(),
    }),
  }),
  z.object({
    operation: z.literal('getSkill'),
    payload: z.object({ id: z.string().uuid() }),
  }),
  z.object({
    operation: z.literal('createSkill'),
    payload: skillInputSchema,
  }),
  z.object({
    operation: z.literal('updateSkill'),
    payload: skillInputSchema.extend({ id: z.string().uuid() }),
  }),
  z.object({
    operation: z.literal('deleteSkill'),
    payload: z.object({ id: z.string().uuid() }),
  }),
  z.object({
    operation: z.literal('installSkill'),
    payload: z.object({ id: z.string().uuid() }),
  }),
  z.object({
    operation: z.literal('uninstallSkill'),
    payload: z.object({ id: z.string().uuid() }),
  }),
  z.object({
    operation: z.literal('getInstalledSkillSummaries'),
    payload: z.object({}),
  }),
  z.object({
    operation: z.literal('loadInstalledSkill'),
    payload: z.object({ id: z.string().uuid() }),
  }),
  z.object({
    operation: z.literal('deleteSkillUserData'),
    payload: z.object({ userId: z.string().uuid() }),
  }),
]);

export const webSearchRequestSchema = z
  .object({
    query: z.string().trim().min(2).max(500),
  })
  .strict();

export const searchResultSchema = z.object({
  snippet: z.string(),
  title: z.string(),
  url: z.string().url(),
});

export const searchImageSchema = z.object({
  alt: z.string().optional(),
  url: z.string().url(),
});

export const searchVideoSchema = z.object({
  title: z.string(),
  url: z.string().url(),
});

export const webSearchResponseSchema = z.object({
  formatted: z.string(),
  images: z.array(searchImageSchema),
  results: z.array(searchResultSchema),
  videos: z.array(searchVideoSchema),
});

export type WebSearchRequest = z.infer<typeof webSearchRequestSchema>;
export type WebSearchResponse = z.infer<typeof webSearchResponseSchema>;
export type SkillSource = z.infer<typeof skillSourceSchema>;
export type SkillCategory = z.infer<typeof skillCategorySchema>;
export type SkillInput = z.infer<typeof skillInputSchema>;
export type SkillSummary = z.infer<typeof skillSummarySchema>;
export type SkillDetail = z.infer<typeof skillDetailSchema>;
export type LoadedSkill = z.infer<typeof loadedSkillSchema>;
export type SkillOperation = z.infer<typeof skillOperationSchema>;
