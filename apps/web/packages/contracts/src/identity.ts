import { z } from 'zod';

import { planSchema } from './billing';

export const customizationSchema = z
  .object({
    additional: z.string().max(4000).default(''),
    nickname: z.string().max(80).default(''),
    occupation: z.string().max(160).default(''),
    traits: z.array(z.string().max(40)).max(20),
  })
  .strict();

export const profileSchema = z.object({
  customization: customizationSchema.nullable(),
  email: z.string().email(),
  hasPassword: z.boolean(),
  id: z.string().uuid(),
  nickname: z.string(),
  subscription: planSchema,
});

export const updateProfileSchema = z
  .object({
    customization: customizationSchema,
  })
  .strict();

export const updateNicknameSchema = z
  .object({
    nickname: z.string().trim().min(3).max(32),
  })
  .strict();

export const updatePasswordSchema = z
  .object({
    currentPassword: z.string().min(1),
    newPassword: z.string().min(8).max(128),
  })
  .strict();

export const deleteAccountSchema = z
  .object({
    password: z.string().min(1).max(128).optional(),
  })
  .strict();

export const identityOperationSchema = z.discriminatedUnion('operation', [
  z.object({
    operation: z.literal('authenticate'),
    payload: z.object({
      nickname: z.string().min(3).max(32),
      password: z.string().min(1).max(128),
    }),
  }),
  z.object({
    operation: z.literal('register'),
    payload: z.object({
      email: z.string().email(),
      nickname: z.string().min(3).max(32),
      password: z.string().min(8).max(128),
    }),
  }),
  z.object({
    operation: z.literal('oauth'),
    payload: z.object({
      email: z.string().email(),
      name: z.string().max(160).nullish(),
    }),
  }),
  z.object({
    operation: z.literal('getUserById'),
    payload: z.object({ userId: z.string().uuid() }),
  }),
  z.object({
    operation: z.literal('getUserByEmail'),
    payload: z.object({ email: z.string().email() }),
  }),
  z.object({
    operation: z.literal('getUserByNickname'),
    payload: z.object({ nickname: z.string().min(3).max(32) }),
  }),
  z.object({
    operation: z.literal('updateCustomization'),
    payload: updateProfileSchema,
  }),
  z.object({
    operation: z.literal('updateNickname'),
    payload: updateNicknameSchema,
  }),
  z.object({
    operation: z.literal('updatePassword'),
    payload: updatePasswordSchema,
  }),
  z.object({
    operation: z.literal('deleteAccount'),
    payload: deleteAccountSchema,
  }),
  z.object({
    operation: z.literal('verifyPassword'),
    payload: deleteAccountSchema,
  }),
]);

export type Customization = z.infer<typeof customizationSchema>;
export type Profile = z.infer<typeof profileSchema>;
export type UpdateProfile = z.infer<typeof updateProfileSchema>;
export type IdentityOperation = z.infer<typeof identityOperationSchema>;
