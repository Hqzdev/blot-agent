import { AuthError } from "../auth/errors.mjs";

const MAX_BODY = 240_000;
const TOOLS = new Set(["read_file", "list_files", "write_file", "edit_file", "bash"]);
const isObject = value => value !== null && typeof value === "object" && !Array.isArray(value);
const invalid = () => new AuthError("invalid_cli_model_request", 400);

async function readBody(request) {
  if (!request.headers.get("content-type")?.startsWith("application/json")) throw invalid();
  const reader = request.body?.getReader();
  if (!reader) throw invalid();
  let size = 0;
  const chunks = [];
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.length;
      if (size > MAX_BODY) throw new AuthError("cli_model_context_too_large", 413);
      chunks.push(Buffer.from(value));
    }
  } finally { await reader.cancel(); }
  try { return JSON.parse(Buffer.concat(chunks).toString("utf8")); }
  catch { throw invalid(); }
}

function messages(value, functions) {
  if (!Array.isArray(value) || value.length < 2 || value.length > 1000 || value[0]?.role !== "system") throw invalid();
  return value.map((row, index) => {
    if (!isObject(row) || typeof row.content !== "string") throw invalid();
    const { role, content } = row;
    if (index === 0 || role === "user") return { role, content };
    if (role === "function" && functions.has(row.name)) return { role, name: row.name, content };
    if (role !== "assistant") throw invalid();
    if (!row.function_call) return { role, content };
    const { name, arguments: args } = row.function_call;
    if (!functions.has(name) || !isObject(args)
        || typeof row.functions_state_id !== "string" || row.functions_state_id.length > 96) throw invalid();
    return { role, content, function_call: { name, arguments: args }, functions_state_id: row.functions_state_id };
  });
}

export class CliModel {
  #authenticate;
  #rate;
  #provider;
  #model;
  #context;
  #output;
  constructor({ authenticate, rate, provider, model, contextTokens, outputTokens }) {
    this.#authenticate = authenticate;
    this.#rate = rate;
    this.#provider = provider;
    this.#model = model;
    this.#context = contextTokens;
    this.#output = outputTokens;
  }

  async handle(request) {
    const header = request.headers.get("authorization");
    if (!/^Bearer [A-Za-z0-9_-]{43}$/.test(header ?? "")) throw new AuthError("session_required", 401);
    const account = await this.#authenticate(header.slice(7));
    if (request.method === "GET") return { model: this.#model, contextTokens: this.#context };
    const body = await readBody(request);
    if (!isObject(body) || !Number.isSafeInteger(body.max_tokens) || body.max_tokens < 1) throw invalid();
    const functions = body.functions ?? [];
    if (!Array.isArray(functions) || functions.length > TOOLS.size || functions.some(fn =>
      !isObject(fn) || !TOOLS.has(fn.name) || typeof fn.description !== "string"
      || fn.description.length > 300 || !isObject(fn.parameters))) throw invalid();
    const allowed = new Set(functions.map(fn => fn.name));
    if (allowed.size !== functions.length) throw invalid();
    const payload = {
      model: this.#model, messages: messages(body.messages, allowed),
      max_tokens: Math.min(body.max_tokens, this.#output), stream: false,
      ...(functions.length ? { functions, function_call: "auto" } : {}),
    };
    await this.#rate.check(`cli-model:minute:${account.id}`, 24, 60);
    await this.#rate.check(`cli-model:day:${account.id}`, 240, 86400);
    await this.#rate.check("cli-model:global:day", 2400, 86400);
    return this.#provider.complete(payload);
  }
}
