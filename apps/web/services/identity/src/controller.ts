import {
  type IdentityOperation,
  identityOperationSchema,
} from '@teya/contracts';
import { InternalRequestVerifier } from '@teya/platform';
import { ZodError } from 'zod';

import {
  IdentityConflictError,
  IdentityForbiddenError,
  IdentityNotFoundError,
  IdentityUnauthorizedError,
} from './errors';
import type { IdentityService } from './service';

export class IdentityRpcController {
  constructor(
    private readonly verifier: InternalRequestVerifier,
    private readonly service: IdentityService,
  ) {}

  async handle(request: Request): Promise<Response> {
    const body = await request.text();
    try {
      const identity = this.verifier.verify(request, body);
      const operation = identityOperationSchema.parse(JSON.parse(body));
      const result = await this.execute(identity.actorId, operation);
      return Response.json({ result });
    } catch (error) {
      if (error instanceof SyntaxError || error instanceof ZodError) {
        return Response.json({ error: 'Invalid request' }, { status: 400 });
      }
      if (error instanceof IdentityConflictError) {
        return Response.json({ error: error.message }, { status: 409 });
      }
      if (error instanceof IdentityNotFoundError) {
        return Response.json({ error: error.message }, { status: 404 });
      }
      if (error instanceof IdentityForbiddenError) {
        return Response.json({ error: error.message }, { status: 403 });
      }
      if (error instanceof IdentityUnauthorizedError) {
        return Response.json({ error: error.message }, { status: 401 });
      }
      return Response.json({ error: 'Unauthorized' }, { status: 401 });
    }
  }

  private async execute(actorId: string, operation: IdentityOperation) {
    if (
      ['authenticate', 'register', 'oauth'].includes(operation.operation) &&
      actorId !== 'system:web'
    ) {
      throw new IdentityForbiddenError('Operation requires the web service');
    }

    switch (operation.operation) {
      case 'authenticate':
        return this.service.authenticate(
          operation.payload.nickname,
          operation.payload.password,
        );
      case 'register':
        return this.service.register(
          operation.payload.email,
          operation.payload.password,
          operation.payload.nickname,
        );
      case 'oauth':
        return this.service.getOrCreateOAuthUser(
          operation.payload.email,
          operation.payload.name,
        );
      case 'getUserById':
        this.requireActorOrSystem(actorId, operation.payload.userId);
        return this.service.getUser(operation.payload.userId);
      case 'getUserByEmail':
        this.requireSystem(actorId);
        return this.service.getUserByEmail(operation.payload.email);
      case 'getUserByNickname':
        this.requireSystem(actorId);
        return this.service.getUserByNickname(operation.payload.nickname);
      case 'updateCustomization':
        return this.service.updateCustomization(
          this.requireUserActor(actorId),
          operation.payload.customization,
        );
      case 'updateNickname':
        return this.service.updateNickname(
          this.requireUserActor(actorId),
          operation.payload.nickname,
        );
      case 'updatePassword':
        return this.service.updatePassword(
          this.requireUserActor(actorId),
          operation.payload.currentPassword,
          operation.payload.newPassword,
        );
      case 'deleteAccount':
        return this.service.deleteAccount(
          this.requireUserActor(actorId),
          operation.payload.password,
        );
      case 'verifyPassword':
        return this.service.verifyPassword(
          this.requireUserActor(actorId),
          operation.payload.password,
        );
    }
  }

  private requireActorOrSystem(actorId: string, userId: string): void {
    if (actorId !== userId && actorId !== 'system:web') {
      throw new IdentityForbiddenError('Cross-user access is forbidden');
    }
  }

  private requireSystem(actorId: string): void {
    if (actorId !== 'system:web') {
      throw new IdentityForbiddenError('Operation requires the web service');
    }
  }

  private requireUserActor(actorId: string): string {
    if (actorId.startsWith('system:')) {
      throw new IdentityForbiddenError('Operation requires a user actor');
    }
    return actorId;
  }
}
