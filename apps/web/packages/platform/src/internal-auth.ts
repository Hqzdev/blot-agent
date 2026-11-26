import {
  createHash,
  createHmac,
  randomUUID,
  timingSafeEqual,
} from 'node:crypto';

export interface InternalSignatureInput {
  actorId: string;
  body: string;
  method: string;
  target: string;
  timestamp: number;
}

export interface InternalIdentity {
  actorId: string;
  requestId: string;
}

export class InternalRequestSigner {
  constructor(private readonly secret: string) {
    if (secret.length < 32) {
      throw new Error(
        'INTERNAL_SERVICE_SECRET must contain at least 32 characters',
      );
    }
  }

  sign(input: InternalSignatureInput): string {
    return createHmac('sha256', this.secret)
      .update(this.canonicalize(input))
      .digest('hex');
  }

  createHeaders(input: Omit<InternalSignatureInput, 'timestamp'>): Headers {
    const timestamp = Date.now();
    const headers = new Headers({
      'content-type': 'application/json',
      'x-teya-actor-id': input.actorId,
      'x-teya-request-id': randomUUID(),
      'x-teya-timestamp': timestamp.toString(),
    });
    headers.set(
      'x-teya-signature',
      this.sign({
        ...input,
        timestamp,
      }),
    );
    return headers;
  }

  private canonicalize(input: InternalSignatureInput): string {
    const bodyDigest = createHash('sha256').update(input.body).digest('hex');
    return [
      input.method.toUpperCase(),
      input.target,
      input.timestamp.toString(),
      input.actorId,
      bodyDigest,
    ].join('\n');
  }
}

export class InternalRequestVerifier {
  constructor(
    private readonly signer: InternalRequestSigner,
    private readonly toleranceMilliseconds = 60_000,
  ) {}

  verify(request: Request, body: string, now = Date.now()): InternalIdentity {
    const actorId = request.headers.get('x-teya-actor-id');
    const requestId = request.headers.get('x-teya-request-id');
    const signature = request.headers.get('x-teya-signature');
    const timestampValue = request.headers.get('x-teya-timestamp');

    if (!actorId || !requestId || !signature || !timestampValue) {
      throw new Error('Missing internal authentication headers');
    }

    const timestamp = Number(timestampValue);
    if (
      !Number.isSafeInteger(timestamp) ||
      Math.abs(now - timestamp) > this.toleranceMilliseconds
    ) {
      throw new Error('Expired internal request');
    }

    const url = new URL(request.url);
    const expected = this.signer.sign({
      actorId,
      body,
      method: request.method,
      target: `${url.pathname}${url.search}`,
      timestamp,
    });

    const actualBuffer = Buffer.from(signature, 'hex');
    const expectedBuffer = Buffer.from(expected, 'hex');
    if (
      actualBuffer.length !== expectedBuffer.length ||
      !timingSafeEqual(actualBuffer, expectedBuffer)
    ) {
      throw new Error('Invalid internal request signature');
    }

    return { actorId, requestId };
  }
}

export class InternalApiClient {
  private readonly signer: InternalRequestSigner;

  constructor(
    private readonly baseUrl: string,
    secret: string,
  ) {
    this.signer = new InternalRequestSigner(secret);
  }

  async request<T>({
    actorId,
    body,
    method = 'POST',
    path,
  }: {
    actorId: string;
    body?: unknown;
    method?: string;
    path: string;
  }): Promise<T> {
    const serializedBody = body === undefined ? '' : JSON.stringify(body);
    const targetUrl = new URL(path, this.baseUrl);
    const target = `${targetUrl.pathname}${targetUrl.search}`;
    const headers = this.signer.createHeaders({
      actorId,
      body: serializedBody,
      method,
      target,
    });
    const response = await fetch(targetUrl, {
      body: serializedBody || undefined,
      headers,
      method,
    });

    if (!response.ok) {
      const responseBody = await response.text();
      throw new Error(
        `Internal service request failed with ${response.status}: ${responseBody}`,
      );
    }

    return (await response.json()) as T;
  }
}
