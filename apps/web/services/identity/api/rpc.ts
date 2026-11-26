import { InternalRequestSigner, InternalRequestVerifier } from '@teya/platform';
import {
  IdentityRpcController,
  IdentityService,
  PasswordHasher,
  PostgresIdentityUserRepository,
} from '@teya/service-identity';

let controller: IdentityRpcController | undefined;

function getController(): IdentityRpcController {
  if (controller) {
    return controller;
  }
  const secret = process.env.INTERNAL_SERVICE_SECRET;
  if (!secret) {
    throw new Error('INTERNAL_SERVICE_SECRET is required');
  }
  controller = new IdentityRpcController(
    new InternalRequestVerifier(new InternalRequestSigner(secret)),
    new IdentityService(
      new PostgresIdentityUserRepository(),
      new PasswordHasher(),
    ),
  );
  return controller;
}

export default async function handler(request: Request): Promise<Response> {
  return getController().handle(request);
}
