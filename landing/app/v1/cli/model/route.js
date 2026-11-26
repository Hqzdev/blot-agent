import { accountDatabase } from "@/lib/accounts/database.mjs";
import { developmentDatabase } from "@/lib/accounts/development-database.mjs";
import { AccountRateLimiter } from "@/lib/accounts/security.mjs";
import { localAccountService } from "@/lib/accounts/service.mjs";
import { failure, json } from "@/lib/auth/route-support.mjs";
import { AuthError } from "@/lib/auth/errors.mjs";
import { GigaChat } from "@/lib/cli/gigachat.mjs";
import { CliModel } from "@/lib/cli/model.mjs";

export const runtime = "nodejs";
export const maxDuration = 90;

let model;
function getModel() {
  if (model) return model;
  const key = process.env.BLOT_GIGACHAT_AUTH_KEY || process.env.GIGACHAT_AUTH_KEY;
  if (!key) throw new AuthError("cli_model_unconfigured", 503);
  const database = process.env.NODE_ENV === "development" && process.env.BLOT_LOCAL_ACCOUNTS === "1"
    ? developmentDatabase() : accountDatabase();
  model = new CliModel({
    authenticate: token => localAccountService(database).authenticate(token),
    rate: new AccountRateLimiter(database),
    provider: new GigaChat({
      key,
      scope: process.env.BLOT_GIGACHAT_SCOPE || process.env.GIGACHAT_SCOPE || "GIGACHAT_API_PERS",
    }),
    model: process.env.BLOT_GIGACHAT_MODEL || process.env.GIGACHAT_MODEL || "GigaChat-2",
    contextTokens: Number(process.env.BLOT_GIGACHAT_CONTEXT_TOKENS) || 32768,
    outputTokens: Number(process.env.BLOT_GIGACHAT_OUTPUT_TOKENS) || 4096,
  });
  return model;
}

async function handle(request) {
  try {
    return json(await getModel().handle(request));
  } catch (error) { return failure(error); }
}
export const GET = handle;
export const POST = handle;
