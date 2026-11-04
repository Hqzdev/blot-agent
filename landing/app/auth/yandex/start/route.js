import { YandexSignIn } from "@/lib/auth/yandex-sign-in.mjs";

export const runtime = "nodejs";
export function GET(request) { return new YandexSignIn().start(request); }
