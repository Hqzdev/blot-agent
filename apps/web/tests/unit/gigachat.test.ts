import assert from 'node:assert/strict';
import { X509Certificate } from 'node:crypto';
import test from 'node:test';

import {
  GIGACHAT_REASONING_TAG,
  GigaChatAccessTokenProvider,
  GigaChatAuthenticatedClient,
  GigaChatImageGenerator,
  type HttpFetch,
  russianTrustedRootCertificate,
} from '@teya/service-ai-gateway';

function createTokenProvider() {
  return {
    async getAccessToken() {
      return 'access-token';
    },
    invalidate() {},
  };
}

function createFragmentedEventStreamResponse(content: string): Response {
  const encoder = new TextEncoder();
  const boundaries = [17, 53, 111].filter(
    (boundary) => boundary < content.length,
  );
  boundaries.push(content.length);
  let offset = 0;
  const body = new ReadableStream<Uint8Array>({
    pull(controller) {
      const boundary = boundaries.shift();
      if (boundary === undefined) {
        controller.close();
        return;
      }
      controller.enqueue(encoder.encode(content.slice(offset, boundary)));
      offset = boundary;
    },
  });

  return new Response(body, {
    headers: { 'content-type': 'text/event-stream' },
  });
}

test('bundled GigaChat root certificate matches the official fingerprint', () => {
  const certificate = new X509Certificate(russianTrustedRootCertificate);

  assert.equal(
    certificate.fingerprint256,
    'D2:6D:2D:02:31:B7:C3:9F:92:CC:73:85:12:BA:54:10:35:19:E4:40:5D:68:B5:BD:70:3E:97:88:CA:8E:CF:31',
  );
});

test('GigaChat access token is reused until the refresh window', async () => {
  let requests = 0;
  let currentTime = 1_800_000_000_000;
  const fetcher: HttpFetch = async () => {
    requests += 1;
    return Response.json({
      access_token: `token-${requests}`,
      expires_at: currentTime + 1_800_000,
    });
  };
  const provider = new GigaChatAccessTokenProvider({
    authorizationKey: 'authorization-key',
    fetcher,
    now: () => currentTime,
    scope: 'GIGACHAT_API_PERS',
  });

  assert.equal(await provider.getAccessToken(), 'token-1');
  assert.equal(await provider.getAccessToken(), 'token-1');
  assert.equal(requests, 1);

  currentTime += 1_750_000;

  assert.equal(await provider.getAccessToken(), 'token-2');
  assert.equal(requests, 2);
});

test('GigaChat client refreshes the token once after an unauthorized response', async () => {
  const tokens = ['expired-token', 'fresh-token'];
  let tokenIndex = 0;
  const tokenProvider = {
    async getAccessToken() {
      return tokens[tokenIndex];
    },
    invalidate() {
      tokenIndex += 1;
    },
  };
  const authorizations: string[] = [];
  const fetcher: HttpFetch = async (_input, init) => {
    const authorization = new Headers(init?.headers).get('authorization') || '';
    authorizations.push(authorization);
    return authorization === 'Bearer expired-token'
      ? new Response(null, { status: 401 })
      : Response.json({ choices: [] });
  };
  const client = new GigaChatAuthenticatedClient({
    fetcher,
    tokenProvider,
  });

  const response = await client.request(
    'https://api.giga.chat/v1/chat/completions',
  );

  assert.equal(response.status, 200);
  assert.deepEqual(authorizations, [
    'Bearer expired-token',
    'Bearer fresh-token',
  ]);
});

test('GigaChat client normalizes reasoning in JSON responses', async () => {
  const fetcher: HttpFetch = async () =>
    Response.json({
      choices: [
        {
          finish_reason: 'stop',
          index: 0,
          message: {
            content: 'Готовый ответ',
            reasoning_content: 'Проверяю условия',
            role: 'assistant',
          },
        },
      ],
    });
  const client = new GigaChatAuthenticatedClient({
    fetcher,
    tokenProvider: createTokenProvider(),
  });

  const response = await client.request(
    'https://api.giga.chat/v1/chat/completions',
    {
      body: JSON.stringify({
        messages: [{ content: 'Задача', role: 'user' }],
        reasoning_effort: 'medium',
      }),
      method: 'POST',
    },
  );
  const payload = (await response.json()) as {
    choices: Array<{
      message: {
        content: string;
        reasoning_content?: string;
      };
    }>;
  };

  assert.equal(
    payload.choices[0].message.content,
    `Проверяю условия</${GIGACHAT_REASONING_TAG}>Готовый ответ`,
  );
  assert.equal(payload.choices[0].message.reasoning_content, undefined);
});

test('GigaChat client normalizes fragmented reasoning event streams', async () => {
  const reasoningEvent = JSON.stringify({
    choices: [
      {
        delta: {
          reasoning_content: 'Проверяю условия',
          role: 'assistant',
        },
        index: 0,
      },
    ],
  });
  const answerEvent = JSON.stringify({
    choices: [
      {
        delta: { content: 'Готовый ответ' },
        finish_reason: null,
        index: 0,
      },
    ],
  });
  const eventStream = `data: ${reasoningEvent}\n\ndata: ${answerEvent}\n\ndata: [DONE]\n\n`;
  const fetcher: HttpFetch = async () =>
    createFragmentedEventStreamResponse(eventStream);
  const client = new GigaChatAuthenticatedClient({
    fetcher,
    tokenProvider: createTokenProvider(),
  });

  const response = await client.request(
    'https://api.giga.chat/v1/chat/completions',
    {
      body: JSON.stringify({
        messages: [{ content: 'Задача', role: 'user' }],
        reasoning_effort: 'medium',
        stream: true,
      }),
      method: 'POST',
    },
  );
  const dataLines = (await response.text())
    .split('\n')
    .filter((line) => line.startsWith('data: {'))
    .map((line) => JSON.parse(line.slice(6)));

  assert.equal(dataLines[0].choices[0].delta.content, 'Проверяю условия');
  assert.equal(
    dataLines[1].choices[0].delta.content,
    `</${GIGACHAT_REASONING_TAG}>Готовый ответ`,
  );
  assert.equal(dataLines[0].choices[0].delta.reasoning_content, undefined);
});

test('GigaChat client leaves standard model streams unchanged', async () => {
  const eventStream =
    'data: {"choices":[{"delta":{"content":"Обычный ответ"},"index":0}]}\n\ndata: [DONE]\n\n';
  const fetcher: HttpFetch = async () =>
    createFragmentedEventStreamResponse(eventStream);
  const client = new GigaChatAuthenticatedClient({
    fetcher,
    tokenProvider: createTokenProvider(),
  });

  const response = await client.request(
    'https://api.giga.chat/v1/chat/completions',
    {
      body: JSON.stringify({
        messages: [{ content: 'Вопрос', role: 'user' }],
        stream: true,
      }),
      method: 'POST',
    },
  );

  assert.equal(await response.text(), eventStream);
});

test('GigaChat image generator downloads the generated file', async () => {
  const fileId = 'a598ae3d-d3eb-454e-a8bf-0848193a603e';
  const requests: Array<{ body: string; method: string; url: string }> = [];
  const fetcher: HttpFetch = async (input, init) => {
    const url = input.toString();
    requests.push({
      body: typeof init?.body === 'string' ? init.body : '',
      method: init?.method ?? 'GET',
      url,
    });
    if (url.endsWith('/chat/completions')) {
      return Response.json({
        choices: [
          {
            message: {
              content: `<img src="${fileId}" fuse="true"/>`,
            },
          },
        ],
      });
    }
    return new Response(Uint8Array.from([255, 216, 255, 217]), {
      headers: { 'content-type': 'image/jpeg' },
    });
  };
  const generator = new GigaChatImageGenerator({
    client: new GigaChatAuthenticatedClient({
      fetcher,
      tokenProvider: createTokenProvider(),
    }),
    model: 'GigaChat',
  });

  const image = await generator.generate(
    'Розовый кот',
    new AbortController().signal,
  );

  assert.equal(image.base64, '/9j/2Q==');
  assert.equal(image.contentType, 'image/jpeg');
  assert.equal(requests[0].method, 'POST');
  assert.match(requests[0].body, /"function_call":"auto"/);
  assert.equal(
    requests[1].url,
    `https://api.giga.chat/v1/files/${fileId}/content`,
  );
  assert.equal(requests[1].method, 'GET');
});
