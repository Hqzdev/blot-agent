import { YandexSignIn } from "@/lib/auth/yandex-sign-in.mjs";

export const runtime = "nodejs";
export async function GET(request) { return new YandexSignIn().callback(request); }
