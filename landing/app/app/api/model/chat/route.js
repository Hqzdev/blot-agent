import { forwardNativeChat } from "@/lib/model/native-chat.mjs";

export const runtime = "nodejs";

export function POST(request) {
  return forwardNativeChat(request);
}
