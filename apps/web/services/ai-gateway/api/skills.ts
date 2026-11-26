import { InternalRequestSigner, InternalRequestVerifier } from '@teya/platform';
import {
  PostgresSkillRepository,
  SkillRpcController,
  SkillService,
} from '@teya/service-ai-gateway';

let controller: SkillRpcController | undefined;

function getController(): SkillRpcController {
  if (controller) {
    return controller;
  }
  const secret = process.env.INTERNAL_SERVICE_SECRET;
  if (!secret) {
    throw new Error('INTERNAL_SERVICE_SECRET is required');
  }
  controller = new SkillRpcController(
    new InternalRequestVerifier(new InternalRequestSigner(secret)),
    new SkillService(new PostgresSkillRepository()),
  );
  return controller;
}

export default function handler(request: Request): Promise<Response> {
  return getController().handle(request);
}
