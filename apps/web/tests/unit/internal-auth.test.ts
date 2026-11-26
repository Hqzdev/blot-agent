import assert from 'node:assert/strict';
import test from 'node:test';

import { InternalRequestSigner, InternalRequestVerifier } from '@teya/platform';

const secret = 'a-secure-internal-secret-with-32-characters';

function createRequest(
  signer: InternalRequestSigner,
  body: string,
  actorId: string,
) {
  return new Request('https://identity.example/api/rpc', {
    body,
    headers: signer.createHeaders({
      actorId,
      body,
      method: 'POST',
      target: '/api/rpc',
    }),
    method: 'POST',
  });
}

test('internal signatures accept an authentic request', () => {
  const signer = new InternalRequestSigner(secret);
  const verifier = new InternalRequestVerifier(signer);
  const request = createRequest(signer, '{"operation":"health"}', 'user-1');

  assert.equal(
    verifier.verify(request, '{"operation":"health"}').actorId,
    'user-1',
  );
});

test('internal signatures reject a modified body', () => {
  const signer = new InternalRequestSigner(secret);
  const verifier = new InternalRequestVerifier(signer);
  const request = createRequest(signer, '{"plan":"free"}', 'user-1');

  assert.throws(() => verifier.verify(request, '{"plan":"team"}'));
});

test('internal signatures reject expired requests', () => {
  const signer = new InternalRequestSigner(secret);
  const verifier = new InternalRequestVerifier(signer);
  const request = createRequest(signer, '{}', 'user-1');

  assert.throws(() => verifier.verify(request, '{}', Date.now() + 61_000));
});
