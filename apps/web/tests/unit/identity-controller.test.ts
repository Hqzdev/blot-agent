import assert from 'node:assert/strict';
import test from 'node:test';

import type { Customization } from '@teya/contracts';
import type { UserRow } from '@teya/database';
import { InternalRequestSigner, InternalRequestVerifier } from '@teya/platform';
import {
  type CreateIdentityUser,
  IdentityRpcController,
  IdentityService,
  type IdentityUserRepository,
  PasswordHasher,
} from '@teya/service-identity';

const secret = 'a-secure-internal-secret-with-32-characters';
const userId = '11111111-1111-4111-8111-111111111111';
const otherUserId = '22222222-2222-4222-8222-222222222222';
const customization: Customization = {
  additional: '',
  nickname: 'Yaroslav',
  occupation: 'Developer',
  traits: ['Honest'],
};

class IdentityRepositoryFake implements IdentityUserRepository {
  readonly users = new Map<string, UserRow>([
    [userId, this.createRow(userId, 'owner@example.com', 'owner')],
    [otherUserId, this.createRow(otherUserId, 'other@example.com', 'other')],
  ]);

  async create(input: CreateIdentityUser): Promise<UserRow> {
    const row = this.createRow(
      '33333333-3333-4333-8333-333333333333',
      input.email,
      input.nickname,
      input.password,
    );
    this.users.set(row.id, row);
    return row;
  }

  async delete(id: string): Promise<void> {
    this.users.delete(id);
  }

  async findByEmail(email: string) {
    return [...this.users.values()].find((user) => user.email === email);
  }

  async findById(id: string) {
    return this.users.get(id);
  }

  async findByNickname(nickname: string) {
    return [...this.users.values()].find((user) => user.nickname === nickname);
  }

  async updateCustomization(id: string, value: unknown) {
    return this.update(id, { customization: value });
  }

  async updateNickname(id: string, nickname: string) {
    return this.update(id, { nickname });
  }

  async updatePassword(id: string, password: string) {
    return this.update(id, { password });
  }

  private createRow(
    id: string,
    email: string,
    nickname: string,
    password: string | null = null,
  ): UserRow {
    return {
      createdAt: new Date(),
      customization: null,
      email,
      id,
      nickname,
      password,
      updatedAt: new Date(),
    };
  }

  private update(id: string, values: Partial<UserRow>): UserRow {
    const current = this.users.get(id);
    assert.ok(current);
    const updated = { ...current, ...values, updatedAt: new Date() };
    this.users.set(id, updated);
    return updated;
  }
}

function createController(repository: IdentityRepositoryFake) {
  const signer = new InternalRequestSigner(secret);
  return {
    controller: new IdentityRpcController(
      new InternalRequestVerifier(signer),
      new IdentityService(repository, new PasswordHasher()),
    ),
    signer,
  };
}

function createRpcRequest(
  signer: InternalRequestSigner,
  actorId: string,
  body: unknown,
) {
  const serializedBody = JSON.stringify(body);
  return new Request('https://identity.example/api/rpc', {
    body: serializedBody,
    headers: signer.createHeaders({
      actorId,
      body: serializedBody,
      method: 'POST',
      target: '/api/rpc',
    }),
    method: 'POST',
  });
}

test('identity RPC rejects cross-user reads', async () => {
  const repository = new IdentityRepositoryFake();
  const { controller, signer } = createController(repository);
  const response = await controller.handle(
    createRpcRequest(signer, userId, {
      operation: 'getUserById',
      payload: { userId: otherUserId },
    }),
  );

  assert.equal(response.status, 403);
});

test('identity RPC ignores client identity and updates the signed actor', async () => {
  const repository = new IdentityRepositoryFake();
  const { controller, signer } = createController(repository);
  const response = await controller.handle(
    createRpcRequest(signer, userId, {
      operation: 'updateCustomization',
      payload: { customization },
    }),
  );

  assert.equal(response.status, 200);
  assert.deepEqual(repository.users.get(userId)?.customization, customization);
  assert.equal(repository.users.get(otherUserId)?.customization, null);
});

test('identity RPC rejects an unsigned profile update', async () => {
  const repository = new IdentityRepositoryFake();
  const { controller } = createController(repository);
  const response = await controller.handle(
    new Request('https://identity.example/api/rpc', {
      body: JSON.stringify({
        operation: 'updateCustomization',
        payload: { customization },
      }),
      method: 'POST',
    }),
  );

  assert.equal(response.status, 401);
  assert.equal(repository.users.get(userId)?.customization, null);
});

test('credential accounts require a valid password for deletion', async () => {
  const repository = new IdentityRepositoryFake();
  const passwordHasher = new PasswordHasher();
  const user = repository.users.get(userId);
  assert.ok(user);
  repository.users.set(userId, {
    ...user,
    password: passwordHasher.hash('correct-password'),
  });
  const { controller, signer } = createController(repository);

  const rejected = await controller.handle(
    createRpcRequest(signer, userId, {
      operation: 'deleteAccount',
      payload: {},
    }),
  );
  assert.equal(rejected.status, 401);
  assert.ok(repository.users.has(userId));

  const accepted = await controller.handle(
    createRpcRequest(signer, userId, {
      operation: 'deleteAccount',
      payload: { password: 'correct-password' },
    }),
  );
  assert.equal(accepted.status, 200);
  assert.equal(repository.users.has(userId), false);
});

test('OAuth accounts can confirm deletion without a password', async () => {
  const repository = new IdentityRepositoryFake();
  const { controller, signer } = createController(repository);

  const response = await controller.handle(
    createRpcRequest(signer, userId, {
      operation: 'deleteAccount',
      payload: {},
    }),
  );

  assert.equal(response.status, 200);
  assert.equal(repository.users.has(userId), false);
});
