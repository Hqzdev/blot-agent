import { randomUUID } from 'node:crypto';
import { request as createHttpsRequest } from 'node:https';
import { Readable } from 'node:stream';

import { z } from 'zod';

import { GigaChatReasoningResponseAdapter } from './gigachat-reasoning';

const tokenResponseSchema = z.object({
  access_token: z.string().min(1),
  expires_at: z.number().positive(),
});

export type HttpFetch = (
  input: RequestInfo | URL,
  init?: RequestInit,
) => Promise<Response>;

interface TrustedHttpsClientOptions {
  certificate: string;
}

export class TrustedHttpsClient {
  private readonly certificate: string;

  constructor(options: TrustedHttpsClientOptions) {
    this.certificate = options.certificate;
  }

  async request(
    input: RequestInfo | URL,
    init?: RequestInit,
  ): Promise<Response> {
    const request = input instanceof Request ? input : undefined;
    const url = new URL(request?.url ?? input.toString());
    const headers = new Headers(request?.headers);
    new Headers(init?.headers).forEach((value, key) => {
      headers.set(key, value);
    });
    const body = await this.resolveBody(init?.body, request);

    return new Promise<Response>((resolve, reject) => {
      const outgoingRequest = createHttpsRequest(
        url,
        {
          ca: this.certificate,
          headers: Object.fromEntries(headers.entries()),
          method: init?.method ?? request?.method ?? 'GET',
        },
        (incomingResponse) => {
          const responseHeaders = new Headers();
          for (const [key, value] of Object.entries(incomingResponse.headers)) {
            if (Array.isArray(value)) {
              for (const entry of value) {
                responseHeaders.append(key, entry);
              }
            } else if (value !== undefined) {
              responseHeaders.set(key, value.toString());
            }
          }
          resolve(
            new Response(
              Readable.toWeb(incomingResponse) as ReadableStream<Uint8Array>,
              {
                headers: responseHeaders,
                status: incomingResponse.statusCode ?? 500,
                statusText: incomingResponse.statusMessage,
              },
            ),
          );
        },
      );
      const abort = () => {
        outgoingRequest.destroy(
          new DOMException('Request aborted', 'AbortError'),
        );
      };
      if (init?.signal?.aborted) {
        abort();
      } else {
        init?.signal?.addEventListener('abort', abort, { once: true });
      }
      outgoingRequest.once('close', () => {
        init?.signal?.removeEventListener('abort', abort);
      });
      outgoingRequest.once('error', reject);
      if (body !== undefined) {
        outgoingRequest.write(body);
      }
      outgoingRequest.end();
    });
  }

  private async resolveBody(
    body: BodyInit | null | undefined,
    request: Request | undefined,
  ): Promise<string | Uint8Array | undefined> {
    if (body !== undefined && body !== null) {
      return this.normalizeBody(body);
    }
    if (request?.body) {
      return new Uint8Array(await request.arrayBuffer());
    }
    return undefined;
  }

  private async normalizeBody(body: BodyInit): Promise<string | Uint8Array> {
    if (typeof body === 'string') {
      return body;
    }
    if (body instanceof URLSearchParams) {
      return body.toString();
    }
    if (body instanceof ArrayBuffer) {
      return new Uint8Array(body);
    }
    if (ArrayBuffer.isView(body)) {
      return new Uint8Array(body.buffer, body.byteOffset, body.byteLength);
    }
    if (body instanceof Blob) {
      return new Uint8Array(await body.arrayBuffer());
    }
    throw new Error('Unsupported GigaChat request body');
  }
}

export interface GigaChatTokenProvider {
  getAccessToken(): Promise<string>;
  invalidate(): void;
}

interface CachedToken {
  expiresAt: number;
  value: string;
}

interface GigaChatAccessTokenProviderOptions {
  authorizationKey: string;
  fetcher?: HttpFetch;
  now?: () => number;
  scope: string;
  tokenUrl?: string;
}

export class GigaChatAccessTokenProvider implements GigaChatTokenProvider {
  private cachedToken: CachedToken | undefined;
  private pendingToken: Promise<CachedToken> | undefined;
  private readonly authorizationKey: string;
  private readonly fetcher: HttpFetch;
  private readonly now: () => number;
  private readonly scope: string;
  private readonly tokenUrl: string;

  constructor(options: GigaChatAccessTokenProviderOptions) {
    this.authorizationKey = options.authorizationKey
      .replace(/^(Basic|Bearer)\s+/i, '')
      .trim();
    this.fetcher = options.fetcher ?? fetch;
    this.now = options.now ?? Date.now;
    this.scope = options.scope;
    this.tokenUrl =
      options.tokenUrl ?? 'https://ngw.devices.sberbank.ru:9443/api/v2/oauth';
  }

  async getAccessToken(): Promise<string> {
    if (this.isUsable(this.cachedToken)) {
      return this.cachedToken.value;
    }
    if (!this.pendingToken) {
      this.pendingToken = this.requestToken().finally(() => {
        this.pendingToken = undefined;
      });
    }
    this.cachedToken = await this.pendingToken;
    return this.cachedToken.value;
  }

  invalidate(): void {
    this.cachedToken = undefined;
  }

  private isUsable(token: CachedToken | undefined): token is CachedToken {
    return Boolean(token && token.expiresAt - this.now() > 60_000);
  }

  private async requestToken(): Promise<CachedToken> {
    if (!this.authorizationKey) {
      throw new Error('GIGACHAT_AUTH_KEY is required');
    }
    const response = await this.fetcher(this.tokenUrl, {
      body: new URLSearchParams({ scope: this.scope }),
      headers: {
        accept: 'application/json',
        authorization: `Basic ${this.authorizationKey}`,
        'content-type': 'application/x-www-form-urlencoded',
        RqUID: randomUUID(),
      },
      method: 'POST',
    });
    if (!response.ok) {
      throw new Error(`GigaChat authorization failed with ${response.status}`);
    }
    const result = tokenResponseSchema.parse(await response.json());
    return {
      expiresAt:
        result.expires_at > 10_000_000_000
          ? result.expires_at
          : result.expires_at * 1000,
      value: result.access_token,
    };
  }
}

interface GigaChatAuthenticatedClientOptions {
  fetcher?: HttpFetch;
  reasoningResponseAdapter?: GigaChatReasoningResponseAdapter;
  tokenProvider: GigaChatTokenProvider;
}

export class GigaChatAuthenticatedClient {
  private readonly fetcher: HttpFetch;
  private readonly reasoningResponseAdapter: GigaChatReasoningResponseAdapter;
  private readonly tokenProvider: GigaChatTokenProvider;

  constructor(options: GigaChatAuthenticatedClientOptions) {
    this.fetcher = options.fetcher ?? fetch;
    this.reasoningResponseAdapter =
      options.reasoningResponseAdapter ??
      new GigaChatReasoningResponseAdapter();
    this.tokenProvider = options.tokenProvider;
  }

  async request(
    input: RequestInfo | URL,
    init?: RequestInit,
  ): Promise<Response> {
    const includesReasoning =
      await this.reasoningResponseAdapter.matchesRequest(input, init);
    const response = await this.requestWithToken(
      input,
      init,
      await this.tokenProvider.getAccessToken(),
    );
    if (response.status !== 401) {
      return includesReasoning
        ? this.reasoningResponseAdapter.adapt(response)
        : response;
    }
    this.tokenProvider.invalidate();
    const retriedResponse = await this.requestWithToken(
      input,
      init,
      await this.tokenProvider.getAccessToken(),
    );
    return includesReasoning
      ? this.reasoningResponseAdapter.adapt(retriedResponse)
      : retriedResponse;
  }

  private requestWithToken(
    input: RequestInfo | URL,
    init: RequestInit | undefined,
    token: string,
  ): Promise<Response> {
    const headers = new Headers(
      input instanceof Request ? input.headers : undefined,
    );
    new Headers(init?.headers).forEach((value, key) => {
      headers.set(key, value);
    });
    headers.set('authorization', `Bearer ${token}`);
    return this.fetcher(input, { ...init, headers });
  }
}

interface GigaChatCompletionClientOptions {
  baseUrl?: string;
  client: GigaChatAuthenticatedClient;
  model: string;
}

const blotTierModels = {
  mini: 'GigaChat-2',
  pro: 'GigaChat-2-Pro',
  max: 'GigaChat-2-Max',
} as const;

export class GigaChatCompletionClient {
  private readonly baseUrl: string;
  private readonly client: GigaChatAuthenticatedClient;
  private readonly model: string;

  constructor(options: GigaChatCompletionClientOptions) {
    this.baseUrl = (options.baseUrl ?? 'https://api.giga.chat/v1').replace(
      /\/$/,
      '',
    );
    this.client = options.client;
    this.model = options.model;
  }

  complete(
    payload: Record<string, unknown>,
    signal: AbortSignal,
    tier?: keyof typeof blotTierModels,
  ): Promise<Response> {
    return this.client.request(`${this.baseUrl}/chat/completions`, {
      body: JSON.stringify({ ...payload, model: tier ? blotTierModels[tier] : this.model }),
      headers: {
        accept: 'application/json',
        'content-type': 'application/json',
      },
      method: 'POST',
      signal,
    });
  }
}
