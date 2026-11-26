import type { Customization } from '@teya/contracts';
import type { UserRow } from '@teya/database';
import { compare, genSaltSync, hashSync } from 'bcrypt-ts';

import {
  IdentityConflictError,
  IdentityNotFoundError,
  IdentityUnauthorizedError,
} from './errors';
import type { IdentityUserRepository } from './repository';

export interface AuthenticatedIdentity {
  email: string;
  id: string;
  nickname: string;
}

export class PasswordHasher {
  hash(password: string): string {
    return hashSync(password, genSaltSync(12));
  }

  verify(password: string, hash: string): Promise<boolean> {
    return compare(password, hash);
  }
}

export class IdentityService {
  constructor(
    private readonly repository: IdentityUserRepository,
    private readonly passwordHasher: PasswordHasher,
  ) {}

  async authenticate(
    nickname: string,
    password: string,
  ): Promise<AuthenticatedIdentity | null> {
    const user = await this.repository.findByNickname(nickname);
    if (
      !user?.password ||
      !(await this.passwordHasher.verify(password, user.password))
    ) {
      return null;
    }
    return this.toAuthenticatedIdentity(user);
  }

  async register(
    email: string,
    password: string,
    nickname: string,
  ): Promise<AuthenticatedIdentity> {
    const [existingEmail, existingNickname] = await Promise.all([
      this.repository.findByEmail(email),
      this.repository.findByNickname(nickname),
    ]);
    if (existingEmail) {
      throw new IdentityConflictError('Email is already registered');
    }
    if (existingNickname) {
      throw new IdentityConflictError('Nickname is already registered');
    }
    const created = await this.repository.create({
      email,
      nickname,
      password: this.passwordHasher.hash(password),
    });
    return this.toAuthenticatedIdentity(created);
  }

  async getOrCreateOAuthUser(
    email: string,
    name?: string | null,
  ): Promise<AuthenticatedIdentity> {
    const existing = await this.repository.findByEmail(email);
    if (existing) {
      return this.toAuthenticatedIdentity(existing);
    }

    const baseNickname = this.createNickname(email, name);
    for (let suffix = 0; suffix < 100; suffix += 1) {
      const suffixValue = suffix === 0 ? '' : suffix.toString();
      const nickname = `${baseNickname.slice(0, 32 - suffixValue.length)}${suffixValue}`;
      if (!(await this.repository.findByNickname(nickname))) {
        const created = await this.repository.create({
          email,
          nickname,
          password: null,
        });
        return this.toAuthenticatedIdentity(created);
      }
    }

    throw new IdentityConflictError('Unable to allocate a unique nickname');
  }

  async getUser(userId: string): Promise<UserRow> {
    const user = await this.repository.findById(userId);
    if (!user) {
      throw new IdentityNotFoundError('User not found');
    }
    return user;
  }

  async getUserByEmail(email: string): Promise<UserRow | undefined> {
    return this.repository.findByEmail(email);
  }

  async getUserByNickname(nickname: string): Promise<UserRow | undefined> {
    return this.repository.findByNickname(nickname);
  }

  async updateCustomization(
    userId: string,
    customization: Customization,
  ): Promise<UserRow> {
    await this.getUser(userId);
    return this.repository.updateCustomization(userId, customization);
  }

  async updateNickname(userId: string, nickname: string): Promise<UserRow> {
    const existing = await this.repository.findByNickname(nickname);
    if (existing && existing.id !== userId) {
      throw new IdentityConflictError('Nickname is already registered');
    }
    await this.getUser(userId);
    return this.repository.updateNickname(userId, nickname);
  }

  async updatePassword(
    userId: string,
    currentPassword: string,
    newPassword: string,
  ): Promise<void> {
    const user = await this.getUser(userId);
    if (
      !user.password ||
      !(await this.passwordHasher.verify(currentPassword, user.password))
    ) {
      throw new IdentityUnauthorizedError('Invalid current password');
    }
    await this.repository.updatePassword(
      userId,
      this.passwordHasher.hash(newPassword),
    );
  }

  async deleteAccount(userId: string, password?: string): Promise<void> {
    await this.verifyPassword(userId, password);
    await this.repository.delete(userId);
  }

  async verifyPassword(userId: string, password?: string): Promise<void> {
    const user = await this.getUser(userId);
    if (!user.password) {
      return;
    }
    if (
      !password ||
      !(await this.passwordHasher.verify(password, user.password))
    ) {
      throw new IdentityUnauthorizedError('Invalid password');
    }
  }

  private createNickname(email: string, name?: string | null): string {
    const candidate = (name || email.split('@')[0] || 'user')
      .normalize('NFKD')
      .toLowerCase()
      .replace(/[^a-z0-9]/g, '')
      .slice(0, 24);
    return candidate.length >= 3 ? candidate : candidate.padEnd(3, '0');
  }

  private toAuthenticatedIdentity(user: UserRow): AuthenticatedIdentity {
    return {
      email: user.email,
      id: user.id,
      nickname: user.nickname,
    };
  }
}
