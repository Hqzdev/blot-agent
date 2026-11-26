import { InternalRequestSigner, InternalRequestVerifier } from '@teya/platform';
import {
  ConversationRpcController,
  ConversationService,
  PostgresConversationRepository,
} from '@teya/service-conversation';

let controller: ConversationRpcController | undefined;

function getController(): ConversationRpcController {
  if (controller) {
    return controller;
  }
  const secret = process.env.INTERNAL_SERVICE_SECRET;
  if (!secret) {
    throw new Error('INTERNAL_SERVICE_SECRET is required');
  }
  controller = new ConversationRpcController(
    new InternalRequestVerifier(new InternalRequestSigner(secret)),
    new ConversationService(new PostgresConversationRepository()),
  );
  return controller;
}

export default async function handler(request: Request): Promise<Response> {
  return getController().handle(request);
}
