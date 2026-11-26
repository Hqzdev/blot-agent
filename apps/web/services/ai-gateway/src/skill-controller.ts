import { type SkillOperation, skillOperationSchema } from '@teya/contracts';
import { InternalRequestVerifier } from '@teya/platform';
import { ZodError } from 'zod';

import {
  SkillForbiddenError,
  SkillNotFoundError,
  SkillValidationError,
} from './skill-errors';
import type { SkillService } from './skill-service';

export class SkillRpcController {
  constructor(
    private readonly verifier: InternalRequestVerifier,
    private readonly service: SkillService,
  ) {}

  async handle(request: Request): Promise<Response> {
    const body = await request.text();
    try {
      const identity = this.verifier.verify(request, body);
      const operation = skillOperationSchema.parse(JSON.parse(body));
      const result = await this.execute(identity.actorId, operation);
      return Response.json({ result });
    } catch (error) {
      if (error instanceof SyntaxError || error instanceof ZodError) {
        return Response.json({ error: 'Invalid request' }, { status: 400 });
      }
      if (error instanceof SkillValidationError) {
        return Response.json({ error: error.message }, { status: 400 });
      }
      if (error instanceof SkillNotFoundError) {
        return Response.json({ error: error.message }, { status: 404 });
      }
      if (error instanceof SkillForbiddenError) {
        return Response.json({ error: error.message }, { status: 403 });
      }
      return Response.json({ error: 'Unauthorized' }, { status: 401 });
    }
  }

  private execute(actorId: string, operation: SkillOperation) {
    if (operation.operation === 'deleteSkillUserData') {
      if (actorId !== 'system:web') {
        throw new SkillForbiddenError('Operation requires the web service');
      }
      return this.service.deleteUserData(operation.payload.userId);
    }
    if (actorId.startsWith('system:')) {
      throw new SkillForbiddenError('Operation requires a user actor');
    }
    switch (operation.operation) {
      case 'listSkills':
        return this.service.listSkills(actorId, operation.payload.query);
      case 'getSkill':
        return this.service.getSkill(actorId, operation.payload.id);
      case 'createSkill':
        return this.service.createSkill(actorId, operation.payload);
      case 'updateSkill':
        return this.service.updateSkill(
          actorId,
          operation.payload.id,
          operation.payload,
        );
      case 'deleteSkill':
        return this.service.deleteSkill(actorId, operation.payload.id);
      case 'installSkill':
        return this.service.installSkill(actorId, operation.payload.id);
      case 'uninstallSkill':
        return this.service.uninstallSkill(actorId, operation.payload.id);
      case 'getInstalledSkillSummaries':
        return this.service.getInstalledSkillSummaries(actorId);
      case 'loadInstalledSkill':
        return this.service.loadInstalledSkill(actorId, operation.payload.id);
    }
  }
}
