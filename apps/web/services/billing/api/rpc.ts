import { getRpcController } from './composition';

export default function handler(request: Request): Promise<Response> {
  return getRpcController().handle(request);
}
