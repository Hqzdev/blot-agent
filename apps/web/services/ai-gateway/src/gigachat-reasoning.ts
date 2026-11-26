export const GIGACHAT_REASONING_TAG = 'teya_reasoning';

type JsonRecord = Record<string, unknown>;
type OutputPhase = 'reasoning' | 'answer';

function isJsonRecord(value: unknown): value is JsonRecord {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

class GigaChatReasoningPayloadTransformer {
  private readonly phases = new Map<number, OutputPhase>();
  private readonly openingTag = `<${GIGACHAT_REASONING_TAG}>`;
  private readonly closingTag = `</${GIGACHAT_REASONING_TAG}>`;

  transform(serializedPayload: string): string {
    try {
      return JSON.stringify(this.transformValue(JSON.parse(serializedPayload)));
    } catch {
      return serializedPayload;
    }
  }

  private transformValue(value: unknown): unknown {
    if (!isJsonRecord(value) || !Array.isArray(value.choices)) {
      return value;
    }

    return {
      ...value,
      choices: value.choices.map((choice, position) =>
        this.transformChoice(choice, position),
      ),
    };
  }

  private transformChoice(choice: unknown, position: number): unknown {
    if (!isJsonRecord(choice)) {
      return choice;
    }

    const choiceIndex =
      typeof choice.index === 'number' ? choice.index : position;

    if (isJsonRecord(choice.delta)) {
      return {
        ...choice,
        delta: this.transformContent(choice.delta, choiceIndex),
      };
    }

    if (isJsonRecord(choice.message)) {
      return {
        ...choice,
        message: this.transformContent(choice.message, choiceIndex),
      };
    }

    return choice;
  }

  private transformContent(
    contentPart: JsonRecord,
    choiceIndex: number,
  ): JsonRecord {
    const reasoning =
      typeof contentPart.reasoning_content === 'string'
        ? contentPart.reasoning_content
        : undefined;
    const content =
      typeof contentPart.content === 'string'
        ? contentPart.content
        : contentPart.content === null
          ? ''
          : undefined;

    if (reasoning === undefined && content === undefined) {
      return contentPart;
    }

    let phase = this.phases.get(choiceIndex) ?? 'reasoning';
    let normalizedContent = '';

    if (reasoning !== undefined) {
      if (phase === 'answer') {
        normalizedContent += this.openingTag;
      }
      normalizedContent += reasoning;
      phase = 'reasoning';
    }

    if (content !== undefined) {
      if (phase === 'reasoning') {
        normalizedContent += this.closingTag;
      }
      normalizedContent += content;
      phase = 'answer';
    }

    this.phases.set(choiceIndex, phase);

    return {
      ...Object.fromEntries(
        Object.entries(contentPart).filter(
          ([key]) => key !== 'reasoning_content',
        ),
      ),
      content: normalizedContent,
    };
  }
}

class GigaChatReasoningEventStreamTransformer {
  private buffer = '';
  private readonly payloadTransformer =
    new GigaChatReasoningPayloadTransformer();

  transform(chunk: string): string {
    this.buffer += chunk;
    let transformed = '';

    while (true) {
      const delimiterMatch = /\r?\n\r?\n/.exec(this.buffer);
      if (!delimiterMatch || delimiterMatch.index === undefined) {
        return transformed;
      }

      const frame = this.buffer.slice(0, delimiterMatch.index);
      const delimiter = delimiterMatch[0];
      this.buffer = this.buffer.slice(delimiterMatch.index + delimiter.length);
      transformed += this.transformFrame(frame) + delimiter;
    }
  }

  flush(): string {
    const transformed = this.transformFrame(this.buffer);
    this.buffer = '';
    return transformed;
  }

  private transformFrame(frame: string): string {
    const lineEnding = frame.includes('\r\n') ? '\r\n' : '\n';

    return frame
      .split(/\r?\n/)
      .map((line) => this.transformLine(line))
      .join(lineEnding);
  }

  private transformLine(line: string): string {
    if (!line.startsWith('data:')) {
      return line;
    }

    const dataWithSpacing = line.slice(5);
    const spacing = dataWithSpacing.match(/^\s*/)?.[0] ?? '';
    const data = dataWithSpacing.slice(spacing.length);
    if (data === '[DONE]') {
      return line;
    }

    return `data:${spacing}${this.payloadTransformer.transform(data)}`;
  }
}

export class GigaChatReasoningResponseAdapter {
  async matchesRequest(
    input: RequestInfo | URL,
    init?: RequestInit,
  ): Promise<boolean> {
    const body = await this.readRequestBody(input, init);
    if (!body) {
      return false;
    }

    try {
      const payload = JSON.parse(body);
      if (!isJsonRecord(payload)) {
        return false;
      }
      if (typeof payload.reasoning_effort === 'string') {
        return true;
      }
      if (!isJsonRecord(payload.model_options)) {
        return false;
      }
      if (!isJsonRecord(payload.model_options.reasoning)) {
        return false;
      }
      return typeof payload.model_options.reasoning.effort === 'string';
    } catch {
      return false;
    }
  }

  async adapt(response: Response): Promise<Response> {
    if (!response.ok || !response.body) {
      return response;
    }

    const contentType = response.headers.get('content-type') ?? '';
    if (contentType.includes('text/event-stream')) {
      return this.adaptEventStream(response);
    }
    if (contentType.includes('application/json')) {
      return this.adaptJson(response);
    }
    return response;
  }

  private async readRequestBody(
    input: RequestInfo | URL,
    init?: RequestInit,
  ): Promise<string | undefined> {
    const body = init?.body;
    if (typeof body === 'string') {
      return body;
    }
    if (body instanceof URLSearchParams) {
      return body.toString();
    }
    if (body instanceof ArrayBuffer) {
      return new TextDecoder().decode(body);
    }
    if (ArrayBuffer.isView(body)) {
      return new TextDecoder().decode(
        new Uint8Array(body.buffer, body.byteOffset, body.byteLength),
      );
    }
    if (body instanceof Blob) {
      return body.text();
    }
    if (input instanceof Request) {
      return input.clone().text();
    }
    return undefined;
  }

  private adaptEventStream(response: Response): Response {
    const eventTransformer = new GigaChatReasoningEventStreamTransformer();
    const body = response.body
      ?.pipeThrough(new TextDecoderStream())
      .pipeThrough(
        new TransformStream<string, string>({
          transform(chunk, controller) {
            const transformed = eventTransformer.transform(chunk);
            if (transformed) {
              controller.enqueue(transformed);
            }
          },
          flush(controller) {
            const transformed = eventTransformer.flush();
            if (transformed) {
              controller.enqueue(transformed);
            }
          },
        }),
      )
      .pipeThrough(new TextEncoderStream());

    return this.createResponse(response, body);
  }

  private async adaptJson(response: Response): Promise<Response> {
    const payloadTransformer = new GigaChatReasoningPayloadTransformer();
    const body = payloadTransformer.transform(await response.text());
    return this.createResponse(response, body);
  }

  private createResponse(
    response: Response,
    body: BodyInit | null | undefined,
  ): Response {
    const headers = new Headers(response.headers);
    headers.delete('content-encoding');
    headers.delete('content-length');
    return new Response(body, {
      headers,
      status: response.status,
      statusText: response.statusText,
    });
  }
}
